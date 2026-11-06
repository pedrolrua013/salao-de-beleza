import { test } from "node:test";
import assert from "node:assert/strict";
import { processarEntrada } from "./processar.ts";

// Banco de mentira: guarda o que foi gravado e devolve dados fixos nas consultas.
function bancoFalso(opts: { botAtivo?: boolean; nova?: boolean; estado?: unknown; rpc?: Record<string, unknown> } = {}) {
  const gravado = { updates: [] as any[], mensagens: [] as any[], rpcs: [] as any[] };
  const dados: Record<string, any[]> = {
    servicos: [{ id: "s1", nome: "Escova", duracao_min: 45 }],
    membros: [{ user_id: "p1", nome: "Ana" }],
    ocupacoes: [],
  };
  const cadeia = (tabela: string, modo: "select" | "update" | "insert", payload?: any) => {
    const c: any = new Proxy({}, { get: (_, k) => {
      if (k === "then") return (res: any) => {
        if (modo === "update") gravado.updates.push({ tabela, payload });
        if (modo === "insert") gravado.mensagens.push(payload);
        res({ data: modo === "select" ? dados[tabela] ?? [] : null, error: null });
      };
      return () => c;
    } });
    return c;
  };
  const db: any = {
    from: (t: string) => ({ select: () => cadeia(t, "select"), update: (p: any) => cadeia(t, "update", p), insert: (p: any) => cadeia(t, "insert", p) }),
    rpc: async (nome: string, args: any) => {
      gravado.rpcs.push({ nome, args });
      if (opts.rpc && nome in opts.rpc) return { data: opts.rpc[nome], error: null };
      if (nome === "receber_mensagem") return { data: { conversa_id: "c1", nova: opts.nova ?? true, bot_ativo: opts.botAtivo ?? true, estado: opts.estado ?? null, cliente_nome: "Marina Silva", consentiu: true }, error: null };
      if (opts.rpc && nome in opts.rpc) return { data: opts.rpc[nome], error: null };
      return { data: [], error: null };
    },
  };
  return { db, gravado };
}
const SALAO = { id: "cl1", nome: "Studio Bela", telefone: null, endereco: null, mensagem: null, fuso: "America/Sao_Paulo", abre: "08:00:00", fecha: "18:00:00", dias_semana: [1, 2, 3, 4, 5] };
const CONTA = { phone_number_id: "555", token: "t".repeat(30) };
const ev = (texto: string, id?: string, extra = {}) => ({ phoneNumberId: "555", waId: "5511999990001", nome: "Marina", msgId: "w" + Math.random(), tipo: id ? "interativo" : "texto", texto, id, suportado: true, ...extra });

function interceptarEnvios() {
  const enviados: any[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (_u: string, i: RequestInit) => { enviados.push(JSON.parse(String(i.body))); return new Response(JSON.stringify({ messages: [{ id: "wamid." + enviados.length }] }), { status: 200 }); }) as typeof fetch;
  return { enviados, restaurar: () => { globalThis.fetch = original; } };
}
const AGORA = new Date("2026-10-22T13:00:00Z");

test("mensagem nova: responde com o menu, grava o estado e registra a resposta", async () => {
  const { db, gravado } = bancoFalso();
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("oi"), AGORA); } finally { f.restaurar(); }
  assert.equal(f.enviados.length, 1);
  assert.equal(f.enviados[0].to, "5511999990001");
  assert.equal(f.enviados[0].interactive.type, "button");
  assert.match(f.enviados[0].interactive.body.text, /Olá, Marina/);
  assert.equal(gravado.mensagens.length, 1);
  assert.equal(gravado.mensagens[0].autor, "robo");
  assert.equal(gravado.mensagens[0].wa_msg_id, "wamid.1");
  assert.ok(gravado.updates.some((u) => u.tabela === "conversas" && u.payload.estado.passo === "inicio"));
});

test("webhook repetido (já processado) não responde de novo", async () => {
  const { db } = bancoFalso({ nova: false });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("oi"), AGORA); } finally { f.restaurar(); }
  assert.equal(f.enviados.length, 0);
});

test("conversa assumida pela equipe: grava a mensagem mas o robô fica quieto", async () => {
  const { db } = bancoFalso({ botAtivo: false });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("oi"), AGORA); } finally { f.restaurar(); }
  assert.equal(f.enviados.length, 0);
});

test("áudio: avisa que só lê texto e passa a conversa para a equipe", async () => {
  const { db, gravado } = bancoFalso();
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("[áudio]", undefined, { tipo: "audio", suportado: false }), AGORA); } finally { f.restaurar(); }
  assert.match(f.enviados[0].text.body, /só consigo ler texto/);
  assert.ok(gravado.updates.some((u) => u.payload.bot_ativo === false));
});

test("pedido de atendente desliga o robô", async () => {
  const { db, gravado } = bancoFalso();
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Falar com o salão", "humano"), AGORA); } finally { f.restaurar(); }
  assert.ok(gravado.updates.some((u) => u.tabela === "conversas" && u.payload.bot_ativo === false));
});

