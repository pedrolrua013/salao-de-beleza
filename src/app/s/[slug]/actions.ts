"use server";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { zonedToUtc } from "@/lib/slots";
import { pixCopiaECola } from "@/lib/pix";
import { criarPixMP } from "@/lib/pagamentos/mercadopago";
import type { Estado } from "@/components/acao-form";
import { ipDoCliente } from "@/lib/limite";

const ERROS: Record<string, string> = {
  horario_indisponivel: "Esse horário acabou de ser ocupado. Escolha outro.",
  nome_telefone: "Informe seu nome e um celular com DDD.",
  "consentimento obrigatório": "Para marcar, é preciso aceitar receber a confirmação e os lembretes.",
  limite_agendamentos: "Você já tem 3 horários marcados. Para marcar mais, fale com o salão.",
  salao_indisponivel: "O agendamento online deste salão está desligado.",
  cliente_bloqueada: "Não foi possível marcar pelo link. Fale com o salão pelo WhatsApp.",
  muitas_tentativas: "Muitos agendamentos seguidos. Tente de novo mais tarde ou fale com o salão.",
};

/** Marca pelo link público. Roda no servidor com a chave de serviço; o banco confere tudo de novo (horário livre, jornada, aceite). */
export async function agendarOnline(_: Estado, f: FormData): Promise<Estado> {
  const db = clienteAdmin();
  if (!db) return { erro: "Agendamento indisponível no momento." };
  const slug = String(f.get("slug") ?? ""), dia = String(f.get("dia") ?? ""), hora = String(f.get("hora") ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia) || !/^\d{2}:\d{2}$/.test(hora)) return { erro: "Escolha o dia e o horário." };
  if (f.get("politica") !== "on") return { erro: "Leia e aceite a política de cancelamento." };
  const { data: salao } = await db.from("saloes").select("id, nome, fuso, pix_chave, pix_nome, pix_cidade").eq("slug", slug).maybeSingle();
  if (!salao) return { erro: "Salão não encontrado." };
  const h = await headers();
  const ip = ipDoCliente(h);
  // Cada item é "servico" ou "servico~tamanho".
  const itens = f.getAll("servicos").map(String).filter((x) => /^[0-9a-f-]{36}(~[0-9a-f-]{36})?$/.test(x)).slice(0, 4);
  if (itens.length === 0) return { erro: "Escolha o serviço." };
  const servicos = itens.map((x) => x.split("~")[0]), variacoes = itens.map((x) => x.split("~")[1] ?? null);
  const { data, error } = await db.rpc("agendar_online_grupo", {
    p_slug: slug, p_servicos: servicos, p_variacoes: variacoes, p_profissional: String(f.get("profissional")),
    p_inicio: zonedToUtc(dia, hora, salao.fuso).toISOString(),
    p_nome: String(f.get("nome") ?? "").trim(), p_telefone: String(f.get("telefone") ?? ""),
    p_aceite_contato: f.get("contato") === "on", p_ip: ip, p_agente: (h.get("user-agent") ?? "").slice(0, 300) || null,
  });
  if (error || !data) return { erro: Object.entries(ERROS).find(([k]) => error?.message?.includes(k))?.[1] ?? "Não foi possível marcar. Tente outro horário." };
  const r = data as { agendamento_id: string; token: string; sinal_centavos: number; cliente_novo: boolean };
  if (r.sinal_centavos > 0) await gerarCobranca(db, salao, r);
  // Só cliente nova recebe a ficha (quem digita o telefone de alguém já cadastrado não abre a ficha dela).
  const { data: ficha } = r.cliente_novo ? await db.rpc("criar_link_ficha_online", { p_agendamento: r.agendamento_id }) : { data: null };
  if (r.cliente_novo) {
    const ind = String(f.get("ind") ?? ""), origem = String(f.get("o") ?? "");
    if (ind || origem) await db.rpc("vincular_origem", { p_agendamento: r.agendamento_id, p_codigo: ind, p_origem: origem });
  }
  // A área da cliente (próximos horários, cashback, pacotes) vai junto, só para quem acabou de se cadastrar pelo link.
  const { data: area } = r.cliente_novo ? await db.rpc("link_cliente_online", { p_agendamento: r.agendamento_id }) : { data: null };
  const extras = new URLSearchParams();
  if (ficha) extras.set("ficha", String(ficha));
  if (area) extras.set("area", String(area));
  redirect(`/s/${slug}/h/${r.token}${extras.size ? `?${extras}` : ""}`);
}

