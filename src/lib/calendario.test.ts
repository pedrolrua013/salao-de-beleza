import { test } from "node:test";
import assert from "node:assert/strict";
import { dataBr, lerDataBr, mascararData, semanasDoMes } from "./calendario.ts";

test("data: máscara enquanto digita", () => {
  assert.equal(mascararData("3"), "3");
  assert.equal(mascararData("311"), "31/1");
  assert.equal(mascararData("31121990"), "31/12/1990");
  assert.equal(mascararData("31/12/1990 extra 55"), "31/12/1990");
});

test("data: lê só datas que existem", () => {
  assert.equal(lerDataBr("31/12/1990"), "1990-12-31");
  assert.equal(lerDataBr("29/02/2024"), "2024-02-29");
  assert.equal(lerDataBr("29/02/2023"), null, "2023 não é bissexto");
  assert.equal(lerDataBr("31/04/2026"), null);
  assert.equal(lerDataBr("12/1990"), null);
  assert.equal(dataBr("1990-12-31"), "31/12/1990");
  assert.equal(dataBr(""), "");
});

test("data: grade do mês começa no domingo", () => {
  const out = semanasDoMes(2026, 10); // 1/10/2026 é quinta
  assert.deepEqual(out[0], [null, null, null, null, 1, 2, 3]);
  assert.equal(out.flat().filter(Boolean).length, 31);
  assert.ok(out.every((s) => s.length === 7));
});
