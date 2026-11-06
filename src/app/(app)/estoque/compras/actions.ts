"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { lerReais } from "@/lib/dinheiro";
import type { Estado } from "@/components/acao-form";

const UUID = /^[0-9a-f-]{36}$/;
const atualizar = () => { revalidatePath("/estoque/compras"); revalidatePath("/estoque"); };

export async function salvarFornecedor(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const nome = String(f.get("nome") ?? "").trim().slice(0, 120), tel = String(f.get("telefone") ?? "").replace(/\D/g, "");
  if (nome.length < 2) return { erro: "Informe o nome do fornecedor." };
  if (tel && !/^[0-9]{10,13}$/.test(tel)) return { erro: "Telefone com DDD." };
  const { error } = await supabase.from("fornecedores").insert({ nome, telefone: tel || null, email: String(f.get("email") ?? "").trim().slice(0, 200) || null });
  if (error) return { erro: "Sem permissão para cadastrar fornecedores." };
  atualizar();
  return { ok: "Fornecedor cadastrado." };
}

export async function apagarFornecedor(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("fornecedores").delete().eq("id", String(f.get("id")));
  atualizar();
}

/** De quem compra e quanto quer ter na prateleira. */
export async function salvarProdutoCompra(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const forn = String(f.get("fornecedor_id") ?? ""), ideal = Number(String(f.get("estoque_ideal") ?? "").replace(",", "."));
  const { error } = await supabase.from("produtos").update({
    fornecedor_id: UUID.test(forn) ? forn : null,
    estoque_ideal: Number.isFinite(ideal) && ideal > 0 ? ideal : null,
  }).eq("id", String(f.get("produto_id")));
  if (error) return { erro: "Não foi possível salvar." };
  atualizar();
  return { ok: "Salvo." };
}

/** Cria o pedido com as quantidades da tela (já vem a sugestão). */
export async function criarPedido(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const forn = String(f.get("fornecedor_id") ?? "");
  const itens = f.getAll("produto_id").map(String).map((id, i) => ({
    produto_id: id, embalagens: Number(String(f.getAll("embalagens")[i] ?? "").replace(",", ".")), custo: lerReais(String(f.getAll("custo")[i] ?? "")),
  })).filter((x) => UUID.test(x.produto_id) && Number.isFinite(x.embalagens) && x.embalagens > 0);
  if (itens.length === 0) return { erro: "Informe a quantidade de pelo menos um produto." };
  const { data: ped, error } = await supabase.from("pedidos_compra").insert({ fornecedor_id: UUID.test(forn) ? forn : null }).select("id").single();
  if (error || !ped) return { erro: "Sem permissão para criar pedidos." };
  const { error: e2 } = await supabase.from("pedido_compra_itens").insert(itens.map((x) => ({ pedido_id: ped.id, produto_id: x.produto_id, embalagens: x.embalagens, custo_centavos: x.custo })));
  if (e2) { await supabase.from("pedidos_compra").delete().eq("id", ped.id); return { erro: "Não foi possível salvar os itens." }; }
  atualizar();
  return { ok: "Pedido criado. Mande para o fornecedor pelo botão do WhatsApp." };
}

export async function receberPedido(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.rpc("receber_pedido", { p_pedido: String(f.get("id")) });
  atualizar();
}

export async function cancelarPedido(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("pedidos_compra").update({ status: "cancelado" }).eq("id", String(f.get("id"))).eq("status", "aberto");
  atualizar();
}
