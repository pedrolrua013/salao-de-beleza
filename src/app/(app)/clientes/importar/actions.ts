"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { chaveCliente, validarImportado, type ClienteImportado } from "@/lib/importar-clientes";
import { todasAsLinhas } from "@/lib/paginar";

export type ResultadoLote = { criadas: number; repetidas: number } | { erro: string };

/**
 * Um pedaço da planilha (até 1.000 clientes), já lido no navegador. Aqui tudo é conferido de novo e
 * quem já está no cadastro (mesmo celular, ou mesmo nome quando não há celular) não é duplicado.
 */
export async function importarLote(linhas: unknown[]): Promise<ResultadoLote> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador importa clientes." };
  if (!Array.isArray(linhas) || linhas.length > 1000) return { erro: "Envie até 1.000 clientes por vez." };
  let existentes: { nome: string; telefone: string | null }[];
  try {
    existentes = await todasAsLinhas((de, ate) => supabase.from("clientes").select("id, nome, telefone").order("id").range(de, ate));
  } catch { return { erro: "Não foi possível conferir o cadastro atual. Tente de novo." }; }
  const ja = new Set<string>();
  for (const c of existentes) { ja.add(chaveCliente(c)); ja.add(chaveCliente({ nome: c.nome, telefone: null })); }
  const novos: ClienteImportado[] = [];
  let repetidas = 0;
  for (const x of linhas) {
    const c = validarImportado(x);
    if (!c) continue;
    const k = chaveCliente(c);
    if (ja.has(k)) { repetidas++; continue; }
    ja.add(k);
    novos.push(c);
  }
  if (novos.length) {
    const { error } = await supabase.from("clientes").insert(novos);
    if (error) return { erro: "Não foi possível salvar este pedaço da planilha. Nada dele entrou; tente de novo." };
  }
  revalidatePath("/clientes");
  return { criadas: novos.length, repetidas };
}
