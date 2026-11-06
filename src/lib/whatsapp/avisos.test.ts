import { test } from "node:test";
import assert from "node:assert/strict";
import { executarAvisos, parametrosAviso, textoDoAviso, type AvisoReservado } from "./avisos.ts";

const base = { id: "v1", salao_id: "s1", wa_id: "5511900005555", cliente_nome: "Júlia Souza", salao_nome: "Studio Bela", slug: "studio-bela", fuso: "America/Sao_Paulo" };

test("convite de retorno com dias, serviço e link do serviço", () => {
  const a: AvisoReservado = { ...base, tipo: "retorno", dados: { servico: "Corte masculino", servico_id: "srv1", dias: 35 } };
  const p = parametrosAviso(a, "https://app.x", "Corte masculino");
  assert.deepEqual(p, ["Júlia", "35", "Corte masculino", "Studio Bela", "https://app.x/s/studio-bela?servico=srv1"]);
  assert.match(textoDoAviso(a, p), /Já faz 35 dias do seu Corte masculino em Studio Bela/);
});

test("campanha leva o texto numa linha e o link do salão", () => {
  const a: AvisoReservado = { ...base, tipo: "campanha", dados: { texto: "Semana da\nhidratação!", campanha_id: "c1" } };
  const p = parametrosAviso(a, "https://app.x", "");
  assert.deepEqual(p, ["Júlia", "Semana da hidratação!", "https://app.x/s/studio-bela"]);
  assert.match(textoDoAviso(a, p), /PARAR/);
});

test("pedido de avaliação leva ao link com o segredo", () => {
  const a: AvisoReservado = { ...base, tipo: "avaliacao", dados: { token: "abc123" } };
  assert.deepEqual(parametrosAviso(a, "https://app.x", ""), ["Júlia", "Studio Bela", "https://app.x/s/studio-bela/avaliar/abc123"]);
});

test("aviso de vaga leva direto ao dia e horário que abriu", () => {
  const a: AvisoReservado = { ...base, tipo: "vaga", dados: { servico_id: "srv1", profissional_id: "p1", inicio: "2026-11-17T18:00:00Z" } };
  const p = parametrosAviso(a, "https://app.x", "Escova");
  assert.equal(p[1], "Escova");
  assert.equal(p[4], "15:00");
  assert.equal(p[5], "https://app.x/s/studio-bela?servico=srv1&prof=p1&dia=2026-11-17&hora=15:00");
});

test("envia o modelo sem botões e registra o resultado", async () => {
  const rpcs: { nome: string; args: any }[] = [];
  const corpos: any[] = [];
  const db: any = {
    rpc: async (nome: string, args: any) => {
      rpcs.push({ nome, args });
      if (nome === "reservar_avisos") return { data: [{ ...base, tipo: "retorno", dados: { servico: "Corte", servico_id: "srv1", dias: 31 } }], error: null };
      if (nome === "abrir_conversa") return { data: "c1", error: null };
      return { data: null, error: null };
    },
    from: (t: string) => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: t === "whatsapp_contas" ? { phone_number_id: "555", token: "t".repeat(30) } : { nome: "Corte" } }) }) }),
      insert: async (x: any) => { corpos.push(x); return { error: null }; },
    }),
  };
  const f = (async (_u: string, i: RequestInit) => { corpos.push(JSON.parse(String(i.body))); return new Response(JSON.stringify({ messages: [{ id: "wamid.A" }] }), { status: 200 }); }) as typeof fetch;
  const b = await executarAvisos(db, "https://app.x", f);
  assert.deepEqual(b, { reservados: 1, enviados: 1, falhas: 0 });
  const envio = corpos[0];
  assert.equal(envio.template.name, "belezando_retorno");
  assert.equal(envio.template.components.length, 1, "só o corpo, sem botões");
  assert.ok(rpcs.some((r) => r.nome === "concluir_aviso" && r.args.p_ok === true && r.args.p_wa_msg_id === "wamid.A"));
  assert.match(corpos[1].corpo, /Já faz 31 dias/);
});
