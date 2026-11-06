"use server";
import { revalidatePath } from "next/cache";
import { lerPermissoes } from "@/lib/permissoes";
import type { Papel } from "@/lib/types";
import { exigirMembro } from "@/lib/auth";
import { clienteAdmin } from "@/lib/supabase/admin";
import type { Estado } from "@/components/acao-form";

const PAPEIS = ["admin", "profissional", "recepcao"] as const;

export async function convidar(_: Estado, f: FormData): Promise<Estado> {
  const { membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador convida pessoas." };
  const email = String(f.get("email") ?? "").trim().toLowerCase();
  const nome = String(f.get("nome") ?? "").trim();
  const papel = String(f.get("papel") ?? "");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || nome.length < 2) return { erro: "Informe nome e um e-mail válido." };
  if (!(PAPEIS as readonly string[]).includes(papel)) return { erro: "Escolha o papel." };
  const admin = clienteAdmin();
  if (!admin) return { erro: "Convites precisam da chave de serviço do Supabase (SUPABASE_SERVICE_ROLE_KEY) no servidor." };
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email);
  if (error || !data.user) return { erro: "Não foi possível enviar o convite. Esse e-mail já pode ter uma conta." };
  const { error: e2 } = await admin.from("membros").insert({ user_id: data.user.id, salao_id: salao.id, papel, nome });
  if (e2) {
    // Só apaga a conta se ela acabou de ser criada por este convite e não pertence a nenhum salão.
    const recente = Date.now() - Date.parse(data.user.created_at) < 120_000;
    const { count } = await admin.from("membros").select("user_id", { count: "exact", head: true }).eq("user_id", data.user.id);
    if (recente && !count) await admin.auth.admin.deleteUser(data.user.id);
    return { erro: e2.code === "23505" ? "Essa pessoa já pertence a um salão." : "Não foi possível cadastrar a pessoa." };
  }
  revalidatePath("/equipe");
  return { ok: `Convite enviado para ${email}.` };
}

export async function alternarAtivo(f: FormData) {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return;
  const id = String(f.get("id") ?? "");
  if (id === membro.user_id) return; // ninguém desativa a si mesmo
  await supabase.from("membros").update({ ativo: String(f.get("ativo")) !== "true" }).eq("user_id", id);
  revalidatePath("/equipe");
}

const HORA = /^\d{2}:\d{2}$/;

/** Dias e horários de um profissional. Campo vazio = segue o horário do salão. */
/** Permissões sob medida: grava só o que difere do padrão do papel. */
export async function salvarPermissoes(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador muda as permissões." };
  const id = String(f.get("id") ?? "");
  const { data: m } = await supabase.from("membros").select("papel").eq("user_id", id).maybeSingle();
  if (!m || m.papel === "admin") return { erro: "O administrador já pode tudo." };
  const { error } = await supabase.from("membros").update({ permissoes: lerPermissoes(m.papel as Papel, f.getAll("perm").map(String)) }).eq("user_id", id);
  if (error) return { erro: "Não foi possível salvar as permissões." };
  revalidatePath("/equipe");
  return { ok: "Permissões salvas. Valem no próximo clique da pessoa." };
}

export async function salvarJornada(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador muda a jornada." };
  const id = String(f.get("id") ?? "");
  const h = (k: string) => { const v = String(f.get(k) ?? ""); return HORA.test(v) ? v : null; };
  const dias = f.getAll("dias").map(Number).filter((n) => n >= 1 && n <= 7);
  const entrada = h("entrada"), saida = h("saida"), almocoIni = h("almoco_inicio"), almocoFim = h("almoco_fim");
  if (dias.length === 0) return { erro: "Marque pelo menos um dia de trabalho." };
  if (entrada && saida && saida <= entrada) return { erro: "A saída precisa ser depois da entrada." };
  if (!almocoIni !== !almocoFim) return { erro: "Informe início e fim do almoço, ou deixe os dois vazios." };
  if (almocoIni && almocoFim && almocoFim <= almocoIni) return { erro: "O fim do almoço precisa ser depois do início." };
  const tel = String(f.get("telefone") ?? "").replace(/\D/g, "");
  if (tel && !/^[0-9]{10,11}$/.test(tel)) return { erro: "Celular com DDD: 10 ou 11 números." };
  const avisos = f.get("avisos_whatsapp") === "on";
  if (avisos && !tel) return { erro: "Para avisar pelo WhatsApp, informe o celular." };
  const { error } = await supabase.from("membros").update({
    dias_semana: dias,
    entrada, saida, almoco_inicio: almocoIni, almoco_fim: almocoFim,
    telefone: tel || null, avisos_whatsapp: avisos,
  }).eq("user_id", id);
  if (error) return { erro: "Não foi possível salvar a jornada." };
  revalidatePath("/equipe"); revalidatePath("/agenda");
  return { ok: "Jornada salva." };
}

/** Meta do mês (do salão ou de um profissional). Faturamento e produtos em reais; atendimentos em quantidade. */
export async function salvarMeta(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador define metas." };
  const tipo = String(f.get("tipo") ?? "");
  if (!["faturamento", "produtos", "atendimentos"].includes(tipo)) return { erro: "Escolha o tipo da meta." };
  const bruto = String(f.get("valor") ?? "").replace(/\./g, "").replace(",", ".");
  const n = Number(bruto);
  const valor = tipo === "atendimentos" ? Math.round(n) : Math.round(n * 100);
  if (!Number.isFinite(n) || valor <= 0) return { erro: "Informe o valor da meta." };
  const mes = String(f.get("mes") ?? "");
  if (!/^\d{4}-\d{2}$/.test(mes)) return { erro: "Escolha o mês." };
  const prof = String(f.get("membro_id") ?? "");
  const { error } = await supabase.from("metas").insert({ membro_id: /^[0-9a-f-]{36}$/.test(prof) ? prof : null, mes: `${mes}-01`, tipo, valor });
  if (error) return { erro: error.code === "23505" ? "Já existe essa meta nesse mês. Apague a antiga para trocar." : "Não foi possível salvar a meta." };
  revalidatePath("/equipe"); revalidatePath("/hoje"); revalidatePath("/painel");
  return { ok: "Meta salva." };
}

export async function apagarMeta(f: FormData) {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return;
  await supabase.from("metas").delete().eq("id", String(f.get("id")));
  revalidatePath("/equipe"); revalidatePath("/hoje"); revalidatePath("/painel");
}
