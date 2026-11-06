// Importação de clientes: reconhece as colunas da planilha, limpa os dados e confere de novo no servidor.
import { lerData } from "./csv.ts";
import { UFS } from "./cep.ts";

export const CAMPOS = [
  ["nome", "Nome"], ["telefone", "Celular"], ["email", "E-mail"], ["nascimento", "Nascimento"],
  ["cep", "CEP"], ["logradouro", "Rua"], ["numero", "Número"], ["complemento", "Complemento"], ["bairro", "Bairro"], ["cidade", "Cidade"], ["uf", "Estado"],
  ["alergias", "Alergias"], ["observacoes", "Observações"],
] as const;
export type Campo = (typeof CAMPOS)[number][0];
export type Mapa = Record<Campo, number>; // índice da coluna; -1 = não importar

export type ClienteImportado = {
  nome: string; telefone: string | null; email: string | null; nascimento: string | null;
  cep: string | null; logradouro: string | null; numero: string | null; complemento: string | null; bairro: string | null; cidade: string | null; uf: string | null;
  alergias: string | null; observacoes: string | null;
};

const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
const NOMES: Record<Campo, string[]> = {
  nome: ["nome", "cliente", "nomecompleto", "nomedocliente", "nomedacliente", "name", "fullname", "razaosocial"],
  telefone: ["celular", "telefone", "whatsapp", "fone", "telefonecelular", "cel", "telefone1", "celular1", "telefoneprincipal", "phone", "mobile", "zap", "contato"],
  email: ["email", "correioeletronico", "mail", "email1"],
  nascimento: ["nascimento", "datadenascimento", "aniversario", "datanascimento", "dtnascimento", "dtnasc", "datanasc", "birthday", "dataaniversario"],
  cep: ["cep", "codigopostal", "zipcode", "zip"],
  logradouro: ["rua", "endereco", "logradouro", "avenida", "address", "enderecocompleto"],
  numero: ["numero", "num", "no", "n", "nro"],
  complemento: ["complemento", "compl", "apto", "apartamento"],
  bairro: ["bairro", "distrito", "neighborhood"],
  cidade: ["cidade", "municipio", "city", "localidade"],
  uf: ["uf", "estado", "state"],
  alergias: ["alergias", "alergia", "sensibilidades", "restricoes"],
  observacoes: ["observacoes", "observacao", "obs", "anotacoes", "notas", "nota", "comentarios", "comentario"],
};

/** Acha cada campo pelo nome da coluna. Sem nada reconhecido, a primeira linha já é cliente (sem cabeçalho). */
export function detectarMapa(cabecalho: string[]): { mapa: Mapa; temCabecalho: boolean } {
  const cab = cabecalho.map(norm);
  const mapa = Object.fromEntries(CAMPOS.map(([k]) => [k, -1])) as Mapa;
  const usados = new Set<number>();
  // Primeiro os nomes exatos, depois "começa com" (ex.: "Celular (WhatsApp)").
  for (const exato of [true, false]) for (const [k] of CAMPOS) {
    if (mapa[k] >= 0) continue;
    const i = cab.findIndex((c, j) => !usados.has(j) && c && NOMES[k].some((n) => (exato ? c === n : n.length >= 3 && c.startsWith(n))));
    if (i >= 0) { mapa[k] = i; usados.add(i); }
  }
  const achados = CAMPOS.filter(([k]) => mapa[k] >= 0).length;
  if (achados > 0) return { mapa, temCabecalho: true };
  return { mapa: adivinharSemCabecalho(cabecalho), temCabecalho: false };
}

/** Sem cabeçalho: a coluna com celular vira telefone, com @ vira e-mail, e a primeira de texto vira nome. */
function adivinharSemCabecalho(l: string[]): Mapa {
  const mapa = Object.fromEntries(CAMPOS.map(([k]) => [k, -1])) as Mapa;
  l.forEach((v, i) => {
    const d = v.replace(/\D/g, "");
    if (mapa.email < 0 && /@/.test(v)) mapa.email = i;
    else if (mapa.telefone < 0 && d.length >= 8 && d.length <= 13 && !/[a-z]/i.test(v) && !/\d{1,2}\/\d{1,2}\/\d/.test(v)) mapa.telefone = i;
    else if (mapa.nascimento < 0 && lerData(v)) mapa.nascimento = i;
    else if (mapa.nome < 0 && /[a-zà-ú]{2}/i.test(v)) mapa.nome = i;
  });
  return mapa;
}

/** Data de nascimento: texto ("31/12/1990") ou número de série do Excel (33238). */
export function lerNascimento(v: string): string | null {
  const t = v.trim();
  if (/^\d{4,5}(\.0+)?$/.test(t)) {
    const n = Math.floor(Number(t));
    if (n > 366 && n < 60000) return lerData(new Date(Date.UTC(1899, 11, 30) + n * 86400000).toISOString().slice(0, 10));
  }
  return lerData(t.replace(/\s.*$/, "")); // "31/12/1990 00:00:00"
}

/** Celular com DDD (10 ou 11 números). Sem DDD, usa o DDD do salão. */
export function lerTelefone(v: string, ddd: string | null): string | null {
  let d = v.replace(/\D/g, "");
  if (d.length > 11 && d.startsWith("55")) d = d.slice(2);
  // Zero na frente: "011 98888-7777" (0 + DDD) perde só o zero; "015 11 98888-7777" (0 + operadora + DDD) perde zero e operadora.
  if (d.startsWith("0")) d = d.length >= 13 ? d.slice(3) : d.slice(1);
  if ((d.length === 8 || d.length === 9) && ddd && /^\d{2}$/.test(ddd)) d = ddd + d;
  return /^[1-9]\d{9,10}$/.test(d) ? d : null;
}

