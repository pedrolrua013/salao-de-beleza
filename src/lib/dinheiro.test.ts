import { test } from "node:test";
import assert from "node:assert/strict";
import { campoReais, lerReais, reais } from "./dinheiro.ts";

test("formata centavos em reais", () => {
  assert.equal(reais(123456), "R$ 1.234,56");
  assert.equal(reais(0), "R$ 0,00");
  assert.equal(campoReais(4550), "45,50");
});

test("lê valores digitados do jeito brasileiro", () => {
  assert.equal(lerReais("45"), 4500);
  assert.equal(lerReais("45,5"), 4550);
  assert.equal(lerReais("1.234,56"), 123456);
  assert.equal(lerReais("R$ 1.234"), 123400);
  assert.equal(lerReais("12.50"), 1250);
  assert.equal(lerReais(""), null);
  assert.equal(lerReais("abc"), null);
  assert.equal(lerReais("-5"), null);
  assert.equal(lerReais("1,234"), null);
});