type SalaoPix = { id: string; nome: string; pix_chave: string | null; pix_nome: string | null; pix_cidade: string | null };

/** Gera o Pix do sinal: dinâmico no Mercado Pago (confirma sozinho) ou estático na chave do salão (a recepção confirma). */
async function gerarCobranca(db: NonNullable<ReturnType<typeof clienteAdmin>>, salao: SalaoPix, r: { agendamento_id: string; sinal_centavos: number }) {
  const txid = `S${r.agendamento_id.replace(/-/g, "").slice(0, 24)}`;
  const { data: sinal } = await db.from("sinais").select("modo, expira_em").eq("agendamento_id", r.agendamento_id).maybeSingle();
  if (sinal?.modo === "mercadopago") {
    const { data: conta } = await db.from("pagamentos_contas").select("mp_access_token").eq("salao_id", salao.id).maybeSingle();
    if (conta?.mp_access_token) {
      try {
        const site = process.env.NEXT_PUBLIC_SITE_URL;
        const pix = await criarPixMP({
          token: conta.mp_access_token, valorCentavos: r.sinal_centavos, descricao: `Sinal ${salao.nome}`, referencia: r.agendamento_id,
          expiraEm: new Date(sinal.expira_em), avisoUrl: site ? `${site}/api/pagamentos/mercadopago?salao=${salao.id}` : undefined,
        });
        await db.rpc("registrar_cobranca_sinal", { p_agendamento: r.agendamento_id, p_txid: txid, p_copia_cola: pix.copiaECola, p_mp_payment_id: pix.id, p_modo: "mercadopago" });
        return;
      } catch (e) {
        console.error("[sinal] Mercado Pago falhou, usando Pix da chave", e instanceof Error ? e.message : e);
      }
    }
  }
  if (salao.pix_chave) {
    const copia = pixCopiaECola({ chave: salao.pix_chave, nome: salao.pix_nome || salao.nome, cidade: salao.pix_cidade || "BRASIL", valorCentavos: r.sinal_centavos, txid });
    await db.rpc("registrar_cobranca_sinal", { p_agendamento: r.agendamento_id, p_txid: txid, p_copia_cola: copia, p_mp_payment_id: null, p_modo: "pix_manual" });
  }
}

export async function cancelarOnline(f: FormData) {
  const db = clienteAdmin();
  const token = String(f.get("token") ?? ""), slug = String(f.get("slug") ?? "");
  if (db && /^[0-9a-f-]{36}$/.test(token)) await db.rpc("cancelar_online", { p_token: token });
  redirect(`/s/${slug}/h/${token}`);
}

const REMARCAR: Record<string, string> = {
  horario_indisponivel: "Esse horário acabou de ser ocupado. Escolha outro.",
  fora_do_prazo: "Já passou do prazo para remarcar pelo link. Fale com o salão.",
  ja_cancelado: "Esse horário já foi cancelado.",
  varios_profissionais: "Seu atendimento tem mais de um profissional: para remarcar, fale com o salão.",
};

/** A cliente troca o próprio horário pelo link: o antigo só é liberado se o novo couber. */
export async function remarcarOnline(_: Estado, f: FormData): Promise<Estado> {
  const db = clienteAdmin();
  if (!db) return { erro: "Indisponível no momento." };
  const slug = String(f.get("slug") ?? ""), token = String(f.get("token") ?? ""), dia = String(f.get("dia") ?? ""), hora = String(f.get("hora") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(token) || !/^\d{4}-\d{2}-\d{2}$/.test(dia) || !/^\d{2}:\d{2}$/.test(hora)) return { erro: "Escolha o dia e o horário." };
  const { data: salao } = await db.from("saloes").select("fuso").eq("slug", slug).maybeSingle();
  if (!salao) return { erro: "Salão não encontrado." };
  const { data } = await db.rpc("remarcar_online", { p_token: token, p_inicio: zonedToUtc(dia, hora, salao.fuso).toISOString(), p_profissional: String(f.get("profissional") ?? "") });
  if (data !== "remarcado") return { erro: REMARCAR[String(data)] ?? "Não foi possível remarcar. Tente outro horário." };
  redirect(`/s/${slug}/h/${token}`);
}
