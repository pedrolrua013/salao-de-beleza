// O Supabase devolve no máximo 1.000 linhas por consulta. Para listas que podem passar disso, busca de 1.000 em 1.000.
// A consulta precisa ter uma ordem fixa (ex.: .order("id")), senão as páginas se misturam.

type Pagina<T> = PromiseLike<{ data: T[] | null; error: { message: string } | null }>;

export async function todasAsLinhas<T>(pagina: (de: number, ate: number) => Pagina<T>, maximo = 50_000): Promise<T[]> {
  const out: T[] = [];
  for (let de = 0; de < maximo; de += 1000) {
    const { data, error } = await pagina(de, de + 999);
    // Lista pela metade não pode parecer completa (ex.: horário ocupado aparecendo como livre).
    if (error) throw new Error(error.message);
    out.push(...(data ?? []));
    if (!data || data.length < 1000) break;
  }
  return out;
}
