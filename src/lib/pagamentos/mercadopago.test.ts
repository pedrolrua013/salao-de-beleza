import { test } from "node:test";
import assert from "node:assert/strict";
import { consultarPagamentoMP, criarPixMP } from "./mercadopago.ts";

function falsoFetch(resposta: unknown, status = 200) {
  const chamadas: { url: string; init?: RequestInit }[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string, init?: RequestInit) => { chamadas.push({ url, init }); return new Response(JSON.stringify(resposta), { status }); }) as typeof fetch;
  return { chamadas, restaurar: () => { globalThis.fetch = original; } };
}

test("cria o Pix com valor em reais, idempotência e expiração", async () => {
  const f = falsoFetch({ id: 123, point_of_interaction: { transaction_data: { qr_code: "000201abc", qr_code_base64: "iVBOR" } } }, 201);
  try {
    const p = await criarPixMP({ token: "TEST-x", valorCentavos: 6000, descricao: "Sinal", referencia: "ag-1", expiraEm: new Date("2026-11-02T13:30:00Z") });
    assert.deepEqual(p, { id: "123", copiaECola: "000201abc", qrBase64: "iVBOR" });
    const corpo = JSON.parse(String(f.chamadas[0].init?.body));
    assert.equal(corpo.transaction_amount, 60);
    assert.equal(corpo.payment_method_id, "pix");
    assert.equal(corpo.date_of_expiration, "2026-11-02T13:30:00.000-00:00");
    assert.equal((f.chamadas[0].init?.headers as Record<string, string>)["X-Idempotency-Key"], "ag-1");
  } finally { f.restaurar(); }
});

test("erro do Mercado Pago vira exceção", async () => {
  const f = falsoFetch({ message: "invalid token" }, 401);
  try { await assert.rejects(criarPixMP({ token: "x", valorCentavos: 1, descricao: "", referencia: "r", expiraEm: new Date() }), /401/); }
  finally { f.restaurar(); }
});

test("consulta o pagamento e lê aprovado e valor", async () => {
  const f = falsoFetch({ status: "approved", transaction_amount: 60 });
  try {
    assert.deepEqual(await consultarPagamentoMP("t", "123"), { aprovado: true, valorCentavos: 6000 });
    assert.equal(await consultarPagamentoMP("t", "../admin"), null, "id estranho nem consulta");
    assert.equal(f.chamadas.length, 1);
  } finally { f.restaurar(); }
});
