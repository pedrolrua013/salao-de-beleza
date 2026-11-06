import { test } from "node:test";
import assert from "node:assert/strict";
import { conversar } from "./bot.ts";
import type { Contexto, EstadoBot, Saida } from "./tipos.ts";

const AGORA = new Date("2026-10-22T13:00:00Z"); // quinta 10:00 em São Paulo
const SRV = [{ id: "s1", nome: "Escova", duracao_min: 45 }, { id: "s2", nome: "Corte", duracao_min: 30 }];
const PROFS = [{ id: "p1", nome: "Ana" }, { id: "p2", nome: "Bruno" }];

function ctx(over: Partial<Contexto> = {}, log: any = {}): Contexto {
  return {
    agora: AGORA,
    salao: { nome: "Studio Bela", telefone: "1140028922", endereco: "Rua das Palmeiras, 120", mensagem: null, fuso: "America/Sao_Paulo" },
    cliente: { nome: null, consentiu: false },
    servicos: SRV, profissionais: PROFS,
    dias: async () => ["2026-10-23", "2026-10-26"],
    horarios: async (dia) => dia === "2026-10-23" ? [{ hora: "09:00", profissional: "p1" }, { hora: "10:30", profissional: "p2" }] : [],
    meusAgendamentos: async () => [],
    agendar: async (a) => { log.agendou = a; return log.resultado ?? "ok"; },
    cancelar: async (id) => { log.cancelou = id; return true; },
    remarcar: async (id, inicio, prof) => { log.remarcou = { id, inicio, prof }; return log.remarcar ?? "ok"; },
    ...over,
  };
}
const tapa = (id: string) => ({ texto: id, id });
const corpos = (s: Saida[]) => s.map((x) => x.corpo).join("\n");
async function passo(e: EstadoBot | null, entrada: { texto: string; id?: string }, c: Contexto) {
  const r = await conversar(e, entrada, c);
  return r;
}

test("cliente novo percorre o fluxo inteiro e agenda", async () => {
  const log: any = {};
  const c = ctx({}, log);
  let r = await passo(null, { texto: "oi" }, c);
  assert.equal(r.saidas[0].tipo, "botoes");
  r = await passo(r.estado, tapa("agendar"), c);
  assert.equal(r.estado.passo, "aceite");
  r = await passo(r.estado, tapa("sim"), c);
  assert.equal(r.estado.passo, "nome");
  r = await passo(r.estado, { texto: "Joana Lima" }, c);
  assert.equal(r.estado.passo, "servico");
  r = await passo(r.estado, tapa("srv:s1"), c);
  assert.equal(r.estado.passo, "profissional");
  r = await passo(r.estado, tapa("prof:qualquer"), c);
  assert.equal(r.estado.passo, "dia");
  r = await passo(r.estado, tapa("dia:2026-10-23"), c);
  assert.equal(r.estado.passo, "hora");
  r = await passo(r.estado, tapa("hora:10:30:p2"), c);
  assert.equal(r.estado.passo, "confirmar");
  assert.match(corpos(r.saidas), /Bruno/);
  r = await passo(r.estado, tapa("ok"), c);
  assert.match(corpos(r.saidas), /Horário marcado/);
  assert.equal(log.agendou.profissional, "p2");
  assert.equal(log.agendou.nome, "Joana Lima");
  assert.equal(log.agendou.aceite, true);
  assert.equal(log.agendou.inicio.toISOString(), "2026-10-23T13:30:00.000Z"); // 10:30 em São Paulo
});

test("cliente conhecido com aceite pula aceite e nome", async () => {
  const c = ctx({ cliente: { nome: "Marina Silva", consentiu: true } });
  const r = await passo(null, { texto: "quero marcar um horário" }, c);
  assert.equal(r.estado.passo, "servico");
});

test("não aceitar o termo encerra o fluxo sem agendar", async () => {
  const c = ctx();
  let r = await passo(null, tapa("agendar"), c);
  assert.equal(r.estado.passo, "aceite");
  r = await passo(r.estado, tapa("nao"), c);
  assert.equal(r.estado.passo, "inicio");
  assert.match(corpos(r.saidas), /Sem esse aceite/);
});

