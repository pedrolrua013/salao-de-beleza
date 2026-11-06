import { test } from "node:test";
import assert from "node:assert/strict";
import { formatarTelefone } from "./telefone.ts";

test("telefone: formata enquanto digita", () => {
  assert.equal(formatarTelefone(""), "");
  assert.equal(formatarTelefone("1"), "(1");
  assert.equal(formatarTelefone("13"), "(13");
  assert.equal(formatarTelefone("139"), "(13) 9");
  assert.equal(formatarTelefone("139999"), "(13) 9999");
  assert.equal(formatarTelefone("1399990"), "(13) 9999-0");
  assert.equal(formatarTelefone("1333334444"), "(13) 3333-4444", "fixo");
  assert.equal(formatarTelefone("13999990000"), "(13) 99999-0000", "celular");
});

test("telefone: aceita o que vier colado e corta o excesso", () => {
  assert.equal(formatarTelefone("+55 (13) 99999-0000"), "(13) 99999-0000");
  assert.equal(formatarTelefone("13 99999 0000 123"), "(13) 99999-0000");
});
