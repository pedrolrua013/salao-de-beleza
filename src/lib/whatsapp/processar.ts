// Liga o robô ao banco e à Meta. Só roda no servidor, com a chave de serviço.
import type { SupabaseClient } from "@supabase/supabase-js";
import { criarDisponibilidade, separarId } from "../disponibilidade.ts";
import Anthropic from "@anthropic-ai/sdk";
import { iaDisponivel, responderDuvida, sistemaIA } from "./ia.ts";
import { dentroDoLimite } from "../limite.ts";
import { conversar, iniciarRemarcacao } from "./bot.ts";
import { enviar, textoParaHistorico, type ContaMeta, type EventoEntrada } from "./meta.ts";
import type { Contexto, EstadoBot, Saida } from "./tipos.ts";

type Salao = { id: string; nome: string; telefone: string | null; endereco: string | null; mensagem: string | null; fuso: string; abre: string; fecha: string; dias_semana: number[]; antecedencia_min_horas?: number; antecedencia_max_dias?: number ; slug?: string; ia_ativa?: boolean; ia_instrucoes?: string | null };

async function montarContexto(db: SupabaseClient, salao: Salao, conversaId: string, cliente: Contexto["cliente"], agora: Date): Promise<Contexto> {
  const disp = await criarDisponibilidade(db, salao, agora);
  const { profissionais, horarios } = disp;
  const lista = disp.servicos.map((s) => ({ id: s.id, nome: s.nome, duracao_min: s.duracao_min }));

  const ia = salao.ia_ativa && iaDisponivel() ? async (pergunta: string) => {
    // Até 20 perguntas por conversa por dia: protege a conta do salão de abuso.
    if (!(await dentroDoLimite(`ia:${conversaId}`, 20, 24 * 60))) return null;
    const { data: promos } = await db.from("promocoes").select("nome, percentual").eq("salao_id", salao.id).eq("ativa", true);
    const h = (x: string) => x.slice(0, 5);
    const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "");
    const sistema = sistemaIA({
      nome: salao.nome, endereco: salao.endereco, telefone: salao.telefone,
      horario: `dias ${salao.dias_semana.map((d) => ["", "seg", "ter", "qua", "qui", "sex", "sáb", "dom"][d]).join(", ")}, das ${h(salao.abre)} às ${h(salao.fecha)}`,
      link: site && salao.slug ? `${site}/s/${salao.slug}` : null,
      servicos: disp.servicos.map((x) => ({ nome: x.nome, preco_centavos: x.preco_centavos, duracao_min: x.duracao_min })),
      promocoes: (promos ?? []).map((p) => `${p.nome} (${p.percentual}% off)`), instrucoes: salao.ia_instrucoes ?? null,
    });
    return responderDuvida(new Anthropic(), sistema, pergunta);
  } : undefined;

  return {
    ia,
    agora, salao: { nome: salao.nome, telefone: salao.telefone, endereco: salao.endereco, mensagem: salao.mensagem, fuso: salao.fuso },
    cliente, servicos: lista, profissionais,
    horarios,
    dias: (servico, prof) => disp.dias(servico, prof),
    async meusAgendamentos() {
      const { data } = await db.rpc("agendamentos_whatsapp", { p_salao: salao.id, p_conversa: conversaId });
      return (data ?? []).map((a: any) => ({ id: a.id, inicio: a.inicio, servico: a.servico, profissional: a.profissional }));
    },
    async agendar(a) {
      const { servico, variacao } = separarId(a.servico);
      const { error } = await db.rpc("agendar_whatsapp", { p_salao: salao.id, p_conversa: conversaId, p_servico: servico, p_variacao: variacao, p_profissional: a.profissional, p_inicio: a.inicio.toISOString(), p_nome: a.nome, p_consentiu: a.aceite });
      if (!error) return "ok";
      if (error.message?.includes("horario_indisponivel")) return "indisponivel";
      return error.message?.includes("limite_agendamentos") ? "limite" : "erro";
    },
    async remarcar(id, inicio, profissional) {
      const { data, error } = await db.rpc("remarcar_whatsapp", { p_salao: salao.id, p_conversa: conversaId, p_agendamento: id, p_inicio: inicio.toISOString(), p_profissional: profissional });
      if (error) return "erro";
      return data === "remarcado" ? "ok" : data === "horario_indisponivel" ? "indisponivel" : data === "varios_profissionais" ? "equipe" : "erro";
    },
    async cancelar(id) {
      const { data, error } = await db.rpc("cancelar_whatsapp", { p_salao: salao.id, p_conversa: conversaId, p_agendamento: id });
      return !error && data === true;
    },
  };
}

