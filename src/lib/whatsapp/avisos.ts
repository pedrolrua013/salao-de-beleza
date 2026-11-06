// Convites de retorno e avisos de vaga da lista de espera. O banco decide quem e quando (programar_retornos, avisar_lista_espera);
// aqui montamos a mensagem com o link de agendamento já preenchido e registramos o envio.
import type { SupabaseClient } from "@supabase/supabase-js";
import { enviarModelo, type ContaMeta, type Modelo } from "./meta.ts";

export type TipoAviso = "retorno" | "vaga" | "avaliacao" | "aniversario" | "campanha";

/** Modelos para cadastrar na Meta. Retorno é "Marketing" (cobrado como marketing); vaga é "Utilidade". Sem botões: o link vai no texto. */
export const MODELOS_AVISO: Record<TipoAviso, { nome: string; categoria: string; corpo: string }> = {
  retorno: {
    nome: "belezando_retorno",
    categoria: "Marketing",
    corpo: "Olá, {{1}}! Já faz {{2}} dias do seu {{3}} em {{4}}. Que tal marcar o próximo? É só escolher o horário aqui: {{5}}",
  },
  avaliacao: {
    nome: "belezando_avaliacao",
    categoria: "Marketing",
    corpo: "Olá, {{1}}! Obrigado pela visita ao {{2}}. De 0 a 10, quanto você recomendaria a gente para uma amiga? Leva 10 segundos: {{3}}",
  },
  aniversario: {
    nome: "belezando_aniversario",
    categoria: "Marketing",
    corpo: "Feliz aniversário, {{1}}! 🎉 Hoje o {{2}} quer comemorar com você: {{3}}. Marque seu horário: {{4}}",
  },
  campanha: {
    nome: "belezando_campanha",
    categoria: "Marketing",
    corpo: "Olá, {{1}}! {{2}} Para marcar: {{3}} Responda PARAR para não receber mais.",
  },
  vaga: {
    nome: "belezando_vaga",
    categoria: "Utilidade",
    corpo: "Olá, {{1}}! Abriu um horário para {{2}} em {{3}}: {{4}}, às {{5}}. Você estava na lista de espera. Quem marcar primeiro fica com ele: {{6}}",
  },
};

export type AvisoReservado = {
  id: string; salao_id: string; tipo: TipoAviso; wa_id: string; cliente_nome: string; salao_nome: string; slug: string; fuso: string;
  dados: { servico?: string; servico_id?: string; profissional_id?: string; inicio?: string; dias?: number; servico_nome?: string; token?: string; credito?: number; ate?: string; texto?: string; campanha_id?: string };
};

const primeiroNome = (n: string) => n.trim().split(/\s+/)[0] || "cliente";

