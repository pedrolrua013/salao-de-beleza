import { test } from "node:test";
import assert from "node:assert/strict";
import { ipDoCliente } from "./limite.ts";

test("IP: usa o cabeçalho da hospedagem e ignora o que a pessoa inventa", () => {
  const h = new Headers({ "x-real-ip": "203.0.113.9", "cf-connecting-ip": "1.1.1.1", "x-forwarded-for": "6.6.6.6, 203.0.113.9" });
  assert.equal(ipDoCliente(h, {}), "203.0.113.9");
  assert.equal(ipDoCliente(new Headers({ "x-forwarded-for": "6.6.6.6, 203.0.113.9" }), {}), "203.0.113.9", "sem x-real-ip: o último salto, que o proxy escreveu");
  assert.equal(ipDoCliente(h, { IP_CABECALHO: "cf-connecting-ip" }), "1.1.1.1");
  assert.equal(ipDoCliente(new Headers({ "x-real-ip": "'; drop table--" }), {}), null);
  assert.equal(ipDoCliente(new Headers({ "x-real-ip": "abc" }), {}), null, "texto que só parece IP não passa");
  assert.equal(ipDoCliente(new Headers({ "x-real-ip": "999.1.1.1" }), {}), null);
  assert.equal(ipDoCliente(new Headers({ "x-real-ip": "2001:db8::1" }), {}), "2001:db8::1");
  // Atrás do Cloudflare: o x-real-ip que a pessoa manda é ignorado; vale o cf-connecting-ip, que o Cloudflare reescreve.
  assert.equal(ipDoCliente(new Headers({ "x-real-ip": "6.6.6.6", "cf-connecting-ip": "203.0.113.9" }), { IP_CABECALHO: "cf-connecting-ip" }), "203.0.113.9");
});