async function enviarERegistrar(db: SupabaseClient, conta: ContaMeta, salaoId: string, conversaId: string, waId: string, saida: Saida, autor: "robo" | "equipe") {
  const r = await enviar(conta, waId, saida);
  await db.from("mensagens").insert({
    salao_id: salaoId, conversa_id: conversaId, direcao: "saida", autor, tipo: saida.tipo,
    corpo: textoParaHistorico(saida), wa_msg_id: r.ok ? r.msgId : null, erro: r.ok ? null : r.erro,
  });
  if (!r.ok) console.error("[whatsapp] falha ao enviar", { conversa: conversaId, erro: r.erro });
  return r;
}
export { enviarERegistrar };

/** Trata uma mensagem recebida: grava, e (se o robô estiver ativo) responde. */
export async function processarEntrada(db: SupabaseClient, salao: Salao, conta: ContaMeta, ev: EventoEntrada, agora = new Date()) {
  const { data: rec, error } = await db.rpc("receber_mensagem", {
    p_salao: salao.id, p_wa_id: ev.waId, p_nome: ev.nome, p_wa_msg_id: ev.msgId, p_tipo: ev.tipo, p_corpo: ev.id ? `${ev.texto} (${ev.id.split(":")[0]})` : ev.texto,
  });
  if (error || !rec) throw new Error(`receber_mensagem: ${error?.message ?? "sem retorno"}`);
  if (!rec.nova) return; // reenvio da Meta de algo que já foi tratado
  await tratar(db, salao, conta, ev, rec, agora); // se falhar, o erro sobe e a Meta reenvia (a mensagem só vale como tratada depois daqui)
  await db.from("mensagens").update({ processada_em: new Date().toISOString() }).eq("salao_id", salao.id).eq("wa_msg_id", ev.msgId);
}

async function tratar(db: SupabaseClient, salao: Salao, conta: ContaMeta, ev: EventoEntrada, rec: any, agora: Date) {
  if (rec.limitado) return; // excesso de mensagens em pouco tempo: guarda, mas não responde

  const conversaId = rec.conversa_id as string;
  const mandar = (s: Saida) => enviarERegistrar(db, conta, salao.id, conversaId, ev.waId, s, "robo");

  // Resposta a um lembrete (botão ou "confirmo"/"parar"): vale mesmo se a equipe assumiu a conversa.
  if (ev.suportado && (await tratarLembrete(db, salao, ev, rec, mandar, agora))) return;
  if (!rec.bot_ativo) return; // a equipe assumiu a conversa

  if (!ev.suportado) {
    await db.from("conversas").update({ bot_ativo: false }).eq("id", conversaId);
    await mandar({ tipo: "texto", corpo: "Por aqui eu só consigo ler texto. Já avisei a equipe para ver a sua mensagem." });
    return;
  }

  const ctx = await montarContexto(db, salao, conversaId, { nome: rec.cliente_nome ?? null, consentiu: rec.consentiu === true }, agora);
  const r = await conversar((rec.estado ?? null) as EstadoBot | null, { texto: ev.texto, id: ev.id }, ctx);
  await db.from("conversas").update({ estado: r.estado, ...(r.humano ? { bot_ativo: false } : {}) }).eq("id", conversaId);
  for (const s of r.saidas) {
    const envio = await mandar(s);
    if (!envio.ok) break; // não adianta mandar o resto se o primeiro falhou
  }
}

