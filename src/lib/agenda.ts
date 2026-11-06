import type { SupabaseClient } from "@supabase/supabase-js";
import { diaIso, zonedToUtc, somarDias } from "@/lib/slots";
import type { Agendamento, Bloqueio, Salao } from "@/lib/types";

export type SituacaoLembrete = { texto: string; tom: "ok" | "wt" | "no" | "mu" };
export type LinhaAgenda = Agendamento & { cliente: string; telefone: string | null; servico: string; cor: string | null; vip: boolean; profissional: string; lembrete: SituacaoLembrete | null; sinal: { valor_centavos: number; status: string } | null };

type LembreteLinha = { agendamento_id: string; tipo: string; estado: string; resposta: string | null; enviar_em: string; inicio_ref: string };

/** Resume em uma frase o que aconteceu com os lembretes deste horário (só os do horário atual dele). */
export function situacaoLembrete(a: Pick<Agendamento, "inicio" | "status">, ls: LembreteLinha[], tz: string): SituacaoLembrete | null {
  const meus = ls.filter((l) => Date.parse(l.inicio_ref) === Date.parse(a.inicio));
  const resp = meus.find((l) => l.resposta);
  if (resp?.resposta === "confirmou") return { texto: "Confirmou pelo WhatsApp", tom: "ok" };
  if (resp?.resposta === "remarcar") return { texto: "Pediu para remarcar", tom: "wt" };
  if (resp?.resposta === "cancelou") return { texto: "Cancelou pelo WhatsApp", tom: "no" };
  if (a.status !== "agendado") return null;
  if (meus.some((l) => l.estado === "enviado")) return { texto: "Lembrete enviado, sem resposta", tom: "wt" };
  if (meus.some((l) => l.estado === "falhou")) return { texto: "Lembrete não entregue, ligue", tom: "no" };
  const prox = meus.filter((l) => l.estado === "pendente" || l.estado === "enviando").sort((x, y) => Date.parse(x.enviar_em) - Date.parse(y.enviar_em))[0];
  if (prox) {
    const quando = new Intl.DateTimeFormat("pt-BR", { timeZone: tz, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(prox.enviar_em)).replace(",", " às");
    return { texto: `Lembrete em ${quando}`, tom: "mu" };
  }
  return null;
}

/** Agendamentos de um dia (no fuso do salão), já com nomes de cliente, serviço e profissional. */
export async function carregarDia(supabase: SupabaseClient, salao: Salao, data: string): Promise<LinhaAgenda[]> {
  const de = zonedToUtc(data, "00:00", salao.fuso).toISOString();
  const ate = zonedToUtc(somarDias(data, 1), "00:00", salao.fuso).toISOString();
  const { data: ags } = await supabase
    .from("agendamentos").select("*").gte("inicio", de).lt("inicio", ate).order("inicio");
  const lista = (ags ?? []) as Agendamento[];
  if (lista.length === 0) return [];
  const ids = [...new Set(lista.map((a) => a.cliente_id))];
  const [{ data: pacs }, { data: srvs }, { data: mems }, { data: lems }, { data: sins }] = await Promise.all([
    supabase.from("clientes").select("id, nome, telefone, vip").in("id", ids),
    supabase.from("servicos").select("id, nome, cor, servico_variacoes(id, nome)"),
    supabase.from("membros").select("user_id, nome"),
    supabase.from("lembretes").select("agendamento_id, tipo, estado, resposta, enviar_em, inicio_ref").in("agendamento_id", lista.map((a) => a.id)),
    supabase.from("sinais").select("agendamento_id, valor_centavos, status").in("agendamento_id", lista.map((a) => a.id)),
  ]);
  const sinalDe = new Map((sins ?? []).map((x) => [x.agendamento_id as string, { valor_centavos: x.valor_centavos as number, status: x.status as string }]));
  const porAg = new Map<string, LembreteLinha[]>();
  for (const l of (lems ?? []) as LembreteLinha[]) (porAg.get(l.agendamento_id) ?? porAg.set(l.agendamento_id, []).get(l.agendamento_id)!).push(l);
  const p = new Map((pacs ?? []).map((x) => [x.id, x]));
  const s = new Map((srvs ?? []).map((x) => [x.id, x.nome as string]));
  const cor = new Map((srvs ?? []).map((x) => [x.id, (x.cor as string | null) ?? null]));
  const tam = new Map((srvs ?? []).flatMap((x) => ((x.servico_variacoes ?? []) as { id: string; nome: string }[]).map((v) => [v.id, v.nome] as const)));
  const m = new Map((mems ?? []).map((x) => [x.user_id, x.nome as string]));
  return lista.map((a) => ({
    ...a,
    cliente: p.get(a.cliente_id)?.nome ?? "Cliente",
    telefone: p.get(a.cliente_id)?.telefone ?? null,
    servico: `${s.get(a.servico_id) ?? "Serviço"}${a.variacao_id && tam.get(a.variacao_id) ? ` (${tam.get(a.variacao_id)})` : ""}`,
    cor: cor.get(a.servico_id) ?? null,
    vip: !!p.get(a.cliente_id)?.vip,
    profissional: m.get(a.profissional_id) ?? "Profissional",
    lembrete: situacaoLembrete(a, porAg.get(a.id) ?? [], salao.fuso),
    sinal: sinalDe.get(a.id) ?? null,
  }));
}

export type ProfDia = { id: string; nome: string; abre: string; fecha: string; trabalha: boolean; almoco: { inicio: string; fim: string } | null };

/** Profissionais ativos e a jornada de cada um no dia (vazio na jornada = segue o salão). */
export async function carregarProfissionais(supabase: SupabaseClient, salao: Salao, data: string): Promise<ProfDia[]> {
  const { data: ms } = await supabase.from("membros")
    .select("user_id, nome, dias_semana, entrada, saida, almoco_inicio, almoco_fim")
    .in("papel", ["admin", "profissional"]).eq("ativo", true).order("nome");
  const dia = diaIso(data);
  return (ms ?? []).map((m) => ({
    id: m.user_id as string, nome: m.nome as string,
    abre: ((m.entrada as string | null) ?? salao.abre).slice(0, 5),
    fecha: ((m.saida as string | null) ?? salao.fecha).slice(0, 5),
    trabalha: ((m.dias_semana as number[] | null) ?? salao.dias_semana).includes(dia),
    almoco: m.almoco_inicio ? { inicio: (m.almoco_inicio as string).slice(0, 5), fim: (m.almoco_fim as string).slice(0, 5) } : null,
  }));
}

/** Bloqueios que tocam o dia (no fuso do salão). */
export async function carregarBloqueios(supabase: SupabaseClient, salao: Salao, data: string): Promise<Bloqueio[]> {
  const de = zonedToUtc(data, "00:00", salao.fuso).toISOString();
  const ate = zonedToUtc(somarDias(data, 1), "00:00", salao.fuso).toISOString();
  const { data: bs } = await supabase.from("bloqueios").select("id, profissional_id, inicio, fim, motivo").lt("inicio", ate).gt("fim", de).order("inicio");
  return (bs ?? []) as Bloqueio[];
}