test("escolher agendar para cliente conhecido pede o serviço", async () => {
  const { db } = bancoFalso();
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Agendar horário", "agendar"), AGORA); } finally { f.restaurar(); }
  assert.equal(f.enviados[0].interactive.type, "list");
  assert.equal(f.enviados[0].interactive.action.sections[0].rows[0].id, "srv:s1");
});

test("falha ao enviar fica registrada com o erro e interrompe o resto", async () => {
  const { db, gravado } = bancoFalso();
  const original = globalThis.fetch;
  globalThis.fetch = (async () => new Response(JSON.stringify({ error: { code: 131047, message: "janela" } }), { status: 400 })) as typeof fetch;
  try { await processarEntrada(db, SALAO, CONTA, ev("oi"), AGORA); } finally { globalThis.fetch = original; }
  assert.equal(gravado.mensagens.length, 1);
  assert.match(gravado.mensagens[0].erro, /131047/);
  assert.equal(gravado.mensagens[0].wa_msg_id, null);
});

const LEM = "11111111-1111-4111-8111-111111111111";
const INICIO = "2026-10-27T17:30:00Z";

test("lembrete: tocar em Confirmo confirma a consulta e agradece", async () => {
  const { db, gravado } = bancoFalso({ rpc: { responder_lembrete: { ok: true, acao: "confirmou", agendamento_id: "ag1", inicio: INICIO, status: "confirmado" } } });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Confirmo", `lem:${LEM}:c`), AGORA); } finally { f.restaurar(); }
  const chamada = gravado.rpcs.find((r) => r.nome === "responder_lembrete");
  assert.equal(chamada.args.p_resposta, "confirmou");
  assert.equal(chamada.args.p_lembrete, LEM);
  assert.equal(chamada.args.p_wa_id, "5511999990001");
  assert.match(f.enviados[0].text.body, /Horário confirmado.*14:30/s);
});

test("lembrete: confirmar funciona mesmo com a equipe no comando da conversa", async () => {
  const { db, gravado } = bancoFalso({ botAtivo: false, rpc: { responder_lembrete: { ok: true, acao: "confirmou", agendamento_id: "ag1", inicio: INICIO } } });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Confirmo", `lem:${LEM}:c`), AGORA); } finally { f.restaurar(); }
  assert.ok(gravado.rpcs.some((r) => r.nome === "responder_lembrete"));
  assert.equal(f.enviados.length, 1);
});

test("lembrete: Cancelar pede confirmação antes de cancelar", async () => {
  const { db, gravado } = bancoFalso();
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Cancelar horário", `lem:${LEM}:x`), AGORA); } finally { f.restaurar(); }
  assert.ok(!gravado.rpcs.some((r) => r.nome === "responder_lembrete"));
  assert.deepEqual(f.enviados[0].interactive.action.buttons.map((b: any) => b.reply.id), [`lem:${LEM}:xs`, `lem:${LEM}:m`]);
});

test("lembrete: 'Sim, cancelar' cancela; 'Não, manter' não mexe em nada", async () => {
  const a = bancoFalso({ rpc: { responder_lembrete: { ok: true, acao: "cancelou", agendamento_id: "ag1", inicio: INICIO } } });
  let f = interceptarEnvios();
  try { await processarEntrada(a.db, SALAO, CONTA, ev("Sim, cancelar", `lem:${LEM}:xs`), AGORA); } finally { f.restaurar(); }
  assert.equal(a.gravado.rpcs.find((r) => r.nome === "responder_lembrete").args.p_resposta, "cancelou");
  assert.match(f.enviados[0].text.body, /cancelado/);

  const b = bancoFalso();
  f = interceptarEnvios();
  try { await processarEntrada(b.db, SALAO, CONTA, ev("Não, manter", `lem:${LEM}:m`), AGORA); } finally { f.restaurar(); }
  assert.ok(!b.gravado.rpcs.some((r) => r.nome === "responder_lembrete"));
});

test("lembrete: Preciso remarcar abre a escolha de novo dia, sem cancelar a consulta", async () => {
  const { db, gravado } = bancoFalso({ rpc: { responder_lembrete: { ok: true, acao: "remarcar", agendamento_id: "ag1", inicio: INICIO, servico_id: "s1", profissional_id: "p1" } } });
  const f = interceptarEnvios();
  const relogio = new Date("2026-10-26T13:00:00Z");
  try { await processarEntrada(db, SALAO, CONTA, ev("Preciso remarcar", `lem:${LEM}:r`), relogio); } finally { f.restaurar(); }
  const estado = gravado.updates.find((u) => u.tabela === "conversas" && u.payload.estado)?.payload.estado;
  assert.equal(estado.passo, "dia");
  assert.equal(estado.remarcar, "ag1");
  assert.equal(estado.servico, "s1");
  assert.ok(!gravado.rpcs.some((r) => r.nome === "cancelar_whatsapp"), "não cancela antes de ter o novo horário");
});