test("urgência e pedido de atendente passam para a equipe", async () => {
  const c = ctx();
  let r = await passo(null, { texto: "estou com dor forte e sangrando" }, c);
  assert.equal(r.humano, true);
  assert.match(corpos(r.saidas), /1140028922/);
  r = await passo(null, { texto: "quero falar com um atendente" }, c);
  assert.equal(r.humano, true);
});

test("três respostas que não fazem sentido chamam a equipe", async () => {
  const c = ctx({ cliente: { nome: "Marina Silva", consentiu: true } });
  let r = await passo(null, tapa("agendar"), c);
  assert.equal(r.estado.passo, "servico");
  r = await passo(r.estado, { texto: "blá" }, c);
  assert.ok(!r.humano);
  r = await passo(r.estado, { texto: "blá" }, c);
  r = await passo(r.estado, { texto: "blá" }, c);
  assert.equal(r.humano, true);
});

test("horário que acabou de ser ocupado volta para a escolha de horário", async () => {
  const log: any = { resultado: "indisponivel" };
  const c = ctx({ cliente: { nome: "Marina Silva", consentiu: true } }, log);
  const e: EstadoBot = { passo: "confirmar", em: AGORA.toISOString(), servico: "s1", profissional: "qualquer", dia: "2026-10-23", hora: "09:00", profHora: "p1", aceite: false };
  const r = await passo(e, tapa("ok"), c);
  assert.equal(r.estado.passo, "hora");
  assert.match(corpos(r.saidas), /acabou de ser ocupado/);
});

test("cancelar consulta pede confirmação antes", async () => {
  const log: any = {};
  const ags = [{ id: "a1", inicio: "2026-10-26T13:00:00Z", servico: "Escova", profissional: "Ana" }];
  const c = ctx({ meusAgendamentos: async () => ags, cliente: { nome: "Marina Silva", consentiu: true } }, log);
  let r = await passo(null, { texto: "meus horários" }, c);
  assert.equal(r.estado.passo, "meus");
  r = await passo(r.estado, tapa("cancelar"), c);
  r = await passo(r.estado, tapa("ag:a1"), c);
  assert.equal(r.estado.passo, "cancelar_confirma");
  assert.equal(log.cancelou, undefined);
  r = await passo(r.estado, tapa("sim"), c);
  assert.equal(log.cancelou, "a1");
  assert.match(corpos(r.saidas), /foi cancelado/);
});

test("não deixa cancelar consulta que não é do cliente", async () => {
  const c = ctx({ meusAgendamentos: async () => [{ id: "a1", inicio: "2026-10-26T13:00:00Z", servico: "x", profissional: "y" }] });
  const e: EstadoBot = { passo: "cancelar_lista", em: AGORA.toISOString() };
  const r = await passo(e, tapa("ag:de-outra-pessoa"), c);
  assert.equal(r.estado.passo, "cancelar_lista");
});

test("depois de 2 horas parado o fluxo recomeça", async () => {
  const c = ctx();
  const velho: EstadoBot = { passo: "hora", em: new Date(AGORA.getTime() - 3 * 3600_000).toISOString(), dia: "2026-10-23", servico: "s1", profissional: "qualquer" };
  const r = await passo(velho, { texto: "oi" }, c);
  assert.equal(r.estado.passo, "inicio");
});

test("palavra menu volta ao início em qualquer passo", async () => {
  const c = ctx();
  const e: EstadoBot = { passo: "dia", em: AGORA.toISOString(), servico: "s1", profissional: "qualquer" };
  const r = await passo(e, { texto: "Menu" }, c);
  assert.equal(r.estado.passo, "inicio");
});

test("sem horários nos próximos dias chama a equipe", async () => {
  const c = ctx({ dias: async () => [], cliente: { nome: "Marina Silva", consentiu: true }, profissionais: [PROFS[0]] });
  const e: EstadoBot = { passo: "servico", em: AGORA.toISOString() };
  const r = await passo(e, tapa("srv:s1"), c);
  assert.equal(r.humano, true);
});

test("respeita os limites de tamanho da Meta", async () => {
  const longos = Array.from({ length: 14 }, (_, i) => ({ id: `s${i}`, nome: "Procedimento com nome muito comprido número " + i, duracao_min: 30 }));
  const c = ctx({ servicos: longos, cliente: { nome: "Marina Silva", consentiu: true } });
  const r = await passo(null, tapa("agendar"), c);
  const lista = r.saidas[0];
  assert.equal(lista.tipo, "lista");
  if (lista.tipo === "lista") {
    assert.ok(lista.itens.length <= 10);
    assert.ok(lista.itens.every((i) => i.titulo.length <= 24));
  }
});

