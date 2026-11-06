// Pix "copia e cola" estático (BR Code, padrão EMV do Banco Central) com valor e identificador.
// Não precisa de banco nem de intermediário: a cliente paga para a chave do salão e a recepção confirma que caiu.

const campo = (id: string, valor: string) => `${id}${String(valor.length).padStart(2, "0")}${valor}`;

/** CRC16-CCITT (polinômio 0x1021, início 0xFFFF), como exige o BR Code. */
export function crc16(texto: string): string {
  let crc = 0xffff;
  for (const byte of new TextEncoder().encode(texto)) {
    crc ^= byte << 8;
    for (let i = 0; i < 8; i++) crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
  }
  return crc.toString(16).toUpperCase().padStart(4, "0");
}

/** Tira acento e o que o BR Code não aceita no nome e na cidade. */
function limpar(t: string, max: number) {
  return t.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^A-Za-z0-9 .\-]/g, "").trim().slice(0, max) || "SALAO";
}

const cpfValido = (d: string) => {
  if (!/^\d{11}$/.test(d) || /^(\d)\1{10}$/.test(d)) return false;
  const dv = (n: number) => { let s = 0; for (let i = 0; i < n; i++) s += Number(d[i]) * (n + 1 - i); const r = (s * 10) % 11; return r === 10 ? 0 : r; };
  return dv(9) === Number(d[9]) && dv(10) === Number(d[10]);
};

/**
 * Chave Pix no formato que o BR Code exige: CPF/CNPJ só números, celular +55DDDNÚMERO, e-mail e chave aleatória em minúsculas.
 * "(11) 99999-0000" → "+5511999990000"; "123.456.789-09" → "12345678909". Inválida → null.
 */
export function tipoChavePix(chaveNormalizada: string): "e-mail" | "chave aleatória" | "celular" | "CNPJ" | "CPF" {
  if (chaveNormalizada.includes("@")) return "e-mail";
  if (chaveNormalizada.includes("-")) return "chave aleatória";
  if (chaveNormalizada.startsWith("+")) return "celular";
  return chaveNormalizada.length === 14 ? "CNPJ" : "CPF";
}

export function normalizarChavePix(chave: string): string | null {
  const t = chave.trim();
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(t)) return t.toLowerCase().slice(0, 77);
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(t)) return t.toLowerCase();
  if (!/^[+\d\s().\/-]+$/.test(t)) return null;
  const d = t.replace(/\D/g, "");
  // Digitado como telefone ("(11) 98765-0034", "+55 11...", "11 98765-0034"): é celular, mesmo que os números passem como CPF.
  const comoTelefone = /[+()\s]/.test(t) && !t.includes(".");
  if (d.length === 14 && !comoTelefone) return d;                            // CNPJ
  if (d.length === 11 && !comoTelefone && cpfValido(d)) return d;            // CPF
  const tel = d.startsWith("55") && (d.length === 12 || d.length === 13) ? d.slice(2) : d;
  if (/^[1-9]{2}9?\d{8}$/.test(tel)) return `+55${tel}`;                   // celular ou fixo com DDD
  return null;
}

export type DadosPix = { chave: string; nome: string; cidade: string; valorCentavos: number; txid?: string; descricao?: string };

export function pixCopiaECola(d: DadosPix): string {
  const conta = campo("00", "br.gov.bcb.pix") + campo("01", normalizarChavePix(d.chave) ?? d.chave.trim()) + (d.descricao ? campo("02", limpar(d.descricao, 40)) : "");
  const txid = (d.txid ?? "***").replace(/[^A-Za-z0-9]/g, "").slice(0, 25) || "***";
  const corpo =
    campo("00", "01") +
    campo("26", conta) +
    campo("52", "0000") +
    campo("53", "986") +
    campo("54", (d.valorCentavos / 100).toFixed(2)) +
    campo("58", "BR") +
    campo("59", limpar(d.nome, 25)) +
    campo("60", limpar(d.cidade, 15)) +
    campo("62", campo("05", txid)) +
    "6304";
  return corpo + crc16(corpo);
}
