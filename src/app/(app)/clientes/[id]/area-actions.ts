"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import type { EstadoLink } from "@/components/gerar-link";

const site = () => process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") ?? "";

/** Link da área da cliente (vale 6 meses). */
export async function gerarLinkArea(_: EstadoLink, f: FormData): Promise<EstadoLink> {
  const { supabase, salao } = await exigirMembro();
  const { data, error } = await supabase.rpc("criar_link_cliente", { p_cliente: String(f.get("cliente_id") ?? "") });
  if (error || !data) return { erro: "Não foi possível gerar o link." };
  return { link: `${site()}/s/${salao.slug}/minha/${data}`, mensagem: `Oi! Esta é a sua área no ${salao.nome}: horários, cashback e pacotes.` };
}

/** Link de indicação da cliente (o código nasce na primeira vez). */
export async function gerarLinkIndicacao(_: EstadoLink, f: FormData): Promise<EstadoLink> {
  const { supabase, salao } = await exigirMembro();
  const { data, error } = await supabase.rpc("codigo_indicacao", { p_cliente: String(f.get("cliente_id") ?? "") });
  if (error || !data) return { erro: "Não foi possível gerar o link." };
  return { link: `${site()}/s/${salao.slug}?ind=${data}`, mensagem: `Indique o ${salao.nome} para as amigas! Quem marcar por este link e vier, você ganha crédito:` };
}

export async function perdoarTaxa(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.rpc("perdoar_taxa", { p_id: String(f.get("id") ?? "") });
  revalidatePath(`/clientes/${String(f.get("cliente_id") ?? "")}`);
  const comanda = String(f.get("comanda_id") ?? "");
  if (comanda) revalidatePath(`/caixa/${comanda}`);
}
