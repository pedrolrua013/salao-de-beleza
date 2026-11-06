"use server";
import { exigirMembro } from "@/lib/auth";
import { soDigitos } from "@/lib/format";

export type ClienteAchada = { id: string; nome: string; telefone: string | null };

/** Busca pelo nome (qualquer parte) ou pelo telefone (4 números ou mais). */
export async function buscarClientes(termo: string): Promise<ClienteAchada[]> {
  const { supabase } = await exigirMembro();
  const t = termo.trim().slice(0, 60);
  if (t.length < 2) return [];
  const d = soDigitos(t);
  let q = supabase.from("clientes").select("id, nome, telefone").order("nome").limit(8);
  // % e _ digitados são letras, não curingas.
  q = d.length >= 4 && /^[\d\s()+.-]+$/.test(t) ? q.ilike("telefone", `%${d}%`) : q.ilike("nome", `%${t.replace(/[\\%_]/g, (c) => `\\${c}`)}%`);
  const { data } = await q;
  return (data ?? []) as ClienteAchada[];
}
