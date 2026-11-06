import { test } from "node:test";
import assert from "node:assert/strict";
import { crc16, normalizarChavePix, pixCopiaECola, tipoChavePix } from "./pix.ts";

test("CRC16-CCITT confere com o valor de referência", () => {
  assert.equal(crc16("123456789"), "29B1");
});

test("monta o Pix copia e cola com chave, valor, nome, cidade e identificador", () => {
  const p = pixCopiaECola({ chave: "studiobela@exemplo.com", nome: "Studio Bela Cabeleireiros Associados", cidade: "São Paulo", valorCentavos: 6000, txid: "SINAL-ab12cd34" });
  assert.ok(p.startsWith("000201"));
  assert.match(p, /0014br\.gov\.bcb\.pix0122studiobela@exemplo\.com/);
  assert.match(p, /5303986/);
  assert.match(p, /540560\.00/);
  assert.match(p, /5925Studio Bela Cabeleireiro/, "nome cortado em 25");
  assert.match(p, /6009Sao Paulo/, "sem acento");
  assert.match(p, /62170513SINALab12cd34/);
  assert.equal(p.slice(-4), crc16(p.slice(0, -4)), "termina com o CRC do resto");
});

test("sem identificador usa ***", () => {
  const p = pixCopiaECola({ chave: "11999990000", nome: "Ana", cidade: "Rio", valorCentavos: 100 });
  assert.match(p, /62070503\*\*\*/);
});

test("chave Pix digitada com formatação vira o formato do BR Code", () => {
  assert.equal(normalizarChavePix("(11) 99999-0000"), "+5511999990000");
  assert.equal(normalizarChavePix("+55 11 99999-0000"), "+5511999990000");
  assert.equal(normalizarChavePix("11999990000"), "+5511999990000", "11 números que não são CPF válido: celular");
  assert.equal(normalizarChavePix("529.982.247-25"), "52998224725");
  // Celular cujos 11 números também passam como CPF: com máscara de telefone, é celular.
  assert.equal(normalizarChavePix("52998224725"), "52998224725", "só números e CPF válido: CPF");
  assert.equal(normalizarChavePix("(52) 99822-4725"), "+5552998224725");
  assert.equal(normalizarChavePix("52 99822-4725"), "+5552998224725");
  assert.equal(tipoChavePix("+5552998224725"), "celular");
  assert.equal(tipoChavePix("52998224725"), "CPF");
  assert.equal(tipoChavePix("12345678000195"), "CNPJ");
  assert.equal(tipoChavePix("a@b.com"), "e-mail");
  assert.equal(normalizarChavePix("12.345.678/0001-95"), "12345678000195");
  assert.equal(normalizarChavePix(" Studio@Exemplo.com "), "studio@exemplo.com");
  assert.equal(normalizarChavePix("123E4567-E89B-12D3-A456-426614174000"), "123e4567-e89b-12d3-a456-426614174000");
  assert.equal(normalizarChavePix("minha chave"), null);
  assert.equal(normalizarChavePix("1234"), null);
  assert.match(pixCopiaECola({ chave: "(11) 99999-0000", nome: "Ana", cidade: "Rio", valorCentavos: 100 }), /0114\+5511999990000/);
});