test("remarcação: a consulta antiga só é cancelada depois que a nova é confirmada", async () => {
  const { iniciarRemarcacao } = await import("./bot.ts");
  const log: any = {};
  const c = ctx({ cliente: { nome: "Marina Silva", consentiu: true } }, log);
  let r = await iniciarRemarcacao(c, { servico: "s1", profissional: "p1", agendamento: "ag-velho" });
  assert.equal(r.estado.passo, "dia");
  assert.equal(r.estado.remarcar, "ag-velho");
  assert.equal(log.cancelou, undefined);
  r = await passo(r.estado, tapa("dia:2026-10-23"), c);
  r = await passo(r.estado, tapa("hora:09:00:p1"), c);
  assert.equal(r.estado.passo, "confirmar");
  assert.equal(log.cancelou, undefined, "ainda não cancelou");
  r = await passo(r.estado, tapa("ok"), c);
  assert.equal(log.remarcou.id, "ag-velho", "move o atendimento numa operação só");
  assert.equal(log.agendou, undefined, "não cria um horário novo à parte");
  assert.equal(log.cancelou, undefined);
  assert.match(corpos(r.saidas), /remarcado/);
});

test("remarcação: se o novo horário falha, a consulta antiga continua", async () => {
  const { iniciarRemarcacao } = await import("./bot.ts");
  const log: any = { remarcar: "indisponivel" };
  const c = ctx({ cliente: { nome: "Marina Silva", consentiu: true } }, log);
  let r = await iniciarRemarcacao(c, { servico: "s1", profissional: "p1", agendamento: "ag-velho" });
  r = await passo(r.estado, tapa("dia:2026-10-23"), c);
  r = await passo(r.estado, tapa("hora:09:00:p1"), c);
  r = await passo(r.estado, tapa("ok"), c);
  assert.equal(log.cancelou, undefined);
  assert.equal(r.estado.passo, "hora");
});

test("remarcação de atendimento com vários serviços procura horário para todos juntos", async () => {
  const { iniciarRemarcacao } = await import("./bot.ts");
  const log: any = { pedidos: [] };
  const c = ctx({ cliente: { nome: "Marina Silva", consentiu: true },
    dias: async (s) => { log.pedidos.push(s); return ["2026-10-23"]; },
    horarios: async (_d, s) => { log.pedidos.push(s); return [{ hora: "09:00", profissional: "p1" }]; } }, log);
  let r = await iniciarRemarcacao(c, { servico: "s1", servicos: ["s1", "s2"], profissional: "p1", agendamento: "ag-velho" });
  r = await passo(r.estado, tapa("dia:2026-10-23"), c);
  r = await passo(r.estado, tapa("hora:09:00:p1"), c);
  assert.match(corpos(r.saidas), /Escova \+ Corte/);
  r = await passo(r.estado, tapa("ok"), c);
  assert.ok(log.pedidos.every((s: unknown) => Array.isArray(s) && s.length === 2), "dias e horários consideram os dois serviços");
  assert.equal(log.remarcou.id, "ag-velho");
});

test("remarcação sem horários livres chama a equipe", async () => {
  const { iniciarRemarcacao } = await import("./bot.ts");
  const c = ctx({ dias: async () => [] });
  const r = await iniciarRemarcacao(c, { servico: "s1", profissional: "p1", agendamento: "ag" });
  assert.equal(r.humano, true);
});

test("teto de consultas futuras: avisa e chama a equipe em vez de insistir", async () => {
  const c = ctx({ cliente: { nome: "Marina Silva", consentiu: true } }, { resultado: "limite" });
  let r = await passo(null, { texto: "oi" }, c);
  r = await passo(r.estado, tapa("agendar"), c);
  r = await passo(r.estado, tapa("srv:s1"), c);
  r = await passo(r.estado, tapa("prof:p1"), c);
  r = await passo(r.estado, tapa("dia:2026-10-23"), c);
  r = await passo(r.estado, tapa("hora:09:00:p1"), c);
  r = await passo(r.estado, tapa("ok"), c);
  assert.equal(r.humano, true);
  assert.match(corpos(r.saidas), /3 horários/);
});
