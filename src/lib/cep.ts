export const UFS = ["AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO"];

export type Endereco = { cep: string; logradouro: string; bairro: string; cidade: string; uf: string };

/** 11430090 → 11430-090 (enquanto digita, só o que já tem). */
export function formatarCep(s: string): string {
  const d = s.replace(/\D/g, "").slice(0, 8);
  return d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d;
}

/** Resposta do ViaCEP ou da BrasilAPI no mesmo formato; null se o CEP não existe. */
export function lerRespostaCep(j: unknown): Omit<Endereco, "cep"> | null {
  if (!j || typeof j !== "object") return null;
  const o = j as Record<string, unknown>;
  if (o.erro) return null;
  const txt = (v: unknown) => (typeof v === "string" ? v.trim() : "");
  const uf = txt(o.uf ?? o.state).toUpperCase();
  const cidade = txt(o.localidade ?? o.city);
  if (!UFS.includes(uf) || !cidade) return null;
  return { logradouro: txt(o.logradouro ?? o.street), bairro: txt(o.bairro ?? o.neighborhood), cidade, uf };
}

/** Busca no ViaCEP e, se ele falhar, na BrasilAPI. */
export async function buscarCep(cep: string, buscar: typeof fetch = fetch): Promise<Omit<Endereco, "cep"> | null | "falhou"> {
  const d = cep.replace(/\D/g, "");
  if (d.length !== 8) return null;
  for (const url of [`https://viacep.com.br/ws/${d}/json/`, `https://brasilapi.com.br/api/cep/v1/${d}`]) {
    try {
      const r = await buscar(url, { signal: AbortSignal.timeout(5000) });
      if (r.status === 404 || r.status === 400) return null;
      if (!r.ok) continue;
      return lerRespostaCep(await r.json());
    } catch { /* tenta o próximo */ }
  }
  return "falhou";
}

/** Endereço numa linha: "Rua X, 120 - Sala 2 - Bairro, Cidade - SP". */
export function enderecoEmLinha(e: { logradouro?: string | null; numero?: string | null; complemento?: string | null; bairro?: string | null; cidade?: string | null; uf?: string | null }): string {
  const rua = [e.logradouro, e.numero].filter(Boolean).join(", ");
  const local = [e.cidade, e.uf].filter(Boolean).join(" - ");
  return [rua, e.complemento, [e.bairro, local].filter(Boolean).join(", ")].filter(Boolean).join(" - ");
}
