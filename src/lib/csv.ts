// CSV para importar clientes (planilha ou exportação de outro sistema) e para exportar os dados do salão.

/** Lê CSV com vírgula ou ponto e vírgula, aspas e quebras de linha dentro de campo. */
export function lerCsv(texto: string): string[][] {
  const t = texto.replace(/^﻿/, "");
  const primeira = t.split(/\r?\n/, 1)[0] ?? "";
  const conta = (c: string) => primeira.split(c).length - 1;
  // Texto colado do Excel ou do Google Planilhas vem separado por tabulação.
  const sep = conta("\t") > Math.max(conta(";"), conta(",")) ? "\t" : conta(";") > conta(",") ? ";" : ",";
  const linhas: string[][] = [];
  let campo = "", linha: string[] = [], aspas = false;
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (aspas) {
      if (ch === '"' && t[i + 1] === '"') { campo += '"'; i++; }
      else if (ch === '"') aspas = false;
      else campo += ch;
    } else if (ch === '"') aspas = true;
    else if (ch === sep) { linha.push(campo); campo = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && t[i + 1] === "\n") i++;
      linha.push(campo); campo = "";
      if (linha.some((c) => c.trim())) linhas.push(linha);
      linha = [];
    } else campo += ch;
  }
  linha.push(campo);
  if (linha.some((c) => c.trim())) linhas.push(linha);
  return linhas;
}

/** "31/12/1990", "1990-12-31" ou "31/12/90" → "1990-12-31". */
export function lerData(t: string): string | null {
  let m = /^(\d{4})-(\d{2})-(\d{2})/.exec(t);
  if (m) return valida(+m[1], +m[2], +m[3]);
  m = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$/.exec(t);
  if (!m) return null;
  let ano = +m[3];
  if (ano < 100) ano += ano > (new Date().getFullYear() % 100) ? 1900 : 2000;
  return valida(ano, +m[2], +m[1]);
}
function valida(a: number, m: number, d: number) {
  const dt = new Date(Date.UTC(a, m - 1, d));
  if (dt.getUTCFullYear() !== a || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d || a < 1900 || dt > new Date()) return null;
  return dt.toISOString().slice(0, 10);
}

/** Gera CSV com ponto e vírgula (abre direto no Excel em português) e BOM para os acentos. */
export function escreverCsv(cab: string[], linhas: (string | number | null | undefined)[][]): string {
  const cel = (v: string | number | null | undefined) => {
    let s = v == null ? "" : String(v);
    if (typeof v === "string" && /^[=+\-@\t\r]/.test(s)) s = "'" + s;
    return /[;"\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return "﻿" + [cab, ...linhas].map((l) => l.map(cel).join(";")).join("\r\n");
}
