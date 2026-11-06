import { test } from "node:test";
import assert from "node:assert/strict";
import { todasAsLinhas } from "./paginar.ts";

const tabela = Array.from({ length: 2345 }, (_, i) => i);
const consulta = (de: number, ate: number) => Promise.resolve({ data: tabela.slice(de, ate + 1), error: null });

test("junta todas as páginas de 1.000", async () => {
  const pedidos: number[] = [];
  const r = await todasAsLinhas((de, ate) => { pedidos.push(de); return consulta(de, ate); });
  assert.equal(r.length, 2345);
  assert.deepEqual(pedidos, [0, 1000, 2000]);
});

test("erro em qualquer página não devolve lista pela metade", async () => {
  await assert.rejects(todasAsLinhas((de, ate) => (de === 1000 ? Promise.resolve({ data: null, error: { message: "caiu" } }) : consulta(de, ate))), /caiu/);
});
