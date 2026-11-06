import { test } from "node:test";
import assert from "node:assert/strict";
import { assinaturaValida, cpfValido } from "./termos.ts";

test("CPF confere os dígitos", () => {
  assert.equal(cpfValido("529.982.247-25"), true);
  assert.equal(cpfValido("52998224726"), false);
  assert.equal(cpfValido("111.111.111-11"), false);
  assert.equal(cpfValido("123"), false);
});

test("assinatura precisa ser um PNG desenhado", () => {
  assert.equal(assinaturaValida("data:image/png;base64," + "A".repeat(300)), true);
  assert.equal(assinaturaValida("data:image/png;base64,AAAA"), false);
  assert.equal(assinaturaValida("data:image/svg+xml;base64," + "A".repeat(300)), false);
  assert.equal(assinaturaValida("data:image/png;base64," + "A".repeat(400_001)), false);
});
