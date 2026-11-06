// Fases de um serviço: trabalho (o profissional está com a cliente) e pausa (a química age e o profissional fica livre).
// Mesmas regras do banco (fases_validas): de 1 a 5 fases, começa e termina em trabalho, sem duas pausas seguidas.

export type Fase = { tipo: "trabalho" | "pausa"; min: number };
export type Bloco = { tipo: Fase["tipo"]; inicio: number; fim: number }; // instantes em ms

export function fasesValidas(f: unknown): f is Fase[] {
  if (!Array.isArray(f) || f.length < 1 || f.length > 5) return false;
  let anterior = "";
  for (const e of f) {
    if (!e || (e.tipo !== "trabalho" && e.tipo !== "pausa") || !Number.isInteger(e.min) || e.min < 5 || e.min > 480) return false;
    if (e.tipo === "pausa" && anterior !== "trabalho") return false;
    anterior = e.tipo;
  }
  return f[0].tipo === "trabalho" && f[f.length - 1].tipo === "trabalho";
}

export const totalMin = (f: Fase[]) => f.reduce((s, e) => s + e.min, 0);
export const temPausa = (f: Fase[]) => f.some((e) => e.tipo === "pausa");

/** Fases a partir do formulário do catálogo: trabalho antes, pausa, trabalho depois. Pausa 0 = fase única. */
export function fasesDoFormulario(antes: number, pausa: number, depois: number): Fase[] | null {
  if (![antes, pausa, depois].every((n) => Number.isInteger(n) && n >= 0)) return null;
  const f: Fase[] = pausa > 0
    ? [{ tipo: "trabalho", min: antes }, { tipo: "pausa", min: pausa }, { tipo: "trabalho", min: depois }]
    : [{ tipo: "trabalho", min: antes + depois }];
  return fasesValidas(f) && totalMin(f) >= 10 && totalMin(f) <= 480 ? f : null;
}

/** Os três campos do formulário a partir das fases guardadas (serviços com mais fases somam o que vem depois da 1ª pausa). */
export function fasesParaFormulario(f: Fase[]): { antes: number; pausa: number; depois: number } {
  const i = f.findIndex((e) => e.tipo === "pausa");
  if (i < 0) return { antes: totalMin(f), pausa: 0, depois: 0 };
  return { antes: totalMin(f.slice(0, i)), pausa: f[i].min, depois: totalMin(f.slice(i + 1)) };
}

/** "40 min + pausa 40 + 40 min" ou "45 min". */
export function descreverFases(f: Fase[]): string {
  if (!temPausa(f)) return `${totalMin(f)} min`;
  return f.map((e) => (e.tipo === "pausa" ? `pausa ${e.min}` : `${e.min} min`)).join(" + ");
}

/** Blocos de tempo de um atendimento que começa em `inicio`. */
export function blocos(inicio: number, f: Fase[]): Bloco[] {
  let t = inicio;
  return f.map((e) => {
    const b = { tipo: e.tipo, inicio: t, fim: t + e.min * 60_000 };
    t = b.fim;
    return b;
  });
}
