import { test } from "node:test";
import assert from "node:assert/strict";
import { sugerirCompra, textoPedido, type ProdutoEstoque } from "./compras.ts";

const base: ProdutoEstoque = { id: "a", nome: "Shampoo", unidade: "un", conteudo: 1, estoque: 2, estoque_minimo: 3, estoque_ideal: 10, custo_centavos: 1500, fornecedor_id: null };

test("pede até o ideal, em embalagens", () => {
  assert.equal(sugerirCompra([base])[0].embalagens, 8);
  const tinta = { ...base, id: "b", nome: "Tinta", unidade: "g" as const, conteudo: 60, estoque: 50, estoque_minimo: 120, estoque_ideal: 600 };
  assert.equal(sugerirCompra([tinta])[0].embalagens, 10); // (600 - 50) / 60 = 9,2 → 10 tubos
});

test("sem ideal pede o dobro do mínimo; acima do mínimo não pede", () => {
  assert.equal(sugerirCompra([{ ...base, estoque_ideal: null }])[0].embalagens, 4);
  assert.equal(sugerirCompra([{ ...base, estoque: 5 }]).length, 0);
  assert.equal(sugerirCompra([{ ...base, estoque_minimo: 0 }]).length, 0);
});

test("texto do pedido", () => {
  assert.match(textoPedido("Studio Bela", [{ nome: "Shampoo", embalagens: 8 }]), /Pedido do Studio Bela:\n• 8 × Shampoo/);
});
