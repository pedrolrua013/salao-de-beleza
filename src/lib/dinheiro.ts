// Dinheiro em centavos (inteiro), como no banco.

const BRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

/** 123456 → "R$ 1.234,56" */
export function reais(centavos: number): string {
  return BRL.format(centavos / 100).replace(/ /g, " ");
}

/** "1.234,56", "1234.56", "R$ 45" ou "45,5" → centavos. Vazio ou inválido → null. */
export function lerReais(texto: string): number | null {
  let t = texto.replace(/[R$\s]/g, "");
  if (!t) return null;
  if (t.includes(",")) t = t.replace(/\./g, "").replace(",", ".");
  else if (/^\d{1,3}(\.\d{3})+$/.test(t)) t = t.replace(/\./g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return null;
  const v = Math.round(Number(t) * 100);
  return Number.isSafeInteger(v) && v <= 10_000_000 ? v : null;
}

/** Centavos para o valor de um campo de formulário: 4550 → "45,50". */
export function campoReais(centavos: number): string {
  return (centavos / 100).toFixed(2).replace(".", ",");
}

export const FORMAS = { dinheiro: "Dinheiro", pix: "Pix", debito: "Débito", credito: "Crédito", pacote: "Pacote", sinal: "Sinal (Pix online)", cashback: "Cashback", vale_presente: "Vale-presente", outro: "Outro" } as const;
export type Forma = keyof typeof FORMAS;
/** Formas que a recepção escolhe. Pacote, cashback e sinal só entram pelos botões que descontam o saldo da cliente. */
export const FORMAS_DIGITADAS = ["pix", "dinheiro", "debito", "credito", "outro"] as const;
