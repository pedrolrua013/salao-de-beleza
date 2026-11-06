import { test } from "node:test";
import assert from "node:assert/strict";
import { comDesconto, descreverPromocao, mapaOcupacao, promocaoPara, type Promocao } from "./promocoes.ts";

const SP = "America/Sao_Paulo";
const base: Promocao = { id: "p", nome: "Terça", tipo: "horario", percentual: 20, dias_semana: [2], hora_inicio: "09:00:00", hora_fim: "12:00:00", horas_antes: null, servico_ids: null, valida_ate: null, ativa: true };

test("promoção de dia e horário vale só na janela", () => {
  assert.equal(promocaoPara([base], "s", new Date("2026-11-03T13:00:00Z"), SP)?.percentual, 20); // terça 10h
  assert.equal(promocaoPara([base], "s", new Date("2026-11-03T15:00:00Z"), SP), null);               // terça 12h
  assert.equal(promocaoPara([base], "s", new Date("2026-11-04T13:00:00Z"), SP), null);               // quarta
});

test("escolhe a maior e respeita serviço, validade e desligada", () => {
  const outra = { ...base, id: "q", percentual: 30, servico_ids: ["x"] };
  assert.equal(promocaoPara([base, outra], "x", new Date("2026-11-03T13:00:00Z"), SP)?.id, "q");
  assert.equal(promocaoPara([base, outra], "y", new Date("2026-11-03T13:00:00Z"), SP)?.id, "p");
  assert.equal(promocaoPara([{ ...base, valida_ate: "2026-11-02" }], "s", new Date("2026-11-03T13:00:00Z"), SP), null);
  assert.equal(promocaoPara([{ ...base, ativa: false }], "s", new Date("2026-11-03T13:00:00Z"), SP), null);
});

test("última hora vale só para horários que começam logo", () => {
  const u: Promocao = { ...base, tipo: "ultima_hora", dias_semana: [1, 2, 3, 4, 5, 6, 7], hora_inicio: null, hora_fim: null, horas_antes: 3 };
  const agora = new Date("2026-11-03T12:00:00Z");
  assert.equal(promocaoPara([u], "s", new Date("2026-11-03T14:00:00Z"), SP, agora)?.percentual, 20);
  assert.equal(promocaoPara([u], "s", new Date("2026-11-03T16:00:00Z"), SP, agora), null);
});

test("desconto e descrição", () => {
  assert.equal(comDesconto(8000, 20), 6400);
  assert.equal(descreverPromocao(base), "Ter, das 9h às 12h: 20% off");
});

test("mapa mostra a ocupação por dia e hora", () => {
  const jornadas = new Map([["a", { dias: [1], abre: "09:00", fecha: "11:00", almoco: null }]]);
  // segunda 02/11 09:00 a 10:00 (SP), uma semana
  const m = mapaOcupacao([{ inicio: "2026-11-02T12:00:00Z", fim: "2026-11-02T13:00:00Z", profissional_id: "a" }], jornadas, SP, 1);
  assert.deepEqual(m.horas, [9, 10]);
  assert.equal(m.celulas.find((c) => c.dia === 1 && c.hora === 9)?.ocupacao, 1);
  assert.equal(m.celulas.find((c) => c.dia === 1 && c.hora === 10)?.ocupacao, 0);
  assert.equal(m.celulas.find((c) => c.dia === 2 && c.hora === 9)?.ocupacao, null);
  assert.deepEqual(m.vazios.map((c) => [c.dia, c.hora]), [[1, 10]]);
});
