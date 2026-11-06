import { test } from "node:test";
import assert from "node:assert/strict";
import { iaDisponivel, sistemaIA } from "./ia.ts";

test("a IA só liga com a chave no servidor", () => {
  assert.equal(iaDisponivel({}), false);
  assert.equal(iaDisponivel({ ANTHROPIC_API_KEY: "x" }), true);
});

test("instruções levam os dados do salão e as regras", () => {
  const s = sistemaIA({ nome: "Studio Bela", endereco: "Rua A, 10", telefone: null, horario: "Seg a Sex, 9h às 18h", link: "https://x/s/bela",
    servicos: [{ nome: "Escova", preco_centavos: 5000, duracao_min: 45 }], promocoes: ["Terça 20% off"], instrucoes: "Temos estacionamento." });
  assert.match(s, /Escova: R\$\s?50,00, cerca de 45 min/);
  assert.match(s, /não marca, remarca nem cancela/);
  assert.match(s, /Temos estacionamento/);
  assert.match(s, /Terça 20% off/);
});
