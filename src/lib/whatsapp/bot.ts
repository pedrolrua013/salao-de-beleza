// Robô de agendamento: máquina de estados sem IA, só menus e listas. Previsível, barata e fácil de testar.
// Não tem acesso ao banco: tudo o que precisa vem pelo Contexto.
import { zonedToUtc } from "../slots.ts";
import type { Contexto, Entrada, EstadoBot, Resultado, Saida } from "./tipos.ts";

const EXPIRA_MIN = 120;
const URGENCIA = /urg[eê]ncia|emerg[eê]ncia|dor forte|sangr|incha[cç]o|febre|n[aã]o aguento/i;
const HUMANO = /atendente|humano|pessoa|recep[cç][aã]o|falar com/i;

const corta = (s: string, n: number) => (s.length <= n ? s : s.slice(0, n - 1) + "…");

function fmtDia(data: string, tz: string) {
  const d = zonedToUtc(data, "12:00", tz);
  const s = new Intl.DateTimeFormat("pt-BR", { timeZone: tz, weekday: "short", day: "2-digit", month: "2-digit" }).format(d);
  return s.replace(".", "").replace(",", "");
}
function fmtQuando(inicio: string | Date, tz: string) {
  const d = typeof inicio === "string" ? new Date(inicio) : inicio;
  const dia = new Intl.DateTimeFormat("pt-BR", { timeZone: tz, weekday: "long", day: "2-digit", month: "2-digit" }).format(d);
  const hora = new Intl.DateTimeFormat("pt-BR", { timeZone: tz, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d);
  return `${dia} às ${hora}`;
}

const texto = (corpo: string): Saida => ({ tipo: "texto", corpo });
/** Os serviços do atendimento: vários (remarcação de atendimento em sequência) ou um só. */
const alvo = (e: EstadoBot) => (e.servicos?.length ? e.servicos : e.servico!);
const MENU_BOTOES = [
  { id: "agendar", titulo: "Agendar horário" },
  { id: "meus", titulo: "Meus horários" },
  { id: "humano", titulo: "Falar com o salão" },
];

const SAUDACAO = /^(oi+|ol[aá]|opa|bom dia|boa tarde|boa noite|e a[ií]|tudo bem\??)[\s!.,?]*$/i;

function menu(ctx: Contexto, abertura = true): Saida[] {
  const nome = ctx.cliente.nome?.split(" ")[0];
  const ola = abertura ? `Olá${nome ? `, ${nome}` : ""}! Aqui é o atendimento da ${ctx.salao.nome}.${ctx.salao.mensagem ? `\n${ctx.salao.mensagem}` : ""}\n\nComo posso ajudar?` : "Como posso ajudar?";
  return [{ tipo: "botoes", corpo: ola, botoes: MENU_BOTOES }];
}

/** Mostra o passo atual de novo (ou o primeiro passo depois de uma escolha). */
async function pergunta(e: EstadoBot, ctx: Contexto): Promise<Saida[]> {
  const tz = ctx.salao.fuso;
  switch (e.passo) {
    case "aceite":
      return [{ tipo: "botoes", corpo: `Para marcar, ${ctx.salao.nome} vai guardar seu nome e telefone para agendar seu horário e enviar lembretes por aqui. Se não quiser receber lembretes, é só escrever PARAR. Tudo bem?`, botoes: [{ id: "sim", titulo: "Aceito" }, { id: "nao", titulo: "Não aceito" }] }];
    case "nome":
      return [texto("Qual é o seu nome completo?")];
    case "servico":
      return [{ tipo: "lista", corpo: "Qual atendimento você quer marcar?", botao: "Ver opções", itens: ctx.servicos.slice(0, 10).map((s) => ({ id: `srv:${s.id}`, titulo: corta(s.nome, 24), descricao: `${s.duracao_min} min` })) }];
    case "profissional": {
      const itens = [{ id: "prof:qualquer", titulo: "Qualquer um", descricao: "O primeiro horário livre" }, ...ctx.profissionais.slice(0, 9).map((p) => ({ id: `prof:${p.id}`, titulo: corta(p.nome, 24), descricao: undefined as string | undefined }))];
      return [{ tipo: "lista", corpo: "Com quem você prefere?", botao: "Ver opções", itens }];
    }
    case "dia": {
      const dias = await ctx.dias(alvo(e), e.profissional!);
      return [{ tipo: "lista", corpo: "Qual dia fica melhor?", botao: "Ver dias", itens: dias.slice(0, 10).map((d) => ({ id: `dia:${d}`, titulo: fmtDia(d, tz) })) }];
    }
    case "hora": {
      const hs = await ctx.horarios(e.dia!, alvo(e), e.profissional!);
      if (hs.length === 0) return [texto("Esse dia lotou. Vamos escolher outro?"), ...(await pergunta({ ...e, passo: "dia" }, ctx))];
      const passo = Math.max(1, Math.ceil(hs.length / 10));
      const mostrados = hs.filter((_, i) => i % passo === 0).slice(0, 10);
      return [{ tipo: "lista", corpo: `Horários livres em ${fmtDia(e.dia!, tz)}:`, botao: "Ver horários", itens: mostrados.map((h) => ({ id: `hora:${h.hora}:${h.profissional}`, titulo: h.hora })) }];
    }
    case "confirmar": {
      const srv = (e.servicos?.length ? e.servicos : [e.servico]).map((id) => ctx.servicos.find((s) => s.id === id)?.nome ?? "Serviço").join(" + ");
      const prof = ctx.profissionais.find((p) => p.id === e.profHora)?.nome ?? "";
      const quando = fmtQuando(zonedToUtc(e.dia!, e.hora!, tz), tz);
      return [{ tipo: "botoes", corpo: `Confirma?\n\n${srv}${prof ? ` com ${prof}` : ""}\n${quando}`, botoes: [{ id: "ok", titulo: "Confirmar" }, { id: "outro", titulo: "Outro horário" }, { id: "menu", titulo: "Cancelar" }] }];
    }
    case "cancelar_lista": {
      const ags = await ctx.meusAgendamentos();
      return [{ tipo: "lista", corpo: "Qual horário você quer cancelar?", botao: "Ver horários", itens: ags.slice(0, 10).map((a) => ({ id: `ag:${a.id}`, titulo: corta(fmtQuando(a.inicio, tz).replace(/^./, (c) => c.toUpperCase()), 24), descricao: corta(a.servico, 72) })) }];
    }
    case "cancelar_confirma":
      return [{ tipo: "botoes", corpo: "Tem certeza que quer cancelar esse horário?", botoes: [{ id: "sim", titulo: "Sim, cancelar" }, { id: "nao", titulo: "Não, manter" }] }];
    default:
      return menu(ctx);
  }
}

function pular(e: EstadoBot, ctx: Contexto): EstadoBot {
  // Decide o primeiro passo que ainda falta para agendar.
  if (!ctx.cliente.consentiu && !e.aceite) return { ...e, passo: "aceite" };
  if (!ctx.cliente.nome && !e.nome) return { ...e, passo: "nome" };
  return { ...e, passo: "servico" };
}

export async function conversar(anterior: EstadoBot | null, entrada: Entrada, ctx: Contexto): Promise<Resultado> {
  const agora = ctx.agora.getTime();
  const fresco = anterior?.em && agora - Date.parse(anterior.em) < EXPIRA_MIN * 60_000;
  let e: EstadoBot = fresco && anterior ? { ...anterior } : { passo: "inicio" };
  e.em = ctx.agora.toISOString();
  const txt = entrada.texto.trim();
  const id = entrada.id ?? "";
  const tz = ctx.salao.fuso;
  const sai = (estado: EstadoBot, saidas: Saida[], humano = false): Resultado => ({ estado: { ...estado, em: ctx.agora.toISOString(), erros: humano ? 0 : estado.erros }, saidas, humano });
  const paraHumano = (aviso: string): Resultado => sai({ passo: "humano" }, [texto(aviso)], true);
  const telefoneSalao = ctx.salao.telefone ? ` Se for urgente, ligue para ${ctx.salao.telefone}.` : "";

  // Atalhos que valem em qualquer passo.
  const livre = !id;  // palavras-chave só valem para texto digitado, não para toque em botão ou lista
  if (livre && URGENCIA.test(txt)) return paraHumano(`Sinto muito por isso. Já avisei a equipe para falar com você o quanto antes.${telefoneSalao}`);
  if ((livre && HUMANO.test(txt)) || id === "humano") return paraHumano("Certo! Já chamei a equipe. Assim que alguém estiver disponível, responde aqui mesmo.");
  if ((livre && /^(menu|in[ií]cio|0)$/i.test(txt)) || id === "menu") return sai({ passo: "inicio" }, menu(ctx, false));

  const entendi = (novo: EstadoBot) => ({ ...novo, erros: 0 });
  const irDia = async (p: EstadoBot): Promise<Resultado> => {
    if ((await ctx.dias(alvo(p), p.profissional!)).length === 0) return paraHumano("No momento não encontrei horários livres nos próximos dias. Já chamei a equipe para te ajudar.");
    return sai(entendi(p), await pergunta(p, ctx));
  };
  const naoEntendi = async (): Promise<Resultado> => {
    const n = (e.erros ?? 0) + 1;
    if (n >= 3) return paraHumano("Não consegui te entender por aqui, então vou chamar a equipe para te ajudar.");
    return sai({ ...e, erros: n }, [texto("Não entendi essa resposta. Pode escolher uma das opções?"), ...(await pergunta(e, ctx))]);
  };

  switch (e.passo) {
    case "inicio":
    case "humano": {
      if (id === "meus" || (livre && /meus|minhas|marcad/i.test(txt))) {
        const ags = await ctx.meusAgendamentos();
        if (ags.length === 0) return sai({ passo: "inicio" }, [texto("Você não tem horários marcados."), ...menu(ctx, false)]);
        const linhas = ags.map((a) => `• ${fmtQuando(a.inicio, tz)} — ${a.servico} com ${a.profissional}`).join("\n");
        return sai({ passo: "meus" }, [{ tipo: "botoes", corpo: `Seus próximos horários:\n\n${linhas}`, botoes: [{ id: "cancelar", titulo: "Cancelar uma" }, { id: "menu", titulo: "Voltar ao menu" }] }]);
      }
      if (id === "agendar" || (livre && /agendar|marcar|consulta|hor[aá]rio/i.test(txt))) {
        if (ctx.servicos.length === 0) return paraHumano("Ainda não temos horários para marcar por aqui. Já chamei a equipe.");
        const p = pular(e, ctx);
        return sai(entendi(p), await pergunta(p, ctx));
      }
      // Pergunta em texto livre ("quanto custa a escova?", "tem estacionamento?"): a IA responde, se o salão ligou.
      if (livre && ctx.ia && txt.length >= 6 && !SAUDACAO.test(txt)) {
        const resposta = await ctx.ia(txt);
        if (resposta) return sai({ passo: "inicio" }, [texto(resposta), ...menu(ctx, false)]);
      }
      return sai({ passo: "inicio" }, menu(ctx));
    }
    case "meus": {
      if (id === "cancelar") {
        const ags = await ctx.meusAgendamentos();
        if (ags.length === 0) return sai({ passo: "inicio" }, menu(ctx, false));
        const p = { ...e, passo: "cancelar_lista" };
        return sai(entendi(p), await pergunta(p, ctx));
      }
      return naoEntendi();
    }
    case "cancelar_lista": {
      if (id.startsWith("ag:")) {
        const alvo = id.slice(3);
        if (!(await ctx.meusAgendamentos()).some((a) => a.id === alvo)) return naoEntendi();
        const p = { ...e, passo: "cancelar_confirma", cancelar: alvo };
        return sai(entendi(p), await pergunta(p, ctx));
      }
      return naoEntendi();
    }
    case "cancelar_confirma": {
      if (id === "sim" && e.cancelar) {
        const ok = await ctx.cancelar(e.cancelar);
        return sai({ passo: "inicio" }, [texto(ok ? "Pronto, seu horário foi cancelado. Se quiser, é só marcar outro." : "Não consegui cancelar esse horário. Vou chamar a equipe."), ...(ok ? menu(ctx, false) : [])], !ok);
      }
      if (id === "nao") return sai({ passo: "inicio" }, [texto("Tudo bem, mantive o horário."), ...menu(ctx, false)]);
      return naoEntendi();
    }
    case "aceite": {
      if (id === "sim" || /^(sim|aceito|ok|tudo bem)$/i.test(txt)) { const p = pular({ ...e, aceite: true }, ctx); return sai(entendi(p), await pergunta(p, ctx)); }
      if (id === "nao" || /^n[aã]o/i.test(txt)) return sai({ passo: "inicio" }, [texto("Sem problemas. Sem esse aceite não consigo marcar por aqui, mas a equipe pode te ajudar por telefone."), ...menu(ctx, false)]);
      return naoEntendi();
    }
    case "nome": {
      const nome = txt.replace(/\s+/g, " ");
      if (id || nome.length < 5 || !nome.includes(" ") || nome.length > 120 || /[0-9@]/.test(nome)) return sai({ ...e, erros: (e.erros ?? 0) + 1 }, [texto("Preciso do nome e sobrenome, por favor.")]);
      const p = { ...e, nome, passo: "servico" };
      return sai(entendi(p), await pergunta(p, ctx));
    }
    case "servico": {
      const srv = id.startsWith("srv:") ? ctx.servicos.find((s) => s.id === id.slice(4)) : undefined;
      if (!srv) return naoEntendi();
      const p: EstadoBot = { ...e, servico: srv.id, passo: ctx.profissionais.length > 1 ? "profissional" : "dia", profissional: ctx.profissionais.length === 1 ? ctx.profissionais[0].id : undefined };
      return p.passo === "dia" ? irDia(p) : sai(entendi(p), await pergunta(p, ctx));
    }
    case "profissional": {
      const alvo = id.startsWith("prof:") ? id.slice(5) : "";
      if (alvo !== "qualquer" && !ctx.profissionais.some((x) => x.id === alvo)) return naoEntendi();
      return irDia({ ...e, profissional: alvo, passo: "dia" });
    }
    case "dia": {
      const dia = id.startsWith("dia:") ? id.slice(4) : "";
      if (!/^\d{4}-\d{2}-\d{2}$/.test(dia) || !(await ctx.dias(alvo(e), e.profissional!)).includes(dia)) return naoEntendi();
      const p = { ...e, dia, passo: "hora" };
      return sai(entendi(p), await pergunta(p, ctx));
    }
    case "hora": {
      const m = /^hora:(\d{2}:\d{2}):(.+)$/.exec(id);
      if (!m) return naoEntendi();
      const livres = await ctx.horarios(e.dia!, alvo(e), e.profissional!);
      if (!livres.some((h) => h.hora === m[1] && h.profissional === m[2])) {
        return sai(entendi({ ...e }), [texto("Esse horário acabou de ser ocupado. Escolha outro:"), ...(await pergunta(e, ctx))]);
      }
      const p = { ...e, hora: m[1], profHora: m[2], passo: "confirmar" };
      return sai(entendi(p), await pergunta(p, ctx));
    }
    case "confirmar": {
      if (id === "outro") return irDia({ ...e, passo: "dia" });
      if (id !== "ok") return naoEntendi();
      const inicio = zonedToUtc(e.dia!, e.hora!, tz);
      const onde = ctx.salao.endereco ? `\n${ctx.salao.endereco}` : "";
      const pronto = (aviso: string) => sai({ passo: "inicio" }, [texto(`${aviso}\n${fmtQuando(inicio, tz).replace(/^./, (c) => c.toUpperCase())}${onde}\n\nSe precisar remarcar ou cancelar, é só escrever "menu".`)]);
      // Remarcação: o atendimento inteiro muda junto, e o horário antigo só sai se o novo couber.
      if (e.remarcar) {
        const m = await ctx.remarcar(e.remarcar, inicio, e.profHora!);
        if (m === "ok") return pronto("Horário remarcado! ✅");
        if (m === "indisponivel") { const p = { ...e, passo: "hora" }; return sai(entendi(p), [texto("Esse horário acabou de ser ocupado. Escolha outro:"), ...(await pergunta(p, ctx))]); }
        return paraHumano("Não consegui remarcar por aqui. Já chamei a equipe para ajustar com você; seu horário atual continua marcado.");
      }
      const r = await ctx.agendar({ servico: e.servico!, profissional: e.profHora!, inicio, nome: e.nome ?? ctx.cliente.nome, aceite: e.aceite === true });
      if (r === "ok") return pronto("Horário marcado! ✅");
      if (r === "indisponivel") {
        const p = { ...e, passo: "hora" };
        return sai(entendi(p), [texto("Esse horário acabou de ser ocupado. Escolha outro:"), ...(await pergunta(p, ctx))]);
      }
      if (r === "limite") return paraHumano("Você já tem 3 horários marcados, que é o máximo por aqui. Para marcar mais algum, já chamei a equipe.");
      return paraHumano("Não consegui concluir o agendamento. Vou chamar a equipe para finalizar com você.");
    }
    default:
      return sai({ passo: "inicio" }, menu(ctx));
  }
}

/** O cliente tocou em "Preciso remarcar" num lembrete: já sabemos serviço e profissional, só falta escolher o novo dia. */
export async function iniciarRemarcacao(ctx: Contexto, d: { servico: string; servicos?: string[]; profissional: string; agendamento: string }): Promise<Resultado> {
  const e: EstadoBot = { passo: "dia", em: ctx.agora.toISOString(), aceite: true, nome: ctx.cliente.nome ?? undefined, servico: d.servico, profissional: d.profissional, remarcar: d.agendamento,
    ...(d.servicos && d.servicos.length > 1 ? { servicos: d.servicos } : {}) };
  if ((await ctx.dias(alvo(e), d.profissional)).length === 0) {
    return { estado: { passo: "humano", em: e.em }, saidas: [texto("Anotei que você quer remarcar, mas não encontrei horários livres nos próximos dias. Já chamei a equipe para te ajudar.")], humano: true };
  }
  return { estado: e, saidas: [texto("Sem problema! Vamos escolher um novo horário. Seu horário atual só será cancelado depois que o novo horário estiver confirmado."), ...(await pergunta(e, ctx))] };
}