/** Parâmetros na ordem do modelo. O link leva direto ao serviço (e, na vaga, ao dia e horário). */
export function parametrosAviso(a: AvisoReservado, site: string, servicoNome: string): string[] {
  const base = `${site}/s/${a.slug}`;
  if (a.tipo === "aniversario") {
    const credito = Number(a.dados.credito ?? 0);
    const presente = credito > 0
      ? `um presente de ${(credito / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })} para usar até ${a.dados.ate}`
      : "um carinho especial na sua próxima visita";
    return [primeiroNome(a.cliente_nome), a.salao_nome, presente, base];
  }
  // Campanha: o texto vai numa linha só (o WhatsApp não aceita quebra de linha em parâmetro de modelo).
  if (a.tipo === "campanha") return [primeiroNome(a.cliente_nome), (a.dados.texto ?? "").replace(/\s+/g, " ").trim().slice(0, 500), base];
  if (a.tipo === "avaliacao") return [primeiroNome(a.cliente_nome), a.salao_nome, `${base}/avaliar/${a.dados.token}`];
  if (a.tipo === "retorno") {
    return [primeiroNome(a.cliente_nome), String(a.dados.dias ?? ""), a.dados.servico ?? servicoNome, a.salao_nome, `${base}?servico=${a.dados.servico_id}`];
  }
  const d = new Date(a.dados.inicio!);
  const dia = new Intl.DateTimeFormat("pt-BR", { timeZone: a.fuso, weekday: "long", day: "2-digit", month: "2-digit" }).format(d).replace(",", "");
  const hora = new Intl.DateTimeFormat("pt-BR", { timeZone: a.fuso, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d);
  const ymd = new Intl.DateTimeFormat("en-CA", { timeZone: a.fuso, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
  const link = `${base}?servico=${a.dados.servico_id}&prof=${a.dados.profissional_id}&dia=${ymd}&hora=${hora}`;
  return [primeiroNome(a.cliente_nome), servicoNome, a.salao_nome, dia, hora, link];
}

export function textoDoAviso(a: AvisoReservado, params: string[]): string {
  return MODELOS_AVISO[a.tipo].corpo.replace(/\{\{(\d)\}\}/g, (_, n) => params[Number(n) - 1] ?? "");
}

export type BalancoAvisos = { reservados: number; enviados: number; falhas: number };

export async function executarAvisos(db: SupabaseClient, site: string, f: typeof fetch = fetch, limite = 20): Promise<BalancoAvisos> {
  const { data, error } = await db.rpc("reservar_avisos", { p_limite: limite });
  if (error) throw new Error(`reservar_avisos: ${error.message}`);
  const lista = (data ?? []) as AvisoReservado[];
  const contas = new Map<string, ContaMeta | null>();
  const nomes = new Map<string, string>();
  const balanco: BalancoAvisos = { reservados: lista.length, enviados: 0, falhas: 0 };
  for (const a of lista) {
    try {
      if (!contas.has(a.salao_id)) {
        const { data: c } = await db.from("whatsapp_contas").select("phone_number_id, token").eq("salao_id", a.salao_id).maybeSingle();
        contas.set(a.salao_id, c ? { phone_number_id: c.phone_number_id, token: c.token } : null);
      }
      const conta = contas.get(a.salao_id);
      if (!conta) {
        await db.rpc("concluir_aviso", { p_id: a.id, p_ok: false, p_wa_msg_id: null, p_erro: "WhatsApp não conectado neste salão", p_definitivo: true });
        balanco.falhas++;
        continue;
      }
      const sid = a.dados.servico_id ?? "";
      if (sid && !nomes.has(sid)) {
        const { data: s } = await db.from("servicos").select("nome").eq("id", sid).maybeSingle();
        nomes.set(sid, (s?.nome as string) ?? "seu serviço");
      }
      const params = parametrosAviso(a, site, nomes.get(sid) ?? "seu serviço");
      const modelo: Modelo = { nome: MODELOS_AVISO[a.tipo].nome, parametros: params, botoes: [] };
      const r = await enviarModelo(conta, a.wa_id, modelo, f);
      await db.rpc("concluir_aviso", { p_id: a.id, p_ok: r.ok, p_wa_msg_id: r.ok ? r.msgId : null, p_erro: r.ok ? null : r.erro, p_definitivo: r.ok ? false : r.definitivo === true });
      r.ok ? balanco.enviados++ : balanco.falhas++;
      const { data: conversaId } = await db.rpc("abrir_conversa", { p_salao: a.salao_id, p_wa_id: a.wa_id, p_nome: a.cliente_nome });
      if (conversaId) {
        await db.from("mensagens").insert({
          salao_id: a.salao_id, conversa_id: conversaId, direcao: "saida", autor: "robo", tipo: "modelo",
          corpo: textoDoAviso(a, params), wa_msg_id: r.ok ? r.msgId : null, erro: r.ok ? null : r.erro,
        });
      }
    } catch (e) {
      balanco.falhas++;
      console.error("[avisos] erro ao enviar", { aviso: a.id, erro: e instanceof Error ? e.message : String(e) });
      await db.rpc("concluir_aviso", { p_id: a.id, p_ok: false, p_wa_msg_id: null, p_erro: "erro interno ao enviar", p_definitivo: false });
    }
  }
  return balanco;
}
