"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { lerReais } from "@/lib/dinheiro";
import type { Estado } from "@/components/acao-form";

const DATA = /^\d{4}-\d{2}-\d{2}$/;
const pct = (v: FormDataEntryValue | null) => {
  const n = Number(String(v ?? "").replace(",", "."));
  return Number.isFinite(n) && n >= 0 && n <= 100 ? Math.round(n * 100) / 100 : null;
};
const atualizar = () => { revalidatePath("/comissoes"); revalidatePath("/extrato"); };

export async function salvarPadrao(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador muda as regras." };
  const srv = pct(f.get("servico")), prod = pct(f.get("produto")), assist = pct(f.get("assistente")) ?? 0;
  if (srv === null || prod === null || srv + assist > 100) return { erro: "Use percentuais entre 0 e 100 (serviço + assistente até 100)." };
  for (const [tipo, percentual, assistente_percentual] of [["servico", srv, assist], ["produto", prod, 0]] as const) {
    const { data } = await supabase.from("regras_comissao").select("id").eq("tipo", tipo).is("profissional_id", null).is("servico_id", null).maybeSingle();
    const r = data
      ? await supabase.from("regras_comissao").update({ percentual, assistente_percentual }).eq("id", data.id)
      : await supabase.from("regras_comissao").insert({ tipo, percentual, assistente_percentual });
    if (r.error) return { erro: "Não foi possível salvar." };
  }
  atualizar();
  return { ok: "Regra padrão salva. Vale para as próximas comandas." };
}

export async function salvarExcecao(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador muda as regras." };
  const tipo = String(f.get("tipo")) === "produto" ? "produto" : "servico";
  const prof = String(f.get("profissional_id") ?? "") || null, servico = tipo === "servico" ? String(f.get("servico_id") ?? "") || null : null;
  const percentual = pct(f.get("percentual")), assistente_percentual = tipo === "servico" ? pct(f.get("assistente")) ?? 0 : 0;
  if (!prof && !servico) return { erro: "Escolha um profissional, um serviço ou os dois. Para todos, use a regra padrão." };
  if (percentual === null || percentual + assistente_percentual > 100) return { erro: "Use percentuais entre 0 e 100." };
  const { error } = await supabase.from("regras_comissao").insert({ tipo, profissional_id: prof, servico_id: servico, percentual, assistente_percentual });
  if (error) return { erro: error.code === "23505" ? "Já existe uma regra para essa combinação. Remova a antiga antes." : "Não foi possível salvar." };
  atualizar();
  return { ok: "Exceção salva." };
}

export async function removerRegra(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("regras_comissao").delete().eq("id", String(f.get("id"))).or("profissional_id.not.is.null,servico_id.not.is.null");
  atualizar();
}

export async function salvarTaxas(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador muda as taxas." };
  const t = (k: string) => pct(f.get(k)) ?? 0;
  const { error } = await supabase.from("saloes").update({
    taxa_debito: t("taxa_debito"), taxa_credito: t("taxa_credito"), taxa_credito_parcelado: t("taxa_credito_parcelado"), taxa_pix: t("taxa_pix"),
    comissao_desconta_taxa: f.get("desconta_taxa") === "on", comissao_desconta_custo: f.get("desconta_custo") === "on",
  }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar (taxas até 20%, crédito parcelado até 30%)." };
  atualizar();
  return { ok: "Taxas salvas." };
}

export async function salvarVinculo(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador muda o vínculo." };
  const vinculo = String(f.get("vinculo"));
  if (!["socio", "clt", "parceiro", "autonomo"].includes(vinculo)) return { erro: "Escolha o vínculo." };
  const d = (k: string) => { const v = String(f.get(k) ?? ""); return DATA.test(v) ? v : null; };
  const doc = String(f.get("documento") ?? "").replace(/\D/g, "").slice(0, 14) || null;
  if (vinculo === "parceiro" && doc && doc.length !== 14) return { erro: "Para salão-parceiro, informe o CNPJ do profissional (14 números)." };
  const { error } = await supabase.from("membros").update({
    vinculo, documento: doc, contrato_inicio: d("contrato_inicio"), contrato_fim: d("contrato_fim"), contrato_homologado_em: d("contrato_homologado_em"),
  }).eq("user_id", String(f.get("id")));
  if (error) return { erro: "Confira as datas: o fim do contrato precisa ser depois do início." };
  atualizar();
  return { ok: "Vínculo salvo." };
}

export async function lancarVale(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const valor = lerReais(String(f.get("valor") ?? ""));
  const prof = String(f.get("profissional_id") ?? "");
  if (!valor || !prof) return { erro: "Escolha o profissional e o valor." };
  const { error } = await supabase.from("vales").insert({ profissional_id: prof, valor_centavos: valor, motivo: String(f.get("motivo") ?? "").trim().slice(0, 200) || null });
  if (error) return { erro: "Só administrador ou recepção lançam vale." };
  atualizar();
  return { ok: "Vale lançado. Ele sai do próximo pagamento." };
}

export async function removerVale(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("vales").delete().eq("id", String(f.get("id")));
  atualizar();
}

export async function pagar(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const de = String(f.get("de")), ate = String(f.get("ate"));
  if (!DATA.test(de) || !DATA.test(ate)) return { erro: "Período inválido." };
  const { error } = await supabase.rpc("pagar_profissional", { p_prof: String(f.get("profissional_id")), p_inicio: de, p_fim: ate, p_forma: String(f.get("forma") ?? "") });
  if (error) return { erro: error.message.includes("nada_a_pagar") ? "Não há nada a pagar nesse período." : "Só o administrador registra pagamento." };
  atualizar();
  return { ok: "Pagamento registrado. As comissões do período ficam marcadas como pagas." };
}
