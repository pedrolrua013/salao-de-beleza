import { test } from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { assinaturaValida, lerWebhook, montarEnvio, enviar } from "./meta.ts";

const corpo = JSON.stringify({ a: 1 });
const sig = (c: string, s: string) => "sha256=" + createHmac("sha256", s).update(c).digest("hex");

test("assinatura: aceita a correta e recusa o resto", () => {
  assert.equal(assinaturaValida(corpo, sig(corpo, "segredo"), "segredo"), true);
  assert.equal(assinaturaValida(corpo, sig(corpo, "outro"), "segredo"), false);
  assert.equal(assinaturaValida(corpo + " ", sig(corpo, "segredo"), "segredo"), false);
  assert.equal(assinaturaValida(corpo, null, "segredo"), false);
  assert.equal(assinaturaValida(corpo, "sha256=zz", "segredo"), false);
  assert.equal(assinaturaValida(corpo, sig(corpo, ""), undefined), false, "sem segredo configurado nada passa");
});

const hook = (messages: unknown[], extra: object = {}) => ({
  object: "whatsapp_business_account",
  entry: [{ id: "1", changes: [{ field: "messages", value: { metadata: { phone_number_id: "555", display_phone_number: "1" }, contacts: [{ wa_id: "5511999990001", profile: { name: "Marina" } }], messages, ...extra } }] }],
});

test("webhook: lê texto, botão, lista e marca tipos não suportados", () => {
  const ev = lerWebhook(hook([
    { from: "5511999990001", id: "w1", type: "text", text: { body: "oi" } },
    { from: "5511999990001", id: "w2", type: "interactive", interactive: { type: "button_reply", button_reply: { id: "agendar", title: "Agendar horário" } } },
    { from: "5511999990001", id: "w3", type: "interactive", interactive: { type: "list_reply", list_reply: { id: "srv:1", title: "Escova" } } },
    { from: "5511999990001", id: "w4", type: "audio", audio: {} },
    { from: "5511999990001", id: "w5", type: "reaction", reaction: {} },
  ]));
  assert.deepEqual(ev.map((e) => [e.tipo, e.texto, e.id, e.suportado]), [
    ["texto", "oi", undefined, true], ["interativo", "Agendar horário", "agendar", true], ["interativo", "Escova", "srv:1", true], ["audio", "[áudio]", undefined, false],
  ]);
  assert.equal(ev[0].nome, "Marina");
  assert.equal(ev[0].phoneNumberId, "555");
});

test("webhook: ignora status de entrega, lixo e remetente inválido", () => {
  assert.deepEqual(lerWebhook(hook([], { statuses: [{ id: "x", status: "delivered" }] })), []);
  assert.deepEqual(lerWebhook(null), []);
  assert.deepEqual(lerWebhook({ entry: "x" }), []);
  assert.deepEqual(lerWebhook(hook([{ from: "abc", id: "w", type: "text", text: { body: "x" } }])), []);
});

test("envio: corta textos nos limites da Meta", () => {
  const b: any = montarEnvio("5511", { tipo: "botoes", corpo: "x".repeat(2000), botoes: [{ id: "a", titulo: "Um título bem comprido demais" }, { id: "b", titulo: "B" }, { id: "c", titulo: "C" }, { id: "d", titulo: "D" }] });
  assert.equal(b.interactive.body.text.length, 1024);
  assert.equal(b.interactive.action.buttons.length, 3);
  assert.ok(b.interactive.action.buttons[0].reply.title.length <= 20);
  const l: any = montarEnvio("5511", { tipo: "lista", corpo: "oi", botao: "Ver todas as opções disponíveis", itens: Array.from({ length: 15 }, (_, i) => ({ id: String(i), titulo: "t".repeat(40), descricao: "d".repeat(100) })) });
  assert.equal(l.interactive.action.sections[0].rows.length, 10);
  assert.ok(l.interactive.action.sections[0].rows[0].title.length <= 24);
  assert.ok(l.interactive.action.sections[0].rows[0].description.length <= 72);
  assert.ok(l.interactive.action.button.length <= 20);
});

test("envio: devolve id em caso de sucesso e detecta janela de 24 h fechada", async () => {
  const ok = await enviar({ phone_number_id: "555", token: "t".repeat(30) }, "5511999990001", { tipo: "texto", corpo: "oi" },
    (async () => new Response(JSON.stringify({ messages: [{ id: "wamid.9" }] }), { status: 200 })) as typeof fetch);
  assert.deepEqual(ok, { ok: true, msgId: "wamid.9" });
  const fechada = await enviar({ phone_number_id: "555", token: "t".repeat(30) }, "5511999990001", { tipo: "texto", corpo: "oi" },
    (async () => new Response(JSON.stringify({ error: { code: 131047, message: "Re-engagement message" } }), { status: 400 })) as typeof fetch);
  assert.equal(fechada.ok, false);
  assert.equal(fechada.ok === false && fechada.janelaFechada, true);
  const rede = await enviar({ phone_number_id: "555", token: "t".repeat(30) }, "5511", { tipo: "texto", corpo: "oi" }, (async () => { throw new Error("boom"); }) as typeof fetch);
  assert.equal(rede.ok, false);
});

test("envio: o token só vai no cabeçalho, nunca na URL", async () => {
  let url = "", auth = "";
  await enviar({ phone_number_id: "555", token: "SEGREDO".repeat(5) }, "5511", { tipo: "texto", corpo: "oi" },
    (async (u: string, i: RequestInit) => { url = u; auth = String((i.headers as any).Authorization); return new Response("{}", { status: 400 }); }) as unknown as typeof fetch);
  assert.ok(!url.includes("SEGREDO"));
  assert.ok(auth.startsWith("Bearer SEGREDO"));
});

test("validarConta: aceita só quando a Meta confirma o número com aquele token", async () => {
  const { validarConta } = await import("./meta.ts");
  let chamada: { url: string; auth: string } | null = null;
  const ok = (async (u: string, i: RequestInit) => { chamada = { url: u, auth: String((i.headers as any).Authorization) }; return new Response(JSON.stringify({ id: "12345678" })); }) as any;
  assert.deepEqual(await validarConta({ phone_number_id: "12345678", token: "t".repeat(30) }, ok), { ok: true });
  assert.match(chamada!.url, /graph\.facebook\.com\/v[\d.]+\/12345678\?/);
  assert.equal(chamada!.auth, `Bearer ${"t".repeat(30)}`);

  const negado = (async () => new Response(JSON.stringify({ error: { code: 190 } }), { status: 400 })) as any;
  assert.equal((await validarConta({ phone_number_id: "12345678", token: "x".repeat(30) }, negado)).ok, false);
  const outroNumero = (async () => new Response(JSON.stringify({ id: "99999999" }))) as any;
  assert.equal((await validarConta({ phone_number_id: "12345678", token: "x".repeat(30) }, outroNumero)).ok, false, "id diferente não vale");
  const caiu = (async () => { throw new Error("rede"); }) as any;
  assert.equal((await validarConta({ phone_number_id: "12345678", token: "x".repeat(30) }, caiu)).ok, false);
});

test("modo simulado só liga fora de produção", async () => {
  const { simulando } = await import("./meta.ts");
  assert.equal(simulando({ WHATSAPP_SIMULAR: "1", NODE_ENV: "development" }), true);
  assert.equal(simulando({ WHATSAPP_SIMULAR: "1", NODE_ENV: "production" }), false, "nunca em produção");
  assert.equal(simulando({ NODE_ENV: "development" }), false);
});