const quando = (inicio: string, fuso: string) => {
  const d = new Date(inicio);
  const dia = new Intl.DateTimeFormat("pt-BR", { timeZone: fuso, weekday: "long", day: "2-digit", month: "2-digit" }).format(d).replace(",", "");
  const hora = new Intl.DateTimeFormat("pt-BR", { timeZone: fuso, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d);
  return `${dia.replace(/^./, (c) => c.toUpperCase())} às ${hora}`;
};
/** Serviços ativos do atendimento, na ordem. */
async function servicosDoAtendimento(db: SupabaseClient, agendamento: string) {
  const { data } = await db.rpc("do_grupo", { p_ag: agendamento });
  return ((data ?? []) as { status: string; servico_id: string; variacao_id: string | null; profissional_id: string; inicio: string }[])
    .filter((g) => g.status === "agendado" || g.status === "confirmado").sort((a, b) => a.inicio.localeCompare(b.inicio));
}
const ID_LEMBRETE = /^lem:([0-9a-f-]{36}):(c|r|x|xs|m)$/;

/** Trata respostas aos lembretes. Devolve true se a mensagem era sobre isso (e já foi respondida). */
async function tratarLembrete(db: SupabaseClient, salao: Salao, ev: EventoEntrada, rec: any, mandar: (s: Saida) => Promise<unknown>, agora: Date): Promise<boolean> {
  const texto = (corpo: string): Saida => ({ tipo: "texto", corpo });
  const conversaId = rec.conversa_id as string;
  const txt = ev.texto.trim();

  // "PARAR": nunca mais lembretes automáticos
  if (!ev.id && /^parar[.!]*$/i.test(txt)) {
    await db.rpc("recusar_lembretes", { p_salao: salao.id, p_wa_id: ev.waId });
    await mandar(texto("Tudo certo: você não vai mais receber lembretes automáticos. Seus horários continuam marcados. Se precisar de algo, é só escrever aqui."));
    return true;
  }

  let lembrete: string | null = null, acao: string | null = null;
  const m = ev.id ? ID_LEMBRETE.exec(ev.id) : null;
  if (m) { lembrete = m[1]; acao = m[2]; }
  else if (!ev.id && /^(confirmo|confirmado|confirmar|sim,? confirmo)[.! ]*$/i.test(txt)) {
    const { data } = await db.rpc("lembrete_aberto", { p_salao: salao.id, p_wa_id: ev.waId });
    if (typeof data === "string") { lembrete = data; acao = "c"; }
  }
  if (!lembrete || !acao) return false;

  if (acao === "x") {
    await mandar({ tipo: "botoes", corpo: "Tem certeza que quer cancelar o horário?", botoes: [{ id: `lem:${lembrete}:xs`, titulo: "Sim, cancelar" }, { id: `lem:${lembrete}:m`, titulo: "Não, manter" }] });
    return true;
  }
  if (acao === "m") { await mandar(texto("Combinado, mantive o seu horário. Até lá!")); return true; }

  const resposta = acao === "c" ? "confirmou" : acao === "xs" ? "cancelou" : "remarcar";
  const { data: r, error } = await db.rpc("responder_lembrete", { p_salao: salao.id, p_wa_id: ev.waId, p_lembrete: lembrete, p_resposta: resposta });
  if (error || !r) throw new Error(`responder_lembrete: ${error?.message ?? "sem retorno"}`);

  if (!r.ok) {
    const msg = r.motivo === "consulta_mudou"
      ? "Esse horário foi alterado ou já passou. Escreva *menu* para ver seus horários."
      : "Não consegui localizar esse horário. Escreva *menu* e a gente resolve por aqui.";
    await mandar(texto(msg));
    return true;
  }
  if (r.repetida) {
    await mandar(texto(r.acao === resposta ? "Já tinha registrado essa resposta. Obrigado!" : "Já registrei a sua resposta anterior. Se precisar mudar algo, escreva *menu*."));
    return true;
  }
  if (resposta === "confirmou") {
    await mandar(texto(`Horário confirmado! ✅\n${quando(r.inicio, salao.fuso)}\n\nAté lá!`));
  } else if (resposta === "cancelou") {
    await mandar(texto("Horário cancelado. Se quiser marcar outro horário, escreva *menu*."));
  } else {
    const grupo = rec.bot_ativo ? await servicosDoAtendimento(db, r.agendamento_id) : [];
    // Profissionais diferentes no mesmo atendimento: a equipe combina (o robô levaria tudo para um só).
    if (!rec.bot_ativo || new Set(grupo.map((g) => g.profissional_id)).size > 1) {
      await mandar(texto("Anotei! A equipe vai falar com você para remarcar."));
      if (rec.bot_ativo) await db.from("conversas").update({ bot_ativo: false }).eq("id", conversaId);
      return true;
    }
    const ctx = await montarContexto(db, salao, conversaId, { nome: rec.cliente_nome ?? null, consentiu: true }, agora);
    const ids = grupo.map((g) => (g.variacao_id ? `${g.servico_id}~${g.variacao_id}` : g.servico_id));
    const res = await iniciarRemarcacao(ctx, { servico: ids[0] ?? r.servico_id, servicos: ids, profissional: r.profissional_id, agendamento: r.agendamento_id });
    await db.from("conversas").update({ estado: res.estado, ...(res.humano ? { bot_ativo: false } : {}) }).eq("id", conversaId);
    for (const s of res.saidas) { const envio: any = await mandar(s); if (envio && envio.ok === false) break; }
  }
  return true;
}
