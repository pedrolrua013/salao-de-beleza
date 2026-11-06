"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { lerReais } from "@/lib/dinheiro";
import type { Estado } from "@/components/acao-form";

const num = (v: FormDataEntryValue | null) => { const n = Number(String(v ?? "").replace(",", ".")); return Number.isFinite(n) ? Math.round(n * 100) / 100 : NaN; };

/** Entrada de mercadoria por embalagem: o sistema converte para a unidade do produto. */
export async function darEntrada(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("produto_id") ?? ""), emb = num(f.get("embalagens"));
  const { data: p } = await supabase.from("produtos").select("conteudo, unidade").eq("id", id).maybeSingle();
  if (!p || !(emb > 0)) return { erro: "Escolha o produto e a quantidade de embalagens." };
  const qtd = p.unidade === "un" ? emb : emb * Number(p.conteudo);
  const { error } = await supabase.from("movimentos_estoque").insert({ produto_id: id, tipo: "entrada", quantidade: qtd, custo_centavos: lerReais(String(f.get("custo") ?? "")), motivo: String(f.get("motivo") ?? "").trim().slice(0, 200) || null });
  if (error) return { erro: "Só administrador ou recepção dão entrada no estoque." };
  revalidatePath("/estoque");
  return { ok: "Entrada registrada." };
}

export async function registrarPerda(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const qtd = num(f.get("quantidade"));
  if (!(qtd > 0)) return { erro: "Informe a quantidade perdida." };
  const { error } = await supabase.from("movimentos_estoque").insert({ produto_id: String(f.get("produto_id") ?? ""), tipo: "perda", quantidade: -qtd, motivo: String(f.get("motivo") ?? "").trim().slice(0, 200) || "perda" });
  if (error) return { erro: "Não foi possível registrar a perda." };
  revalidatePath("/estoque");
  return { ok: "Perda registrada." };
}

export async function contarEstoque(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const contado = num(f.get("contado"));
  if (!(contado >= 0)) return { erro: "Informe quanto tem de verdade." };
  const { data, error } = await supabase.rpc("ajustar_estoque", { p_produto: String(f.get("produto_id") ?? ""), p_contado: contado, p_motivo: "contagem" });
  if (error) return { erro: "Não foi possível ajustar." };
  revalidatePath("/estoque");
  return { ok: Number(data) === 0 ? "Conferido: o estoque estava certo." : `Ajustado (${Number(data) > 0 ? "+" : ""}${data}).` };
}

export async function salvarInsumo(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const qtd = num(f.get("quantidade"));
  if (!(qtd > 0)) return { erro: "Informe quanto o serviço usa." };
  const { error } = await supabase.from("servico_insumos").upsert({ servico_id: String(f.get("servico_id") ?? ""), produto_id: String(f.get("produto_id") ?? ""), quantidade: qtd }, { onConflict: "servico_id,produto_id" });
  if (error) return { erro: "Só o administrador define o consumo dos serviços." };
  revalidatePath("/estoque");
  return { ok: "Consumo salvo. A partir de agora sai sozinho do estoque quando a comanda fecha." };
}

export async function removerInsumo(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("servico_insumos").delete().eq("id", String(f.get("id") ?? ""));
  revalidatePath("/estoque");
}
