// Horários e fuso. Sem dependências externas, para rodar igual no servidor, no navegador e nos testes.
import { blocos, totalMin, type Fase } from "./fases.ts";

type Partes = Record<string, number>;

function partes(d: Date, tz: string): Partes {
  const f = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz, hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const o: Partes = {};
  for (const p of f.formatToParts(d)) if (p.type !== "literal") o[p.type] = Number(p.value);
  return o;
}

/** "2026-11-02" + "10:00" no fuso tz → instante UTC. */
export function zonedToUtc(data: string, hora: string, tz: string): Date {
  const [y, m, d] = data.split("-").map(Number);
  const [h, mi] = hora.split(":").map(Number);
  const alvo = Date.UTC(y, m - 1, d, h, mi);
  let utc = alvo;
  for (let i = 0; i < 2; i++) {
    const p = partes(new Date(utc), tz);
    const visto = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
    utc += alvo - visto;
  }
  return new Date(utc);
}

/** Data local (YYYY-MM-DD) de um instante no fuso tz. */
export function dataLocal(d: Date, tz: string): string {
  const p = partes(d, tz);
  return `${p.year}-${String(p.month).padStart(2, "0")}-${String(p.day).padStart(2, "0")}`;
}

export function horaLocal(d: Date | string, tz: string): string {
  const p = partes(typeof d === "string" ? new Date(d) : d, tz);
  return `${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
}

/** 1 = segunda ... 7 = domingo, para uma data YYYY-MM-DD. */
export function diaIso(data: string): number {
  const [y, m, d] = data.split("-").map(Number);
  const w = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return w === 0 ? 7 : w;
}

export function somarDias(data: string, n: number): string {
  const [y, m, d] = data.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return t.toISOString().slice(0, 10);
}

export function minutos(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

export type Intervalo = { inicio: string; fim: string };

export type OpcoesHorarios = {
  data: string;
  tz: string;
  abre: string;
  fecha: string;
  diasSemana: number[];
  /** Fases do serviço. Só as de trabalho precisam de profissional livre. */
  fases: Fase[];
  /** Fases de trabalho e bloqueios já marcados para o profissional (a tabela ocupacoes). */
  ocupados: Intervalo[];
  /** Almoço do profissional, em hora local ("12:00"–"13:00"). A pausa de uma química pode cair nele. */
  almoco?: { inicio: string; fim: string } | null;
  /** Pausas de outros atendimentos do profissional: um horário que cai nelas é um encaixe. */
  pausas?: Intervalo[];
  agora?: Date;
  antecedenciaMin?: number;
  passoMin?: number;
};

export type HorarioLivre = { hora: string; encaixe: boolean };

/** Horários livres de um dia para um profissional, marcando os que são encaixe na pausa de outro atendimento. */
export function horariosLivresDetalhe(o: OpcoesHorarios): HorarioLivre[] {
  if (!o.diasSemana.includes(diaIso(o.data))) return [];
  const agora = o.agora ?? new Date();
  const limite = agora.getTime() + (o.antecedenciaMin ?? 60) * 60_000;
  const passo = o.passoMin ?? 30;
  const duracao = totalMin(o.fases);
  const ocupados = o.ocupados.map((x) => [Date.parse(x.inicio), Date.parse(x.fim)] as const);
  if (o.almoco) ocupados.push([zonedToUtc(o.data, o.almoco.inicio, o.tz).getTime(), zonedToUtc(o.data, o.almoco.fim, o.tz).getTime()]);
  const pausas = (o.pausas ?? []).map((x) => [Date.parse(x.inicio), Date.parse(x.fim)] as const);
  const saida: HorarioLivre[] = [];
  for (let t = minutos(o.abre); t + duracao <= minutos(o.fecha); t += passo) {
    const hhmm = `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`;
    const ini = zonedToUtc(o.data, hhmm, o.tz).getTime();
    if (ini < limite) continue;
    const trabalho = blocos(ini, o.fases).filter((b) => b.tipo === "trabalho");
    if (trabalho.some((b) => ocupados.some(([a, z]) => b.inicio < z && b.fim > a))) continue;
    saida.push({ hora: hhmm, encaixe: trabalho.some((b) => pausas.some(([a, z]) => b.inicio < z && b.fim > a)) });
  }
  return saida;
}

/** Horários livres de um dia para um profissional. Devolve horas locais "HH:MM". */
export function horariosLivres(o: OpcoesHorarios): string[] {
  return horariosLivresDetalhe(o).map((h) => h.hora);
}

/** Lê um tstzrange do Postgres ('["2026-11-02 13:00:00+00","2026-11-02 13:40:00+00")') como intervalo ISO. */
export function lerPeriodo(r: string): Intervalo | null {
  const m = /^[[(]"?([^",]+)"?,"?([^")\]]+)"?[)\]]$/.exec(r.trim());
  if (!m) return null;
  const iso = (x: string) => new Date(x.replace(" ", "T").replace(/([+-]\d{2})$/, "$1:00")).toISOString();
  return { inicio: iso(m[1]), fim: iso(m[2]) };
}
