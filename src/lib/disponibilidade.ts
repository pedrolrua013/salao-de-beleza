// Horários livres para quem marca de fora (robô do WhatsApp e link público). Só no servidor, com a chave de serviço.
// Respeita fases (encaixe na pausa), jornada, almoço, bloqueios, intervalo de limpeza, tamanho do cabelo,
// preço e tempo de cada profissional e as regras de antecedência do salão.
import type { SupabaseClient } from "@supabase/supabase-js";
import { dataLocal, horariosLivres, lerPeriodo, somarDias, type Intervalo } from "./slots.ts";
import { fasesValidas, type Fase } from "./fases.ts";
import { todasAsLinhas } from "./paginar.ts";

/** Quantos dias à frente o link e o robô mostram (no máximo; o salão pode deixar menos). */
export const DIAS_A_FRENTE = 21;

export type SalaoAgenda = { id: string; fuso: string; abre: string; fecha: string; dias_semana: number[]; antecedencia_min_horas?: number; antecedencia_max_dias?: number };
/** Um item escolhível: o serviço, ou o serviço num tamanho (id "servico~tamanho"). */
export type ServicoAgenda = { id: string; nome: string; duracao_min: number; preco_centavos: number; sinal_percentual: number; fases: Fase[]; servico: string; variacao: string | null; intervalo: number; complementos: string[] };
export type Horario = { hora: string; profissional: string };

/** "servico~tamanho" → ids separados (o banco recebe os dois). */
export function separarId(id: string): { servico: string; variacao: string | null } {
  const [servico, variacao] = id.split("~");
  return { servico, variacao: variacao || null };
}

type Variacao = { id: string; nome: string; preco_centavos: number; fases: Fase[]; ordem: number };

