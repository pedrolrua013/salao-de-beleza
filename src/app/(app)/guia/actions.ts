"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { lerReais } from "@/lib/dinheiro";
import { fasesDoFormulario } from "@/lib/fases";
import { enderecoEmLinha, formatarCep, UFS } from "@/lib/cep";
import type { Estado } from "@/components/acao-form";

const NOVOS = 3;

/** Passo 1: nome, contato, endereço e horário de funcionamento. */
export async function guiaSalao(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador configura o salão." };
  const nome = String(f.get("nome") ?? "").trim();
  const abre = String(f.get("abre") ?? ""), fecha = String(f.get("fecha") ?? "");
  const dias = f.getAll("dias").map(Number).filter((n) => n >= 1 && n <= 7);
  if (nome.length < 2) return { erro: "Informe o nome do salão." };
  if (dias.length === 0) return { erro: "Marque pelo menos um dia de atendimento." };
  if (!/^\d{2}:\d{2}$/.test(abre) || !/^\d{2}:\d{2}$/.test(fecha) || fecha <= abre) return { erro: "O horário de fechamento precisa ser depois da abertura." };
  const tel = String(f.get("telefone") ?? "").replace(/\D/g, "");
  if (tel && !/^\d{10,11}$/.test(tel)) return { erro: "Telefone inválido. Use DDD e número." };
  const t = (k: string, max: number) => String(f.get(k) ?? "").trim().replace(/\s+/g, " ").slice(0, max);
  const uf = t("uf", 2).toUpperCase();
  const cep = String(f.get("cep") ?? "").replace(/\D/g, "");
  const linha = enderecoEmLinha({ logradouro: t("logradouro", 100), numero: t("numero", 20), complemento: t("complemento", 40), bairro: t("bairro", 60), cidade: t("cidade", 60), uf: UFS.includes(uf) ? uf : "" });
  const endereco = linha ? `${linha}${cep.length === 8 ? ` · CEP ${formatarCep(cep)}` : ""}`.slice(0, 200) : salao.endereco; // em branco: mantém o que já tinha
  const { error } = await supabase.from("saloes").update({ nome, abre, fecha, dias_semana: dias, telefone: tel || null, endereco }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar. Tente de novo." };
  revalidatePath("/", "layout");
  redirect("/guia?passo=2");
}

/** Passo 2: quais serviços o salão faz, com preço e tempo; e os que faltam. */
export async function guiaServicos(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera os serviços." };
  const ids = f.getAll("id").map(String).filter((x) => /^[0-9a-f-]{36}$/.test(x));
  const { data: atuais } = await supabase.from("servicos").select("id, nome, fases").in("id", ids.length ? ids : ["00000000-0000-0000-0000-000000000000"]);
  let ativos = 0;
  const mudancas: { id: string; dados: Record<string, unknown> }[] = [];
  for (const s of atuais ?? []) {
    const ativo = f.get(`ativo_${s.id}`) === "on";
    const preco = lerReais(String(f.get(`preco_${s.id}`) ?? ""));
    if (ativo && preco === null && String(f.get(`preco_${s.id}`) ?? "").trim()) return { erro: `Confira o preço de ${s.nome}.` };
    const dados: Record<string, unknown> = { ativo, preco_centavos: preco ?? 0 };
    const min = f.get(`min_${s.id}`);
    if (min !== null && (s.fases as unknown[]).length === 1) {
      const fases = fasesDoFormulario(Number(min), 0, 0);
      if (!fases) return { erro: `O tempo de ${s.nome} precisa ficar entre 10 e 480 minutos.` };
      Object.assign(dados, { fases, duracao_min: fases[0].min });
    }
    if (ativo) ativos++;
    mudancas.push({ id: s.id, dados });
  }
  const novos: Record<string, unknown>[] = [];
  for (let i = 0; i < NOVOS; i++) {
    const nome = String(f.get(`novo_nome_${i}`) ?? "").trim().slice(0, 80);
    if (!nome) continue;
    if (nome.length < 2) return { erro: "Nome de serviço muito curto." };
    const fases = fasesDoFormulario(Number(f.get(`novo_min_${i}`) || 0), 0, 0);
    if (!fases) return { erro: `Informe o tempo de ${nome} (entre 10 e 480 minutos).` };
    const preco = lerReais(String(f.get(`novo_preco_${i}`) ?? ""));
    novos.push({ nome, fases, duracao_min: fases[0].min, preco_centavos: preco ?? 0 });
  }
  if (ativos + novos.length === 0) return { erro: "Deixe marcado pelo menos um serviço que o salão faz." };
  for (const m of mudancas) {
    const { error } = await supabase.from("servicos").update(m.dados).eq("id", m.id);
    if (error) return { erro: "Não foi possível salvar os serviços." };
  }
  if (novos.length) {
    const { error } = await supabase.from("servicos").insert(novos);
    if (error) return { erro: "Não foi possível adicionar os serviços novos." };
  }
  revalidatePath("/catalogos");
  redirect("/guia?passo=3");
}

/** Último passo: liga (ou não) o agendamento pelo link e encerra o guia. */
export async function concluirGuia(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador configura o salão." };
  const { error } = await supabase.from("saloes").update({ agendamento_online: f.get("online") === "on", guia_concluido_em: new Date().toISOString() }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar. Tente de novo." };
  revalidatePath("/", "layout");
  redirect("/hoje");
}
