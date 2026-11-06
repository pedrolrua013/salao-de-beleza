"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { clienteAdmin } from "@/lib/supabase/admin";
import { gerarPixCobranca } from "@/lib/cobranca";
import type { EstadoLink } from "@/components/gerar-link";

/** Link para a cliente pagar pelo celular o que falta da comanda (Pix). */
export async function cobrarPeloCelular(_: EstadoLink, f: FormData): Promise<EstadoLink> {
  const { supabase, salao } = await exigirMembro();
  const comanda = String(f.get("comanda_id") ?? "");
  const { data, error } = await supabase.rpc("criar_cobranca_comanda", { p_comanda: comanda });
  if (error || !data) {
    if (error?.message.includes("nada_a_cobrar")) return { erro: "Não falta nada a pagar nesta comanda." };
    if (error?.message.includes("comanda_fechada")) return { erro: "A comanda já foi fechada." };
    return { erro: "Só o administrador ou a recepção geram a cobrança." };
  }
  const c = data as { id: string; token: string; valor_centavos: number };
  const db = clienteAdmin();
  const { data: s } = db ? await db.from("saloes").select("id, nome, pix_chave, pix_nome, pix_cidade").eq("id", salao.id).single() : { data: null };
  if (!db || !s || !(await gerarPixCobranca(db, s, c, `Comanda ${salao.nome}`))) {
    await supabase.rpc("cancelar_cobranca", { p_id: c.id });  // sem Pix não há o que esperar
    return { erro: "Cadastre a chave Pix do salão (Salão > Agendamento online) ou ligue o Mercado Pago." };
  }
  revalidatePath(`/caixa/${comanda}`);
  return { link: `${process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") ?? ""}/s/${salao.slug}/pagar/${c.token}`, mensagem: `Segue o link para pagar pelo Pix no ${salao.nome}:` };
}

/** A recepção viu o Pix cair no banco e confirma (no Mercado Pago a confirmação é sozinha). */
export async function confirmarCobranca(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.rpc("confirmar_cobranca", { p_id: String(f.get("id") ?? "") });
  const comanda = String(f.get("comanda_id") ?? "");
  revalidatePath("/caixa");
  if (comanda) revalidatePath(`/caixa/${comanda}`);
}

export async function cancelarCobranca(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.rpc("cancelar_cobranca", { p_id: String(f.get("id") ?? "") });
  revalidatePath("/caixa");
  const comanda = String(f.get("comanda_id") ?? "");
  if (comanda) revalidatePath(`/caixa/${comanda}`);
}

/** Taxa de falta pendente da cliente entra como item da comanda (o banco confere e põe o valor). */
export async function cobrarTaxa(f: FormData) {
  const { supabase } = await exigirMembro();
  const comanda = String(f.get("comanda_id") ?? "");
  await supabase.from("comanda_itens").insert({ comanda_id: comanda, tipo: "taxa", descricao: `Falta em ${String(f.get("quando") ?? "")}`.slice(0, 160), preco_centavos: 1, taxa_falta_id: String(f.get("taxa_id") ?? "") });
  revalidatePath(`/caixa/${comanda}`);
}

/** Sugestão aceita: serviço feito pela mesma pessoa do serviço principal, ou produto vendido por ela. */
export async function adicionarSugestao(f: FormData) {
  const { supabase } = await exigirMembro();
  const comanda = String(f.get("comanda_id") ?? ""), tipo = String(f.get("tipo") ?? ""), id = String(f.get("id") ?? ""), prof = String(f.get("profissional_id") ?? "") || null;
  if (tipo === "servico") {
    const { data: s } = await supabase.from("servicos").select("id, nome, preco_centavos").eq("id", id).maybeSingle();
    if (!s || !prof) return;
    const preco = Number((await supabase.rpc("preco_de", { p_servico: s.id, p_prof: prof, p_variacao: null })).data ?? s.preco_centavos);
    await supabase.from("comanda_itens").insert({ comanda_id: comanda, tipo, servico_id: s.id, descricao: s.nome, profissional_id: prof, preco_centavos: preco });
  } else if (tipo === "produto") {
    const { data: p } = await supabase.from("produtos").select("id, nome, preco_centavos").eq("id", id).maybeSingle();
    if (!p) return;
    await supabase.from("comanda_itens").insert({ comanda_id: comanda, tipo, produto_id: p.id, descricao: p.nome, profissional_id: prof, preco_centavos: p.preco_centavos });
  }
  revalidatePath(`/caixa/${comanda}`);
}
