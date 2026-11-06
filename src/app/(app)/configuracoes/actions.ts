"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import type { Estado } from "@/components/acao-form";
import { normalizarChavePix, tipoChavePix } from "@/lib/pix";
import { lerReais } from "@/lib/dinheiro";

export async function salvarSalao(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera os dados do salão." };
  const nome = String(f.get("nome") ?? "").trim();
  const abre = String(f.get("abre") ?? ""), fecha = String(f.get("fecha") ?? "");
  const dias = f.getAll("dias").map(Number).filter((n) => n >= 1 && n <= 7);
  if (nome.length < 2) return { erro: "Informe o nome do salão." };
  if (!/^\d{2}:\d{2}$/.test(abre) || !/^\d{2}:\d{2}$/.test(fecha) || fecha <= abre) return { erro: "O horário de fechamento precisa ser depois da abertura." };
  const lembreteHora = String(f.get("lembrete_hora") ?? "10:00");
  if (!/^\d{2}:\d{2}$/.test(lembreteHora) || lembreteHora < "07:00" || lembreteHora > "20:00") return { erro: "O lembrete da véspera deve sair entre 07:00 e 20:00." };
  if (dias.length === 0) return { erro: "Marque pelo menos um dia de atendimento." };
  const { error } = await supabase.from("saloes").update({
    nome, abre, fecha, dias_semana: dias, lembretes_ativos: f.get("lembretes_ativos") === "on", lembrete_hora: lembreteHora,
    telefone: String(f.get("telefone") ?? "").replace(/\D/g, "") || null,
    endereco: String(f.get("endereco") ?? "").trim() || null,
    mensagem: String(f.get("mensagem") ?? "").trim().slice(0, 280) || null,
  }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar." };
  revalidatePath("/configuracoes");
  return { ok: "Dados salvos." };
}

/** Número inteiro dentro do intervalo; fora dele, o padrão. */
const entre = (v: FormDataEntryValue | null, min: number, max: number, padrao: number) => {
  const n = Number(v);
  return Number.isInteger(n) && n >= min && n <= max ? n : padrao;
};

export async function salvarOnline(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera o agendamento online." };
  const horas = Number(f.get("cancelamento_horas") || 24);
  const digitada = String(f.get("pix_chave") ?? "").trim();
  const chave = digitada ? normalizarChavePix(digitada) : null;
  if (digitada && !chave) return { erro: "Chave Pix inválida. Use o CNPJ, CPF, e-mail, celular com DDD ou a chave aleatória." };
  const { error } = await supabase.from("saloes").update({
    agendamento_online: f.get("agendamento_online") === "on",
    politica_cancelamento: String(f.get("politica") ?? "").trim().slice(0, 1000) || null,
    cancelamento_horas: Number.isInteger(horas) && horas >= 0 && horas <= 168 ? horas : 24,
    antecedencia_min_horas: entre(f.get("antecedencia_min"), 0, 72, 1),
    antecedencia_max_dias: entre(f.get("antecedencia_max"), 7, 365, 60),
    sinal_padrao_percentual: entre(f.get("sinal_padrao"), 1, 100, 30),
    pix_chave: chave,
    pix_nome: String(f.get("pix_nome") ?? "").trim().slice(0, 25) || null,
    pix_cidade: String(f.get("pix_cidade") ?? "").trim().slice(0, 15) || null,
  }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar." };
  const token = String(f.get("mp_token") ?? "").trim();
  if (token || f.get("mp_remover") === "on") {
    const { error: e2 } = await supabase.rpc("salvar_token_mp", { p_token: f.get("mp_remover") === "on" ? "" : token });
    if (e2) return { erro: "Dados salvos, mas o token do Mercado Pago foi recusado (confira se copiou o Access Token inteiro)." };
  }
  revalidatePath("/configuracoes");
  return { ok: chave ? `Agendamento online salvo. Chave Pix entendida como ${tipoChavePix(chave)}: ${chave}. Se não for isso, digite de novo (celular com DDD entre parênteses).` : "Agendamento online salvo." };
}

export async function salvarRetorno(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera estas opções." };
  const hora = String(f.get("retorno_hora") ?? "10:00");
  if (!/^\d{2}:\d{2}$/.test(hora) || hora < "08:00" || hora > "20:00") return { erro: "O convite deve sair entre 08:00 e 20:00." };
  const pct = Number(String(f.get("cashback") || "0").replace(",", "."));
  const validade = Number(f.get("cashback_validade") || 90);
  if (!(pct >= 0 && pct <= 30) || !Number.isInteger(validade) || validade < 7 || validade > 365) return { erro: "Cashback entre 0% e 30%, validade entre 7 e 365 dias." };
  const presente = lerReais(String(f.get("aniversario_credito") ?? "")) ?? 0;
  const prazo = Number(f.get("aniversario_validade") || 30);
  if (presente > 100000 || !Number.isInteger(prazo) || prazo < 7 || prazo > 90) return { erro: "Presente de aniversário até R$ 1.000, prazo entre 7 e 90 dias." };
  const google = String(f.get("google") ?? "").trim();
  if (google && !/^https:\/\//.test(google)) return { erro: "O link do Google precisa começar com https://" };
  const { error } = await supabase.from("saloes").update({ retorno_ativo: f.get("retorno_ativo") === "on", retorno_hora: hora, espera_ativa: f.get("espera_ativa") === "on", cashback_percentual: pct, cashback_validade_dias: validade,
    avaliacao_ativa: f.get("avaliacao_ativa") === "on", google_avaliacao_url: google || null,
    aniversario_ativo: f.get("aniversario_ativo") === "on", aniversario_credito_centavos: presente, aniversario_validade_dias: prazo }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar." };
  revalidatePath("/configuracoes");
  return { ok: "Salvo." };
}

const AREAS = ["cabelo", "unhas", "cilios_sobrancelha", "pele", "depilacao"];

/** Fidelidade, indicação, taxa por falta, vendas pelo link, ficha de primeira visita e IA no WhatsApp. */
export async function salvarCrescer(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera estas opções." };
  const reaisInt = (k: string, max: number) => { const n = Math.round(Number(String(f.get(k) ?? "0").replace(",", ".")) * 100); return Number.isFinite(n) && n >= 0 && n <= max ? n : null; };
  const credito = reaisInt("indicacao_credito", 100000), taxa = reaisInt("taxa_falta", 50000);
  if (credito === null) return { erro: "O crédito por indicação vai de R$ 0 a R$ 1.000." };
  if (taxa === null) return { erro: "A taxa por falta vai de R$ 0 a R$ 500." };
  const niveis = [0, 1, 2].map((i) => ({ nome: String(f.get(`nivel_nome_${i}`) ?? "").trim().slice(0, 20), pontos: Number(f.get(`nivel_pontos_${i}`)), bonus: Number(String(f.get(`nivel_bonus_${i}`) ?? "0").replace(",", ".")) }))
    .filter((n) => n.nome && Number.isFinite(n.pontos) && n.pontos >= 1);
  if (niveis.some((n) => !Number.isFinite(n.bonus) || n.bonus < 0 || n.bonus > 20)) return { erro: "O bônus de cada nível vai de 0% a 20%." };
  const areas = f.getAll("areas").map(String).filter((a) => AREAS.includes(a));
  const { error } = await supabase.from("saloes").update({
    fidelidade_ativa: f.get("fidelidade_ativa") === "on",
    fidelidade_niveis: niveis.sort((a, b) => a.pontos - b.pontos).map((n) => ({ nome: n.nome, pontos: Math.round(n.pontos), bonus: Math.round(n.bonus * 10) / 10 })),
    indicacao_credito_centavos: credito, taxa_falta_centavos: taxa,
    venda_online: f.get("venda_online") === "on",
    ficha_areas: areas.length ? areas : ["cabelo"],
    ia_ativa: f.get("ia_ativa") === "on",
    ia_instrucoes: String(f.get("ia_instrucoes") ?? "").trim().slice(0, 1500) || null,
  }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar. Confira os campos." };
  revalidatePath("/configuracoes");
  return { ok: "Opções salvas." };
}
