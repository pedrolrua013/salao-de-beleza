import { test } from "node:test";
import assert from "node:assert/strict";
import { executarLembretes, modeloDe, parametros, textoDoHistorico, type Reservado } from "./lembretes.ts";
import { montarModelo } from "./meta.ts";

const L: Reservado = {
  id: "11111111-1111-4111-8111-111111111111", salao_id: "cl1", agendamento_id: "ag1", tipo: "vespera", wa_id: "5511999990001",
  cliente_nome: "Marina Silva Souza", salao_nome: "Studio Bela", inicio: "2026-10-27T17:30:00Z", fuso: "America/Sao_Paulo", profissional: "Ana", servico: "Escova",
};

test("parâmetros: primeiro nome, salão, dia da semana, hora local e profissional", () => {
  const p = parametros(L);
  assert.equal(p[0], "Marina");
  assert.equal(p[1], "Studio Bela");
  assert.match(p[2], /^terça-feira 27\/10$/);
  assert.equal(p[3], "14:30");
  assert.equal(p[4], "Ana");
});

test("modelo: 5 variáveis e 3 botões que carregam o id do lembrete", () => {
  const m = montarModelo("5511999990001", modeloDe(L)) as any;
  assert.equal(m.type, "template");
  assert.equal(m.template.name, "belezando_lembrete_vespera");
  assert.equal(m.template.language.code, "pt_BR");
  assert.equal(m.template.components[0].parameters.length, 5);
  const botoes = m.template.components.filter((c: any) => c.type === "button");
  assert.deepEqual(botoes.map((b: any) => b.parameters[0].payload), [`lem:${L.id}:c`, `lem:${L.id}:r`, `lem:${L.id}:x`]);
});

test("histórico mostra o texto como o cliente recebeu", () => {
  const t = textoDoHistorico(L);
  assert.match(t, /Olá, Marina! Passando para lembrar do seu horário em Studio Bela/);
  assert.match(t, /\[Confirmo \| Preciso remarcar \| Cancelar horário\]$/);
  assert.ok(!t.includes("{{"));
});

function banco(reservados: Reservado[], conta: any = { phone_number_id: "555", token: "t".repeat(30) }) {
  const concluidos: any[] = [], mensagens: any[] = [];
  const cad: any = (dado: any) => new Proxy({}, { get: (_, k) => (k === "then" ? (r: any) => r({ data: dado, error: null }) : () => cad(dado)) });
  const db: any = {
    from: (t: string) => ({ select: () => cad(t === "whatsapp_contas" ? conta : null), insert: (p: any) => { mensagens.push(p); return cad(null); } }),
    rpc: async (n: string, a: any) => {
      if (n === "reservar_lembretes") return { data: reservados, error: null };
      if (n === "concluir_lembrete") { concluidos.push(a); return { data: null, error: null }; }
      if (n === "abrir_conversa") return { data: "conv1", error: null };
      return { data: null, error: null };
    },
  };
  return { db, concluidos, mensagens };
}
const resposta = (status: number, corpo: unknown): typeof fetch => (async () => new Response(JSON.stringify(corpo), { status })) as any;

test("envio ok: conclui o lembrete e registra na conversa", async () => {
  const { db, concluidos, mensagens } = banco([L]);
  const b = await executarLembretes(db, resposta(200, { messages: [{ id: "wamid.X" }] }));
  assert.deepEqual(b, { reservados: 1, enviados: 1, falhas: 0 });
  assert.equal(concluidos[0].p_ok, true);
  assert.equal(concluidos[0].p_wa_msg_id, "wamid.X");
  assert.equal(mensagens[0].tipo, "modelo");
  assert.equal(mensagens[0].conversa_id, "conv1");
});

test("falha temporária (rede/servidor): não é definitiva, será tentada de novo", async () => {
  const { db, concluidos } = banco([L]);
  const b = await executarLembretes(db, resposta(500, { error: { code: 2, message: "temporário" } }));
  assert.equal(b.falhas, 1);
  assert.equal(concluidos[0].p_ok, false);
  assert.equal(concluidos[0].p_definitivo, false);
});

test("modelo não aprovado (132001): falha definitiva, sem insistir", async () => {
  const { db, concluidos } = banco([L]);
  await executarLembretes(db, resposta(404, { error: { code: 132001, message: "Template name does not exist" } }));
  assert.equal(concluidos[0].p_definitivo, true);
  assert.match(concluidos[0].p_erro, /132001/);
});

test("salão sem WhatsApp conectado: encerra o lembrete, sem chamar a Meta", async () => {
  const { db, concluidos } = banco([L], null);
  let chamou = false;
  const b = await executarLembretes(db, (async () => { chamou = true; return new Response("{}"); }) as any);
  assert.equal(chamou, false);
  assert.equal(b.falhas, 1);
  assert.equal(concluidos[0].p_definitivo, true);
});

test("um lembrete com erro não impede os outros", async () => {
  const { db, concluidos } = banco([L, { ...L, id: "22222222-2222-4222-8222-222222222222" }]);
  let n = 0;
  const f = (async () => { n++; if (n === 1) throw new Error("rede caiu"); return new Response(JSON.stringify({ messages: [{ id: "wamid.2" }] })); }) as any;
  const b = await executarLembretes(db, f);
  assert.equal(b.enviados, 1);
  assert.equal(concluidos.length, 2);
});
