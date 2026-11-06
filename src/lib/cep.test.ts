import { test } from "node:test";
import assert from "node:assert/strict";
import { buscarCep, enderecoEmLinha, formatarCep, lerRespostaCep } from "./cep.ts";

test("CEP ganha o traço enquanto digita", () => {
  assert.equal(formatarCep("11430"), "11430");
  assert.equal(formatarCep("114300"), "11430-0");
  assert.equal(formatarCep("11430-0909"), "11430-090");
});

test("lê ViaCEP e BrasilAPI no mesmo formato", () => {
  const esperado = { logradouro: "Avenida Manoel da Cruz Michael", bairro: "Jardim São Manoel", cidade: "Guarujá", uf: "SP" };
  assert.deepEqual(lerRespostaCep({ cep: "11430-090", logradouro: "Avenida Manoel da Cruz Michael", bairro: "Jardim São Manoel", localidade: "Guarujá", uf: "SP" }), esperado);
  assert.deepEqual(lerRespostaCep({ cep: "11430090", street: "Avenida Manoel da Cruz Michael", neighborhood: "Jardim São Manoel", city: "Guarujá", state: "SP" }), esperado);
  assert.equal(lerRespostaCep({ erro: true }), null);
  assert.equal(lerRespostaCep({ erro: "true" }), null);
});

test("se o ViaCEP cai, tenta a BrasilAPI; CEP inexistente não tenta de novo", async () => {
  const urls: string[] = [];
  const falhaViaCep = (async (u: string) => {
    urls.push(u);
    if (u.includes("viacep")) throw new Error("fora do ar");
    return new Response(JSON.stringify({ city: "Santos", state: "SP", street: "Rua A", neighborhood: "Centro" }));
  }) as typeof fetch;
  assert.deepEqual(await buscarCep("11010-000", falhaViaCep), { logradouro: "Rua A", bairro: "Centro", cidade: "Santos", uf: "SP" });
  assert.equal(urls.length, 2);
  const inexistente = (async () => new Response(JSON.stringify({ erro: "true" }))) as typeof fetch;
  assert.equal(await buscarCep("99999999", inexistente), null);
  assert.equal(await buscarCep("123", inexistente), null);
  const tudoFora = (async () => { throw new Error("x"); }) as typeof fetch;
  assert.equal(await buscarCep("11010000", tudoFora), "falhou");
});

test("endereço numa linha pula o que falta", () => {
  assert.equal(enderecoEmLinha({ logradouro: "Rua A", numero: "10", complemento: "Ap 2", bairro: "Centro", cidade: "Santos", uf: "SP" }), "Rua A, 10 - Ap 2 - Centro, Santos - SP");
  assert.equal(enderecoEmLinha({ bairro: "Centro", cidade: "Santos", uf: "SP" }), "Centro, Santos - SP");
  assert.equal(enderecoEmLinha({}), "");
});