const limpo = (s: string, max: number) => s.trim().replace(/\s+/g, " ").slice(0, max) || null;

export type Lida = { cliente: ClienteImportado; avisos: string[] } | { ignorada: string };

/** Uma linha da planilha → cliente (ou o motivo de ser ignorada). Telefone que não dá para usar vai para as observações. */
export function clienteDaLinha(l: string[], mapa: Mapa, ddd: string | null): Lida {
  const pega = (k: Campo) => (mapa[k] >= 0 ? String(l[mapa[k]] ?? "").trim() : "");
  const nome = limpo(pega("nome"), 120);
  if (!nome || nome.length < 2 || !/[a-zà-ú]/i.test(nome)) return { ignorada: "sem nome" };
  const avisos: string[] = [];
  const telBruto = pega("telefone");
  const telefone = telBruto ? lerTelefone(telBruto, ddd) : null;
  const obs: string[] = [];
  if (telBruto && !telefone) { avisos.push("celular incompleto"); obs.push(`Telefone na planilha: ${telBruto.slice(0, 40)}`); }
  const emailBruto = pega("email").toLowerCase();
  const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailBruto) ? emailBruto.slice(0, 200) : null;
  if (emailBruto && !email) avisos.push("e-mail inválido");
  const nascBruto = pega("nascimento");
  const nascimento = nascBruto ? lerNascimento(nascBruto) : null;
  if (nascBruto && !nascimento) avisos.push("nascimento inválido");
  const cep = pega("cep").replace(/\D/g, "").padStart(8, "0");
  const uf = pega("uf").toUpperCase().trim();
  const outras = pega("observacoes");
  if (outras) obs.push(outras);
  return {
    cliente: {
      nome, telefone, email, nascimento,
      cep: /^\d{8}$/.test(cep) && cep !== "00000000" ? cep : null,
      logradouro: limpo(pega("logradouro"), 200), numero: limpo(pega("numero"), 20), complemento: limpo(pega("complemento"), 100),
      bairro: limpo(pega("bairro"), 100), cidade: limpo(pega("cidade"), 100), uf: UFS.includes(uf) ? uf : null,
      alergias: limpo(pega("alergias"), 500), observacoes: obs.join("\n").slice(0, 2000) || null,
    },
    avisos,
  };
}

/** Chave para achar repetidas: celular, ou o nome sem acento quando não há celular. */
export const chaveCliente = (c: { nome: string; telefone: string | null }) =>
  c.telefone ? `t:${c.telefone.replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "")}` : `n:${norm(c.nome)}`;

export type Resumo = { clientes: ClienteImportado[]; semNome: number; repetidasNaPlanilha: number; comAviso: number };

/** Todas as linhas (sem o cabeçalho) → clientes prontas, já sem repetidas dentro da própria planilha. */
export function prepararClientes(linhas: string[][], mapa: Mapa, ddd: string | null): Resumo {
  const vistos = new Set<string>();
  const r: Resumo = { clientes: [], semNome: 0, repetidasNaPlanilha: 0, comAviso: 0 };
  for (const l of linhas) {
    const x = clienteDaLinha(l, mapa, ddd);
    if ("ignorada" in x) { r.semNome++; continue; }
    const k = chaveCliente(x.cliente);
    if (vistos.has(k)) { r.repetidasNaPlanilha++; continue; }
    vistos.add(k);
    if (x.avisos.length) r.comAviso++;
    r.clientes.push(x.cliente);
  }
  return r;
}

/** O servidor não confia no navegador: confere cada campo de novo. */
export function validarImportado(x: unknown): ClienteImportado | null {
  if (!x || typeof x !== "object") return null;
  const o = x as Record<string, unknown>;
  const s = (k: string, max: number, re?: RegExp) => {
    const v = typeof o[k] === "string" ? (o[k] as string).trim() : "";
    return v && v.length <= max && (!re || re.test(v)) ? v : null;
  };
  const nome = s("nome", 120);
  if (!nome || nome.length < 2) return null;
  const nasc = s("nascimento", 10, /^\d{4}-\d{2}-\d{2}$/);
  return {
    nome, telefone: s("telefone", 11, /^[1-9]\d{9,10}$/), email: s("email", 200, /^[^\s@]+@[^\s@]+\.[^\s@]+$/),
    nascimento: nasc && lerData(nasc) ? nasc : null,
    cep: s("cep", 8, /^\d{8}$/), logradouro: s("logradouro", 200), numero: s("numero", 20), complemento: s("complemento", 100),
    bairro: s("bairro", 100), cidade: s("cidade", 100), uf: s("uf", 2, /^[A-Z]{2}$/) && UFS.includes(o.uf as string) ? (o.uf as string) : null,
    alergias: s("alergias", 500), observacoes: s("observacoes", 2000),
  };
}

/** "A", "B", ... "AA" para quando a planilha não tem cabeçalho. */
export const letraColuna = (i: number): string => (i < 26 ? String.fromCharCode(65 + i) : letraColuna(Math.floor(i / 26) - 1) + String.fromCharCode(65 + (i % 26)));
