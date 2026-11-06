// Regras do campo de data: máscara DD/MM/AAAA, conversão para o formato do banco e a grade de dias do mês.

export const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
export const MESES_CURTOS = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

const dois = (n: number) => String(n).padStart(2, "0");
export const iso = (a: number, m: number, d: number) => `${a}-${dois(m)}-${dois(d)}`;

/** Digitando: "31121990" → "31/12/1990". */
export function mascararData(texto: string): string {
  const d = texto.replace(/\D/g, "").slice(0, 8);
  if (d.length <= 2) return d;
  if (d.length <= 4) return `${d.slice(0, 2)}/${d.slice(2)}`;
  return `${d.slice(0, 2)}/${d.slice(2, 4)}/${d.slice(4)}`;
}

/** "31/12/1990" → "1990-12-31"; data incompleta ou que não existe → null. */
export function lerDataBr(texto: string): string | null {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texto);
  if (!m) return null;
  const d = +m[1], mes = +m[2], a = +m[3];
  const dt = new Date(Date.UTC(a, mes - 1, d));
  if (a < 1900 || a > 2100 || dt.getUTCMonth() !== mes - 1 || dt.getUTCDate() !== d) return null;
  return iso(a, mes, d);
}

/** "1990-12-31" → "31/12/1990". */
export function dataBr(valor: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(valor ?? "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
}

/** As semanas do mês (domingo primeiro), com os dias de fora como null. */
export function semanasDoMes(ano: number, mes: number): (number | null)[][] {
  const primeiro = new Date(Date.UTC(ano, mes - 1, 1)).getUTCDay();
  const total = new Date(Date.UTC(ano, mes, 0)).getUTCDate();
  const dias: (number | null)[] = [...Array(primeiro).fill(null), ...Array.from({ length: total }, (_, i) => i + 1)];
  while (dias.length % 7) dias.push(null);
  return Array.from({ length: dias.length / 7 }, (_, s) => dias.slice(s * 7, s * 7 + 7));
}

/** Hoje no fuso de quem está usando, no formato do banco. */
export function hojeIso(): string {
  const h = new Date();
  return iso(h.getFullYear(), h.getMonth() + 1, h.getDate());
}
