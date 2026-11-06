import { test } from "node:test";
import assert from "node:assert/strict";
import { zonedToUtc, dataLocal, horaLocal, diaIso, somarDias, horariosLivres, horariosLivresDetalhe, lerPeriodo } from "./slots.ts";
import type { Fase } from "./fases.ts";

const SP = "America/Sao_Paulo";

test("converte hora de São Paulo para UTC (UTC-3)", () => {
  assert.equal(zonedToUtc("2026-11-02", "10:00", SP).toISOString(), "2026-11-02T13:00:00.000Z");
  assert.equal(zonedToUtc("2026-11-02", "23:30", SP).toISOString(), "2026-11-03T02:30:00.000Z");
});

test("volta do UTC para data e hora locais", () => {
  const d = new Date("2026-11-03T02:30:00Z");
  assert.equal(dataLocal(d, SP), "2026-11-02");
  assert.equal(horaLocal(d, SP), "23:30");
});

test("dia da semana ISO e soma de dias", () => {
  assert.equal(diaIso("2026-11-02"), 1); // segunda
  assert.equal(diaIso("2026-11-08"), 7); // domingo
  assert.equal(somarDias("2026-11-30", 1), "2026-12-01");
});

const f = (min: number): Fase[] => [{ tipo: "trabalho", min }];
const COR: Fase[] = [{ tipo: "trabalho", min: 40 }, { tipo: "pausa", min: 40 }, { tipo: "trabalho", min: 40 }];
const base = { tz: SP, abre: "08:00", fecha: "18:00", diasSemana: [1, 2, 3, 4, 5], agora: new Date("2026-10-01T00:00:00Z") };

test("dia livre gera horários de meia em meia hora até caber o serviço", () => {
  const h = horariosLivres({ ...base, data: "2026-11-02", fases: f(60), ocupados: [] });
  assert.equal(h[0], "08:00");
  assert.equal(h.at(-1), "17:00");
  assert.equal(h.length, 19);
});

test("fim de semana não tem horários", () => {
  assert.deepEqual(horariosLivres({ ...base, data: "2026-11-07", fases: f(30), ocupados: [] }), []);
});

test("horário ocupado remove todos os começos que se sobrepõem", () => {
  const ocupados = [{ inicio: "2026-11-02T13:00:00Z", fim: "2026-11-02T13:45:00Z" }]; // 10:00-10:45 em SP
  const h = horariosLivres({ ...base, data: "2026-11-02", fases: f(60), ocupados });
  assert.ok(!h.includes("09:30"), "09:30 + 60 min invade o 10:00");
  assert.ok(!h.includes("10:00"));
  assert.ok(!h.includes("10:30"));
  assert.ok(h.includes("09:00"));
  assert.ok(h.includes("11:00"));
});

test("não oferece horário com menos de 1 hora de antecedência", () => {
  const agora = new Date("2026-11-02T11:30:00Z"); // 08:30 em SP
  const h = horariosLivres({ ...base, agora, data: "2026-11-02", fases: f(30), ocupados: [] });
  assert.equal(h[0], "09:30");
});

test("coloração cabe com a pausa por cima de outro atendimento", () => {
  // 10:40-11:20 já ocupado: a coloração das 10:00 tem pausa das 10:40 às 11:20, então cabe
  const ocupados = [{ inicio: "2026-11-02T13:40:00Z", fim: "2026-11-02T14:20:00Z" }];
  const h = horariosLivres({ ...base, data: "2026-11-02", fases: COR, ocupados });
  assert.ok(h.includes("10:00"), "a pausa cobre o horário ocupado");
  assert.ok(!h.includes("09:30"), "a finalização das 09:30 invade o ocupado");
  assert.ok(!h.includes("10:30"), "a aplicação invade o ocupado");
});

test("encaixe: horário livre que cai na pausa de outra química é marcado", () => {
  // coloração das 09:00: trabalho 09:00-09:40 e 10:20-11:00, pausa 09:40-10:20
  const ocupados = [{ inicio: "2026-11-02T12:00:00Z", fim: "2026-11-02T12:40:00Z" }, { inicio: "2026-11-02T13:20:00Z", fim: "2026-11-02T14:00:00Z" }];
  const pausas = [{ inicio: "2026-11-02T12:40:00Z", fim: "2026-11-02T13:20:00Z" }];
  const h = horariosLivresDetalhe({ ...base, data: "2026-11-02", fases: f(30), ocupados, pausas, passoMin: 10 });
  assert.deepEqual(h.find((x) => x.hora === "09:40"), { hora: "09:40", encaixe: true });
  assert.equal(h.find((x) => x.hora === "09:30"), undefined, "invade a aplicação");
  assert.equal(h.find((x) => x.hora === "10:00"), undefined, "invade a finalização");
  assert.deepEqual(h.find((x) => x.hora === "11:00"), { hora: "11:00", encaixe: false });
});

test("almoço bloqueia trabalho, mas aceita a pausa da química", () => {
  const almoco = { inicio: "12:00", fim: "12:40" };
  const corte = horariosLivres({ ...base, data: "2026-11-02", fases: f(30), ocupados: [], almoco });
  assert.ok(!corte.includes("12:00") && !corte.includes("12:30"));
  assert.ok(corte.includes("11:00") && corte.includes("13:00"));
  const cor = horariosLivres({ ...base, data: "2026-11-02", fases: COR, ocupados: [], almoco, passoMin: 10 });
  assert.ok(cor.includes("11:20"), "pausa 12:00-12:40 cai no almoço");
  assert.ok(!cor.includes("11:30"));
});

test("lê o intervalo que o Postgres devolve", () => {
  assert.deepEqual(lerPeriodo('["2026-11-02 13:00:00+00","2026-11-02 13:40:00+00")'), { inicio: "2026-11-02T13:00:00.000Z", fim: "2026-11-02T13:40:00.000Z" });
  assert.deepEqual(lerPeriodo('["2026-11-02 10:00:00-03","2026-11-02 10:40:00-03")'), { inicio: "2026-11-02T13:00:00.000Z", fim: "2026-11-02T13:40:00.000Z" });
  assert.equal(lerPeriodo("lixo"), null);
});
