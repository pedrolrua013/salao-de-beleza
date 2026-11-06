"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { MODELOS_PADRAO } from "@/lib/termos";

export type EstadoTermo = { erro?: string; link?: string };

/** O texto vem do modelo do salão (ou do modelo pronto), nunca do navegador. */
export async function gerarLinkTermo(_: EstadoTermo, f: FormData): Promise<EstadoTermo> {
  const { supabase, salao } = await exigirMembro();
  const cliente = String(f.get("cliente_id") ?? ""), modelo = String(f.get("modelo") ?? "");
  const m = modelo.startsWith("padrao:") ? MODELOS_PADRAO.find((x) => x.id === modelo)
    : /^[0-9a-f-]{36}$/.test(modelo) ? (await supabase.from("termos_modelos").select("id, tipo, titulo, texto").eq("id", modelo).maybeSingle()).data : null;
  if (!m) return { erro: "Escolha o termo." };
  const { data, error } = await supabase.rpc("criar_termo", { p_cliente: cliente, p_tipo: m.tipo, p_titulo: m.titulo, p_texto: m.texto });
  if (error || !data) return { erro: "Não foi possível gerar o link." };
  revalidatePath(`/clientes/${cliente}`);
  return { link: `${process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") ?? ""}/s/${salao.slug}/termo/${data}` };
}
