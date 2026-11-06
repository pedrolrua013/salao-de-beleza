"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import type { Estado } from "@/components/acao-form";

export async function salvarFiscal(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera os dados fiscais." };
  const digitos = (k: string) => String(f.get(k) ?? "").replace(/\D/g, "");
  const texto = (k: string, max: number) => String(f.get(k) ?? "").trim().slice(0, max) || null;
  const cnpj = digitos("cnpj"), municipio = digitos("codigo_municipio");
  const item = String(f.get("item_lista_servico") ?? "").trim();
  const aliquota = Number(String(f.get("aliquota") ?? "").replace(",", "."));
  if (cnpj && cnpj.length !== 14) return { erro: "O CNPJ tem 14 números." };
  if (municipio && municipio.length !== 7) return { erro: "O código IBGE da cidade tem 7 números." };
  if (item && !/^\d{2}\.?\d{2}$/.test(item)) return { erro: "Item da lista no formato 06.01." };
  if (String(f.get("aliquota") ?? "").trim() && (!Number.isFinite(aliquota) || aliquota < 0 || aliquota > 5)) return { erro: "A alíquota do ISS vai de 0% a 5%." };
  const token = String(f.get("token_emissor") ?? "").trim();
  if (token && (token.length < 10 || token.length > 200)) return { erro: "Token do emissor inválido." };
  const dados: Record<string, unknown> = {
    cnpj: cnpj || null, razao_social: texto("razao_social", 150), inscricao_municipal: texto("inscricao_municipal", 20),
    codigo_municipio: municipio || null, item_lista_servico: item || null, codigo_tributario_municipio: texto("codigo_tributario_municipio", 20),
    aliquota: String(f.get("aliquota") ?? "").trim() ? Math.round(aliquota * 100) / 100 : null,
    simples_nacional: f.get("simples_nacional") === "on", ambiente: f.get("ambiente") === "producao" ? "producao" : "homologacao",
    ativo: f.get("ativo") === "on",
    ...(token ? { token_emissor: token } : {}),
  };
  const { data: existe } = await supabase.from("fiscal_salao").select("salao_id").maybeSingle();
  const { error } = existe
    ? await supabase.from("fiscal_salao").update({ ...dados, atualizado_em: new Date().toISOString() }).eq("salao_id", existe.salao_id)
    : await supabase.from("fiscal_salao").insert(dados);
  if (error) return { erro: "Não foi possível salvar. Confira os campos." };
  revalidatePath("/configuracoes/nota-fiscal");
  return { ok: "Dados fiscais salvos." };
}
