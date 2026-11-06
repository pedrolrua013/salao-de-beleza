// Lê a planilha que o salão tem: Excel (.xlsx), CSV de qualquer sistema ou texto colado do Excel/Google Planilhas.
// O .xlsx é um zip de XMLs; lemos sem biblioteca (descompactação nativa do navegador e do Node).
import { lerCsv } from "./csv.ts";

/** UTF-8; se tiver caractere inválido, é CSV antigo do Excel em Latin-1. */
export function decodificarTexto(bytes: Uint8Array): string {
  try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
  catch { return new TextDecoder("windows-1252").decode(bytes); }
}

const ehZip = (b: Uint8Array) => b.length > 4 && b[0] === 0x50 && b[1] === 0x4b && b[2] === 0x03 && b[3] === 0x04;
const ehXlsAntigo = (b: Uint8Array) => b.length > 8 && b[0] === 0xd0 && b[1] === 0xcf && b[2] === 0x11 && b[3] === 0xe0;

export type Leitura = { linhas: string[][] } | { erro: string };

/** Arquivo inteiro → linhas da primeira aba (ou do CSV). */
export async function lerPlanilha(bytes: Uint8Array): Promise<Leitura> {
  if (ehXlsAntigo(bytes)) return { erro: "Esse é o formato antigo do Excel (.xls). No Excel, use Arquivo > Salvar como > Pasta de Trabalho do Excel (.xlsx) ou CSV." };
  if (ehZip(bytes)) {
    try {
      const linhas = await lerXlsx(bytes);
      return linhas ? { linhas } : { erro: "Não reconhecemos esse arquivo. Envie .xlsx ou .csv." };
    } catch { return { erro: "Não deu para abrir essa planilha. Salve de novo como .xlsx ou .csv e tente outra vez." }; }
  }
  return { linhas: lerCsv(decodificarTexto(bytes)) };
}

/* ───── zip ───── */

async function arquivosDoZip(b: Uint8Array, querer: (nome: string) => boolean): Promise<Map<string, string>> {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  let fim = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) if (v.getUint32(i, true) === 0x06054b50) { fim = i; break; }
  if (fim < 0) throw new Error("zip sem diretório");
  const total = v.getUint16(fim + 10, true);
  let p = v.getUint32(fim + 16, true);
  const out = new Map<string, string>();
  for (let n = 0; n < total; n++) {
    if (v.getUint32(p, true) !== 0x02014b50) throw new Error("zip corrompido");
    const metodo = v.getUint16(p + 10, true), tam = v.getUint32(p + 20, true);
    const lNome = v.getUint16(p + 28, true), lExtra = v.getUint16(p + 30, true), lComent = v.getUint16(p + 32, true);
    const local = v.getUint32(p + 42, true);
    const nome = new TextDecoder().decode(b.subarray(p + 46, p + 46 + lNome));
    p += 46 + lNome + lExtra + lComent;
    if (!querer(nome)) continue;
    const ini = local + 30 + v.getUint16(local + 26, true) + v.getUint16(local + 28, true);
    const dados = b.subarray(ini, ini + tam);
    if (metodo === 0) out.set(nome, new TextDecoder().decode(dados));
    else if (metodo === 8) out.set(nome, await new Response(new Blob([dados.slice()]).stream().pipeThrough(new DecompressionStream("deflate-raw"))).text());
  }
  return out;
}

/* ───── xlsx ───── */

const ENT: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };
const desXml = (s: string) => s.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, e: string) =>
  e[0] === "#" ? String.fromCodePoint(e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)) : ENT[e.toLowerCase()]);
const textos = (xml: string) => [...xml.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)].map((m) => desXml(m[1])).join("");

/** "AB12" → 27 (coluna, começando em 0). */
export function indiceColuna(ref: string): number {
  const letras = /^[A-Z]+/i.exec(ref)?.[0].toUpperCase() ?? "A";
  let n = 0;
  for (const ch of letras) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

/** Número do Excel como texto: 1.1999990000E10 → "11999990000". */
function numeroComoTexto(v: string): string {
  if (/^-?\d+(\.\d+)?E[+-]?\d+$/i.test(v)) { const n = Number(v); if (Number.isFinite(n) && Number.isInteger(n)) return n.toFixed(0); }
  return v;
}

/** XML de uma aba + textos compartilhados → linhas. */
export function linhasDaAba(xml: string, compartilhados: string[]): string[][] {
  const linhas: string[][] = [];
  for (const r of xml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const linha: string[] = [];
    let auto = 0;
    for (const c of r[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attrs = c[1], corpo = c[2] ?? "";
      const ref = /\br="([A-Z]+)\d*"/i.exec(attrs)?.[1];
      const col = ref ? indiceColuna(ref) : auto;
      auto = col + 1;
      const tipo = /\bt="(\w+)"/.exec(attrs)?.[1];
      const v = /<v>([\s\S]*?)<\/v>/.exec(corpo)?.[1];
      let s = "";
      if (tipo === "s") s = compartilhados[Number(v)] ?? "";
      else if (tipo === "inlineStr") s = textos(corpo);
      else if (v !== undefined) s = tipo === "str" || tipo === "e" ? desXml(v) : tipo === "b" ? (v === "1" ? "VERDADEIRO" : "FALSO") : numeroComoTexto(v);
      while (linha.length < col) linha.push("");
      linha[col] = s.trim();
    }
    if (linha.some((x) => x)) linhas.push(linha);
  }
  return linhas;
}

async function lerXlsx(b: Uint8Array): Promise<string[][] | null> {
  const arqs = await arquivosDoZip(b, (n) => n === "xl/workbook.xml" || n === "xl/_rels/workbook.xml.rels" || n === "xl/sharedStrings.xml" || /^xl\/worksheets\/[^/]+\.xml$/.test(n));
  // A primeira aba visível do livro, pelo vínculo do workbook (a "sheet1.xml" nem sempre é a primeira).
  let aba: string | undefined;
  const wb = arqs.get("xl/workbook.xml"), rels = arqs.get("xl/_rels/workbook.xml.rels");
  if (wb && rels) {
    const primeira = [...wb.matchAll(/<sheet\b([^>]*)\/?>/g)].map((m) => m[1]).find((a) => !/state="(hidden|veryHidden)"/.test(a));
    const rid = primeira && /r:id="([^"]+)"/.exec(primeira)?.[1];
    const alvo = rid && new RegExp(`<Relationship\\b[^>]*Id="${rid}"[^>]*Target="([^"]+)"`).exec(rels)?.[1]
      || rid && new RegExp(`<Relationship\\b[^>]*Target="([^"]+)"[^>]*Id="${rid}"`).exec(rels)?.[1];
    if (alvo) aba = arqs.get(alvo.startsWith("/") ? alvo.slice(1) : `xl/${alvo}`);
  }
  aba ??= arqs.get("xl/worksheets/sheet1.xml") ?? [...arqs.entries()].filter(([n]) => n.startsWith("xl/worksheets/")).sort()[0]?.[1];
  if (!aba) return null;
  const ss = arqs.get("xl/sharedStrings.xml");
  const compartilhados = ss ? [...ss.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map((m) => textos(m[1])) : [];
  return linhasDaAba(aba, compartilhados);
}
