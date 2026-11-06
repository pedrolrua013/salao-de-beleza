"use server";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { dentroDoLimite, ipDoCliente } from "@/lib/limite";
import { gerarPixCobranca } from "@/lib/cobranca";
import { lerReais } from "@/lib/dinheiro";
import type { Estado } from "@/components/acao-form";

const ERROS: Record<string, string> = {
  venda_indisponivel: "Este salão não está vendendo pelo link agora.",
  nome_telefone: "Informe seu nome e um celular com DDD.",
  pacote_indisponivel: "Esse pacote não está mais à venda.",
  valor_invalido: "O vale vai de R$ 20 a R$ 2.000.",
  presente_sem_nome: "Diga para quem é o presente.",
};

/** Vale ou pacote pelo link: o banco cria a cobrança (e acha a cliente pelo celular); aqui sai o Pix. */
export async function comprarOnline(_: Estado, f: FormData): Promise<Estado> {
  const db = clienteAdmin();
  if (!db) return { erro: "Indisponível no momento." };
  const slug = String(f.get("slug") ?? "");
  if (!(await dentroDoLimite(`compra:ip:${ipDoCliente(await headers()) ?? "sem-ip"}`, 5, 60))) return { erro: "Muitos pedidos seguidos. Tente mais tarde ou fale com o salão." };
  const tipo = f.get("tipo") === "pacote" ? "pacote" : "vale";
  const pacote = String(f.get("pacote") ?? "");
  const { data, error } = await db.rpc("criar_pedido_online", {
    p_slug: slug, p_tipo: tipo, p_pacote: /^[0-9a-f-]{36}$/.test(pacote) ? pacote : null,
    p_valor: tipo === "vale" ? lerReais(String(f.get("valor") ?? "")) : null,
    p_nome: String(f.get("nome") ?? ""), p_telefone: String(f.get("telefone") ?? ""),
    p_para: String(f.get("para") ?? ""), p_mensagem: String(f.get("mensagem") ?? ""),
  });
  if (error || !data) return { erro: Object.entries(ERROS).find(([k]) => error?.message?.includes(k))?.[1] ?? "Não foi possível criar o pedido." };
  const c = data as { id: string; token: string; valor_centavos: number };
  const { data: s } = await db.from("saloes").select("id, nome, pix_chave, pix_nome, pix_cidade").eq("slug", slug).single();
  if (!s || !(await gerarPixCobranca(db, s, c, tipo === "vale" ? `Vale-presente ${s.nome}` : `Pacote ${s.nome}`))) {
    await db.from("cobrancas").update({ status: "cancelada" }).eq("id", c.id);
    return { erro: "O salão ainda não configurou o Pix. Fale com ele pelo WhatsApp." };
  }
  redirect(`/s/${slug}/pagar/${c.token}`);
}