test("lembrete: Preciso remarcar num atendimento com profissionais diferentes passa para a equipe", async () => {
  const { db, gravado } = bancoFalso({ rpc: {
    responder_lembrete: { ok: true, acao: "remarcar", agendamento_id: "ag1", inicio: INICIO, servico_id: "s1", profissional_id: "p1" },
    do_grupo: [{ id: "ag1", status: "agendado", servico_id: "s1", profissional_id: "p1", inicio: INICIO }, { id: "ag2", status: "agendado", servico_id: "s2", profissional_id: "p2", inicio: INICIO }],
  } });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Preciso remarcar", `lem:${LEM}:r`), new Date("2026-10-26T13:00:00Z")); } finally { f.restaurar(); }
  assert.ok(gravado.updates.some((u) => u.tabela === "conversas" && u.payload.bot_ativo === false), "a equipe assume a conversa");
  assert.ok(!gravado.updates.some((u) => u.tabela === "conversas" && u.payload.estado?.remarcar), "o robô não começa a remarcar um serviço só");
  assert.ok(gravado.mensagens.some((m) => /equipe vai falar/.test(m.corpo)));
});

test("lembrete: dois toques no mesmo botão não repetem a ação", async () => {
  const { db } = bancoFalso({ rpc: { responder_lembrete: { ok: true, repetida: true, acao: "confirmou", agendamento_id: "ag1", inicio: INICIO } } });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Confirmo", `lem:${LEM}:c`), AGORA); } finally { f.restaurar(); }
  assert.match(f.enviados[0].text.body, /Já tinha registrado/);
});

test("lembrete: consulta que mudou depois do envio recebe aviso claro", async () => {
  const { db } = bancoFalso({ rpc: { responder_lembrete: { ok: false, motivo: "consulta_mudou" } } });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("Confirmo", `lem:${LEM}:c`), AGORA); } finally { f.restaurar(); }
  assert.match(f.enviados[0].text.body, /alterado ou já passou/);
});

test("'confirmo' digitado confirma o último lembrete aberto; sem lembrete aberto cai no robô", async () => {
  const a = bancoFalso({ rpc: { lembrete_aberto: LEM, responder_lembrete: { ok: true, acao: "confirmou", agendamento_id: "ag1", inicio: INICIO } } });
  let f = interceptarEnvios();
  try { await processarEntrada(a.db, SALAO, CONTA, ev("Confirmo!"), AGORA); } finally { f.restaurar(); }
  assert.equal(a.gravado.rpcs.find((r) => r.nome === "responder_lembrete").args.p_lembrete, LEM);

  const b = bancoFalso({ rpc: { lembrete_aberto: null } });
  f = interceptarEnvios();
  try { await processarEntrada(b.db, SALAO, CONTA, ev("confirmo"), AGORA); } finally { f.restaurar(); }
  assert.ok(!b.gravado.rpcs.some((r) => r.nome === "responder_lembrete"));
  assert.equal(f.enviados[0].interactive.type, "button"); // menu do robô
});

test("PARAR registra a recusa e responde sem acionar o robô", async () => {
  const { db, gravado } = bancoFalso();
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("PARAR"), AGORA); } finally { f.restaurar(); }
  assert.ok(gravado.rpcs.some((r) => r.nome === "recusar_lembretes"));
  assert.match(f.enviados[0].text.body, /não vai mais receber lembretes/);
});

test("mensagem tratada é marcada como processada (senão a Meta reenvia e ela é reprocessada)", async () => {
  const { db, gravado } = bancoFalso();
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("oi"), AGORA); } finally { f.restaurar(); }
  const marca = gravado.updates.find((u) => u.tabela === "mensagens" && u.payload.processada_em);
  assert.ok(marca, "marcou processada_em");
});

test("erro no meio do processamento não marca como processada e sobe o erro (a Meta reenvia)", async () => {
  const { db, gravado } = bancoFalso();
  const original = db.rpc;
  db.rpc = async (n: string, a: any) => { if (n === "agendamentos_whatsapp") throw new Error("banco caiu"); return original(n, a); };
  const f = interceptarEnvios();
  try { await assert.rejects(processarEntrada(db, SALAO, CONTA, ev("meus horários"), AGORA)); } finally { f.restaurar(); }
  assert.ok(!gravado.updates.some((u) => u.tabela === "mensagens" && u.payload.processada_em));
});

test("excesso de mensagens: guarda, não responde e dá como tratada", async () => {
  const { db, gravado } = bancoFalso({ rpc: { receber_mensagem: { conversa_id: "c1", nova: true, bot_ativo: true, estado: null, cliente_nome: null, consentiu: false, limitado: true } } });
  const f = interceptarEnvios();
  try { await processarEntrada(db, SALAO, CONTA, ev("oi"), AGORA); } finally { f.restaurar(); }
  assert.equal(f.enviados.length, 0);
  assert.ok(gravado.updates.some((u) => u.tabela === "mensagens" && u.payload.processada_em));
});
