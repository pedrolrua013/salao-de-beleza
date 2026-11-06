#!/usr/bin/env node
// Simula a cliente escrevendo no WhatsApp: monta um webhook no formato da Meta, assina com o segredo do app e envia ao servidor local.
// Use junto com WHATSAPP_SIMULAR=1 (as respostas do robô aparecem em Conversas, sem sair para a Meta). Veja docs/TESTE-WHATSAPP.md.
//
//   node --env-file=.env.local scripts/simular-whatsapp.mjs --phone-id 123456 --de 5511999990001 --texto "oi"
//   node --env-file=.env.local scripts/simular-whatsapp.mjs --phone-id 123456 --de 5511999990001 --botao "lem:...:c" --titulo "Confirmo"
//   node --env-file=.env.local scripts/simular-whatsapp.mjs --phone-id 123456 --de 5511999990001 --lista "srv:..." --titulo "Escova"
import { createHmac, randomUUID } from "node:crypto";
import { parseArgs } from "node:util";

const { values: a } = parseArgs({
  options: {
    "phone-id": { type: "string" }, de: { type: "string" }, nome: { type: "string", default: "Cliente Teste" },
    texto: { type: "string" }, botao: { type: "string" }, lista: { type: "string" }, titulo: { type: "string", default: "" },
    url: { type: "string", default: "http://localhost:3000/api/whatsapp" },
  },
});

const segredo = process.env.META_APP_SECRET;
const falta = [!a["phone-id"] && "--phone-id", !a.de && "--de", !(a.texto || a.botao || a.lista) && "--texto, --botao ou --lista", !segredo && "META_APP_SECRET (use --env-file=.env.local)"].filter(Boolean);
if (falta.length) { console.error("Faltou:", falta.join(", ")); process.exit(1); }
if (!/^\d{10,15}$/.test(a.de)) { console.error("--de deve ter só dígitos, com DDI (ex.: 5511999990001)."); process.exit(1); }

const mensagem = a.botao
  ? { type: "interactive", interactive: { type: "button_reply", button_reply: { id: a.botao, title: a.titulo } } }
  : a.lista
    ? { type: "interactive", interactive: { type: "list_reply", list_reply: { id: a.lista, title: a.titulo } } }
    : { type: "text", text: { body: a.texto } };
const corpo = JSON.stringify({
  object: "whatsapp_business_account",
  entry: [{ id: "sim", changes: [{ field: "messages", value: {
    metadata: { phone_number_id: a["phone-id"], display_phone_number: "0" },
    contacts: [{ wa_id: a.de, profile: { name: a.nome } }],
    messages: [{ from: a.de, id: `wamid.sim.${randomUUID()}`, timestamp: String(Math.floor(Date.now() / 1000)), ...mensagem }],
  } }] }],
});
const assinatura = "sha256=" + createHmac("sha256", segredo).update(corpo, "utf8").digest("hex");

const r = await fetch(a.url, { method: "POST", headers: { "Content-Type": "application/json", "X-Hub-Signature-256": assinatura }, body: corpo });
console.log(r.status, await r.text());
console.log("Veja a resposta do robô em /conversas.");
process.exit(r.ok ? 0 : 1);
