import { test } from "node:test";
import assert from "node:assert/strict";
import { voltaSegura } from "./volta.ts";

test("aceita caminhos internos com parâmetros", () => {
  assert.equal(voltaSegura("/agenda?data=2026-11-02"), "/agenda?data=2026-11-02");
  assert.equal(voltaSegura("/caixa"), "/caixa");
});

test("recusa outros sites e lixo", () => {
  for (const v of ["//mal.com", "/\\mal.com", "https://mal.com", "javascript:alert(1)", "agenda", "", null, undefined, 5, "/a b", "/" + "a".repeat(400)]) {
    assert.equal(voltaSegura(v), null, String(v));
  }
});