export async function criarDisponibilidade(db: SupabaseClient, salao: SalaoAgenda, agora: Date, opcoes: { soOnline?: boolean; ignorar?: string[] } = {}) {
  let qs = db.from("servicos").select("id, nome, duracao_min, preco_centavos, sinal_percentual, fases, intervalo_min, complementos, servico_variacoes(id, nome, preco_centavos, fases, ordem)").eq("salao_id", salao.id).eq("ativo", true);
  if (opcoes.soOnline) qs = qs.eq("online", true);
  const [{ data: servicos }, { data: profs }, { data: porProf }] = await Promise.all([
    qs.order("nome"),
    db.from("membros").select("user_id, nome, dias_semana, entrada, saida, almoco_inicio, almoco_fim").eq("salao_id", salao.id).eq("ativo", true).in("papel", ["admin", "profissional"]).order("nome"),
    db.from("servico_profissional").select("servico_id, profissional_id, preco_centavos, fases").eq("salao_id", salao.id),
  ]);
  const profissionais = (profs ?? []).map((p) => ({ id: p.user_id as string, nome: p.nome as string }));
  const jornada = new Map((profs ?? []).map((p) => [p.user_id as string, {
    dias: (p.dias_semana as number[] | null) ?? salao.dias_semana,
    abre: ((p.entrada as string | null) ?? salao.abre).slice(0, 5),
    fecha: ((p.saida as string | null) ?? salao.fecha).slice(0, 5),
    almoco: p.almoco_inicio ? { inicio: (p.almoco_inicio as string).slice(0, 5), fim: (p.almoco_fim as string).slice(0, 5) } : null,
  }]));
  const doProf = new Map((porProf ?? []).map((x) => [`${x.servico_id}|${x.profissional_id}`, { preco: x.preco_centavos as number | null, fases: fasesValidas(x.fases) ? (x.fases as Fase[]) : null }]));

  // Serviço com tamanhos vira um item por tamanho ("Escova (Longo)"); o serviço sozinho fica só para remarcar o que já existe.
  const todos: ServicoAgenda[] = [];
  const lista: ServicoAgenda[] = [];
  for (const s of servicos ?? []) {
    const base: ServicoAgenda = {
      id: s.id as string, servico: s.id as string, variacao: null, nome: s.nome as string, duracao_min: s.duracao_min as number,
      preco_centavos: (s.preco_centavos as number | undefined) ?? 0, sinal_percentual: (s.sinal_percentual as number | undefined) ?? 0,
      fases: fasesValidas(s.fases) ? (s.fases as Fase[]) : [{ tipo: "trabalho", min: s.duracao_min as number }],
      intervalo: (s.intervalo_min as number | undefined) ?? 0,
      complementos: (s.complementos as string[] | undefined) ?? [],
    };
    todos.push(base);
    const vars = ((s.servico_variacoes ?? []) as Variacao[]).filter((v) => fasesValidas(v.fases)).sort((a, b) => a.ordem - b.ordem);
    if (vars.length === 0) { lista.push(base); continue; }
    for (const v of vars) {
      const item = { ...base, id: `${base.id}~${v.id}`, variacao: v.id, nome: `${base.nome} (${v.nome})`, preco_centavos: v.preco_centavos, fases: v.fases, duracao_min: v.fases.reduce((t, e) => t + e.min, 0) };
      todos.push(item); lista.push(item);
    }
  }
  const porId = new Map(todos.map((s) => [s.id, s]));
  const hoje = dataLocal(agora, salao.fuso);
  const antecedenciaMin = (salao.antecedencia_min_horas ?? 1) * 60;
  const diasAFrente = Math.min(DIAS_A_FRENTE, salao.antecedencia_max_dias ?? DIAS_A_FRENTE);

  // Fases de trabalho e bloqueios dos próximos dias. As pausas das químicas não entram: dá para encaixar nelas.
  let ocupados: Map<string, Intervalo[]> | null = null;
  async function carregarOcupados() {
    if (ocupados) return ocupados;
    const janela = `[${agora.toISOString()},${new Date(agora.getTime() + (diasAFrente + 2) * 86_400_000).toISOString()})`;
    // Salão cheio passa de 1.000 ocupações em três semanas: busca todas, senão horário ocupado apareceria livre.
    const data = await todasAsLinhas<{ profissional_id: string; periodo: string; agendamento_id: string | null }>((de, ate) =>
      db.from("ocupacoes").select("profissional_id, periodo, agendamento_id").eq("salao_id", salao.id).overlaps("periodo", janela).order("id").range(de, ate));
    ocupados = new Map();
    for (const o of data) {
      if (o.agendamento_id && opcoes.ignorar?.includes(o.agendamento_id as string)) continue;
      const k = o.profissional_id as string, per = lerPeriodo(o.periodo as string);
      if (per) (ocupados.get(k) ?? ocupados.set(k, []).get(k)!).push(per);
    }
    return ocupados;
  }
  const alvo = (prof: string) => (prof === "qualquer" ? profissionais : profissionais.filter((p) => p.id === prof));

  /** Tempo de um item com um profissional: o tamanho vale primeiro, depois o tempo do profissional, depois o do serviço. */
  const fasesCom = (s: ServicoAgenda, prof: string) => (s.variacao ? s.fases : doProf.get(`${s.servico}|${prof}`)?.fases ?? s.fases);
  /** Preço de um item com um profissional (mesma ordem do banco). */
  function precoDe(id: string, prof: string): number {
    const s = porId.get(id);
    if (!s) return 0;
    return s.variacao ? s.preco_centavos : doProf.get(`${s.servico}|${prof}`)?.preco ?? s.preco_centavos;
  }

  /** Fases de um ou mais serviços em sequência pelo profissional, com o intervalo de limpeza depois de cada um. */
  const fasesDe = (servicos: string | string[], prof: string) => {
    const ids = Array.isArray(servicos) ? servicos : [servicos];
    const achados = ids.map((id) => porId.get(id));
    if (!ids.length || !achados.every(Boolean)) return null;
    return achados.flatMap((s) => [...fasesCom(s!, prof), ...(s!.intervalo ? [{ tipo: "trabalho", min: s!.intervalo } as Fase] : [])]);
  };

  /** Horários livres do dia; com "qualquer", cada horário vem com o primeiro profissional livre. Vários serviços = um depois do outro. */
  async function horarios(dia: string, servico: string | string[], prof: string): Promise<Horario[]> {
    if (dia > somarDias(hoje, diasAFrente)) return [];
    const oc = await carregarOcupados();
    const porHora = new Map<string, string>();
    for (const p of alvo(prof)) {
      const fases = fasesDe(servico, p.id);
      if (!fases) return [];
      const j = jornada.get(p.id)!;
      for (const hora of horariosLivres({ data: dia, tz: salao.fuso, abre: j.abre, fecha: j.fecha, diasSemana: j.dias, almoco: j.almoco, fases, ocupados: oc.get(p.id) ?? [], agora, antecedenciaMin })) {
        if (!porHora.has(hora)) porHora.set(hora, p.id);
      }
    }
    return [...porHora.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([hora, profissional]) => ({ hora, profissional }));
  }

  /** Próximos dias com pelo menos um horário livre. */
  async function dias(servico: string | string[], prof: string, max = 7): Promise<string[]> {
    const achados: string[] = [];
    for (let i = 0; i <= diasAFrente && achados.length < max; i++) {
      const d = somarDias(hoje, i);
      if ((await horarios(d, servico, prof)).length > 0) achados.push(d);
    }
    return achados;
  }

  return { servicos: lista, porId, profissionais, horarios, dias, precoDe };
}
