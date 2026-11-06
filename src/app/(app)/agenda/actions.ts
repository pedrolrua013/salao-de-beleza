"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { carregarProfissionais } from "@/lib/agenda";
import { blocos, fasesValidas, type Fase } from "@/lib/fases";
import { horariosLivresDetalhe, lerPeriodo, somarDias, zonedToUtc, type HorarioLivre, type Intervalo } from "@/lib/slots";
import type { Estado } from "@/components/acao-form";
import type { Agendamento } from "@/lib/types";

const DATA = /^\d{4}-\d{2}-\d{2}$/;
const HORA = /^\d{2}:\d{2}$/;

type Linha = { servico: string; prof: string; variacao?: string; outroNome?: string; outroMin?: number; cliente?: string };
type Modo = "sequencia" | "grupo";
const OUTRO = "outro";
const UUID = /^[0-9a-f-]{36}$/;

/** Lê as linhas de serviço do formulário (até 3). Cada linha manda serviço, profissional, tamanho e, no grupo, a cliente. */
function lerLinhas(f: FormData): Linha[] {
  const ss = f.getAll("servico_id").map(String), ps = f.getAll("profissional_id").map(String);
  const vs = f.getAll("variacao_id").map(String), cs = f.getAll("cliente_linha").map(String);
  return ss.map((servico, k) => ({
    servico, prof: ps[k] ?? "", variacao: UUID.test(vs[k] ?? "") ? vs[k] : undefined, cliente: UUID.test(cs[k] ?? "") ? cs[k] : undefined,
    outroNome: String(f.get(`outro_nome_${k}`) ?? "").trim().slice(0, 120), outroMin: Number(f.get(`outro_min_${k}`) || 0),
  })).filter((l) => l.servico && l.prof).slice(0, 3);
}

/** Tempo de cada linha: tamanho > profissional > catálogo (no banco), ou o digitado no "Outro"; mais o intervalo de limpeza. */
async function tempoDasLinhas(supabase: Awaited<ReturnType<typeof exigirMembro>>["supabase"], linhas: Linha[]) {
  const ids = linhas.filter((l) => l.servico !== OUTRO).map((l) => l.servico);
  const { data: srvs } = ids.length ? await supabase.from("servicos").select("id, intervalo_min").in("id", ids) : { data: [] };
  const intervalo = new Map((srvs ?? []).map((x) => [x.id as string, (x.intervalo_min as number) ?? 0]));
  return Promise.all(linhas.map(async (l) => {
    if (l.servico === OUTRO) return { fases: l.outroMin && l.outroMin >= 5 && l.outroMin <= 480 ? [{ tipo: "trabalho", min: l.outroMin }] as Fase[] : null, intervalo: 0 };
    const { data } = await supabase.rpc("fases_de", { p_servico: l.servico, p_prof: l.prof, p_variacao: l.variacao ?? null });
    return { fases: fasesValidas(data) ? (data as Fase[]) : null, intervalo: intervalo.get(l.servico) ?? 0 };
  }));
}
const minutosDe = (t: { fases: Fase[] | null; intervalo: number }) => (t.fases ?? []).reduce((s2, e) => s2 + e.min, 0) + t.intervalo;

/** Datas da repetição: toda semana, a cada 2 semanas ou todo mês (no mesmo dia; mês sem esse dia fica de fora). */
function datasDaSerie(data: string, repetir: string, vezes: number): string[] {
  if (!["7", "14", "mes"].includes(repetir) || vezes < 2) return [data];
  const out: string[] = [];
  for (let k = 0; k < vezes; k++) {
    if (repetir === "mes") {
      const [a, m, d] = data.split("-").map(Number);
      const alvo = new Date(Date.UTC(a, m - 1 + k, d));
      if (alvo.getUTCDate() === d) out.push(alvo.toISOString().slice(0, 10));
    } else out.push(somarDias(data, k * Number(repetir)));
  }
  return out;
}

export async function criarAgendamento(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao } = await exigirMembro();
  const data = String(f.get("data") ?? ""), hora = String(f.get("hora") ?? ""), cliente = String(f.get("cliente_id") ?? "");
  const modo: Modo = f.get("modo") === "grupo" ? "grupo" : "sequencia";
  const linhas = lerLinhas(f);
  if (!DATA.test(data) || !HORA.test(hora) || !cliente || linhas.length === 0) return { erro: "Preencha cliente, serviço, profissional, dia e horário." };
  if (linhas.some((l) => l.servico === OUTRO && (l.outroNome ?? "").length < 2)) return { erro: "Escreva qual é o serviço em \"Outro\"." };
  if (modo === "grupo" && linhas.slice(1).some((l) => !l.cliente)) return { erro: "No grupo, escolha a cliente de cada linha." };
  const tempos = await tempoDasLinhas(supabase, linhas);
  if (tempos.some((x) => !fasesValidas(x.fases))) return { erro: "Serviço não encontrado." };
  // "Outro": vira um serviço avulso (fora do catálogo e do link), para a agenda e a comanda mostrarem o nome certo.
  for (const l of linhas) {
    if (l.servico !== OUTRO) continue;
    const { data: id, error } = await supabase.rpc("servico_avulso", { p_nome: l.outroNome, p_min: l.outroMin });
    if (error || !id) return { erro: "Não foi possível usar esse serviço. Confira o nome e a duração." };
    l.servico = id as string;
  }
  const datas = datasDaSerie(data, String(f.get("repetir") ?? ""), Math.max(1, Math.min(12, Math.floor(Number(f.get("vezes")) || 1))));
  const serie = datas.length > 1 ? crypto.randomUUID() : null;
  const marcados: string[] = [], ocupados: string[] = [];
  for (const d of datas) {
    // Em sequência: um serviço depois do outro (mesma cliente). Em grupo: todos na mesma hora, cada um com a sua cliente.
    const grupo = modo === "sequencia" && linhas.length > 1 ? crypto.randomUUID() : null;
    let t = zonedToUtc(d, hora, salao.fuso).getTime();
    const novos = linhas.map((l, k) => {
      const linha = { cliente_id: modo === "grupo" && k > 0 ? l.cliente! : cliente, servico_id: l.servico, variacao_id: l.variacao ?? null, profissional_id: l.prof,
        inicio: new Date(t).toISOString(), grupo_id: grupo, serie_id: serie };
      if (modo === "sequencia") t += minutosDe(tempos[k]) * 60_000;
      return linha;
    });
    const { error } = await supabase.from("agendamentos").insert(novos);
    if (!error) marcados.push(d);
    else if (error.code === "23P01") ocupados.push(d);
    else if (error.message.includes("sem_permissao_agenda")) return { erro: "Você só pode marcar na sua própria agenda. Peça para a recepção ou o administrador." };
    else if (datas.length === 1) return { erro: "Não foi possível agendar. Confira os dados e tente de novo." };
    else ocupados.push(d);
  }
  revalidatePath("/agenda"); revalidatePath("/hoje");
  const dm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
  if (marcados.length === 0) {
    return { erro: datas.length > 1 ? "Nenhuma data ficou livre nesse horário." : "Algum profissional (ou recurso, como o lavatório) está ocupado em parte desse horário. Escolha um dos horários sugeridos." };
  }
  const extra = modo === "grupo" && linhas.length > 1 ? ` (${linhas.length} pessoas juntas)` : linhas.length > 1 ? ` (${linhas.length} serviços em sequência)` : "";
  if (datas.length > 1) return { ok: `${marcados.length} de ${datas.length} horários marcados${extra}.${ocupados.length ? ` Ficaram de fora (ocupado): ${ocupados.map(dm).join(", ")}.` : ""}` };
  return { ok: `Agendado para ${hora.replace(":", "h")}${extra}.` };
}

/** Arrastar na agenda: muda o horário e o profissional de um atendimento. */
export async function moverAgendamento(id: string, data: string, hora: string, prof: string): Promise<{ erro?: string }> {
  const { supabase, salao } = await exigirMembro();
  if (!UUID.test(id) || !UUID.test(prof) || !DATA.test(data) || !HORA.test(hora)) return { erro: "Dados inválidos." };
  const { data: ok, error } = await supabase.from("agendamentos").update({ inicio: zonedToUtc(data, hora, salao.fuso).toISOString(), profissional_id: prof })
    .eq("id", id).in("status", ["agendado", "confirmado", "em_atendimento"]).select("id");
  revalidatePath("/agenda"); revalidatePath("/hoje");
  if (error?.code === "23P01") return { erro: "Esse horário está ocupado (ou o recurso, como o lavatório, está em uso)." };
  if (error?.message.includes("sem_permissao_agenda")) return { erro: "Você só pode mexer na sua própria agenda." };
  if (error || !ok?.length) return { erro: "Não foi possível mover esse horário." };
  return {};
}

/** Cancela este horário e os próximos da mesma repetição. */
export async function cancelarSerie(f: FormData) {
  const { supabase } = await exigirMembro();
  const serie = String(f.get("serie_id") ?? ""), desde = String(f.get("desde") ?? "");
  if (!UUID.test(serie) || !desde) return;
  await supabase.from("agendamentos").update({ status: "cancelado" }).eq("serie_id", serie).gte("inicio", desde).in("status", ["agendado", "confirmado"]);
  revalidatePath("/agenda"); revalidatePath("/hoje");
}

/** Horários livres de um profissional num dia para umas fases, com os encaixes em pausas de química marcados. */
async function livresDoProf(supabase: Awaited<ReturnType<typeof exigirMembro>>["supabase"], salao: Awaited<ReturnType<typeof exigirMembro>>["salao"], prof: string, data: string, fases: Fase[], passo: number) {
  const de = zonedToUtc(data, "00:00", salao.fuso).toISOString(), ate = zonedToUtc(somarDias(data, 1), "00:00", salao.fuso).toISOString();
  const [profs, { data: ocs }, { data: ags }] = await Promise.all([
    carregarProfissionais(supabase, salao, data),
    supabase.from("ocupacoes").select("periodo").eq("profissional_id", prof).overlaps("periodo", `[${de},${ate})`),
    supabase.from("agendamentos").select("inicio, fases").eq("profissional_id", prof).gte("inicio", de).lt("inicio", ate).not("status", "in", "(cancelado,faltou)"),
  ]);
  const p = profs.find((x) => x.id === prof);
  if (!p) return [];
  const ocupados = (ocs ?? []).map((o) => lerPeriodo(o.periodo as string)).filter((x): x is Intervalo => !!x);
  const pausas = ((ags ?? []) as Pick<Agendamento, "inicio" | "fases">[]).flatMap((a) =>
    blocos(Date.parse(a.inicio), a.fases).filter((b) => b.tipo === "pausa").map((b) => ({ inicio: new Date(b.inicio).toISOString(), fim: new Date(b.fim).toISOString() })));
  return horariosLivresDetalhe({
    data, tz: salao.fuso, abre: p.abre, fecha: p.fecha, diasSemana: p.trabalha ? [1, 2, 3, 4, 5, 6, 7] : [],
    almoco: p.almoco, fases, ocupados, pausas, antecedenciaMin: 0, passoMin: passo,
  });
}

/** Horários em que todos os serviços cabem: em sequência (um depois do outro) ou em grupo (todos na mesma hora). */
export async function sugerirHorarios(linhas: Linha[], data: string, modo: Modo = "sequencia"): Promise<HorarioLivre[]> {
  const validas = linhas.filter((l) => l.servico && l.prof).slice(0, 3);
  if (validas.length === 0 || !DATA.test(data)) return [];
  const { supabase, salao } = await exigirMembro();
  const tempos = await tempoDasLinhas(supabase, validas);
  if (tempos.some((x) => !fasesValidas(x.fases))) return [];
  // O intervalo de limpeza entra como trabalho no fim (ninguém é marcado colado).
  const comIntervalo = tempos.map((t) => (t.intervalo ? [...(t.fases as Fase[]), { tipo: "trabalho", min: t.intervalo } as Fase] : (t.fases as Fase[])));
  if (validas.length === 1) return livresDoProf(supabase, salao, validas[0].prof, data, comIntervalo[0], 15);
  const min = (h: string) => Number(h.slice(0, 2)) * 60 + Number(h.slice(3, 5));
  const listas = await Promise.all(validas.map((l, k) => livresDoProf(supabase, salao, l.prof, data, comIntervalo[k], 5)));
  const conjuntos = listas.map((ls) => new Map(ls.map((h) => [min(h.hora), h.encaixe])));
  const deslocamentos: number[] = [];
  let acc = 0;
  for (const k of validas.keys()) { deslocamentos.push(modo === "grupo" ? 0 : acc); acc += minutosDe(tempos[k]); }
  return listas[0].filter((h) => min(h.hora) % 15 === 0)
    .filter((h) => deslocamentos.every((d, k) => conjuntos[k].has(min(h.hora) + d)))
    .map((h) => ({ hora: h.hora, encaixe: deslocamentos.some((d, k) => conjuntos[k].get(min(h.hora) + d)) }));
}

const PERMITIDOS = ["confirmado", "faltou", "cancelado", "agendado", "em_atendimento", "concluido"] as const;

export async function mudarStatus(f: FormData) {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? ""), status = String(f.get("status") ?? "");
  if (!id || !(PERMITIDOS as readonly string[]).includes(status)) return;
  await supabase.from("agendamentos").update({ status }).eq("id", id);
  revalidatePath("/agenda"); revalidatePath("/hoje");
}

export async function confirmarSinal(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.rpc("confirmar_sinal", { p_agendamento: String(f.get("id") ?? "") });
  revalidatePath("/agenda"); revalidatePath("/hoje");
}

export async function criarBloqueio(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao, membro } = await exigirMembro();
  const prof = membro.papel === "profissional" ? membro.user_id : String(f.get("profissional_id") ?? "");
  const d1 = String(f.get("de_data") ?? ""), h1 = String(f.get("de_hora") ?? ""), d2 = String(f.get("ate_data") ?? ""), h2 = String(f.get("ate_hora") ?? "");
  const motivo = String(f.get("motivo") ?? "").trim().slice(0, 120) || null;
  if (!prof || !DATA.test(d1) || !HORA.test(h1) || !DATA.test(d2) || !HORA.test(h2)) return { erro: "Preencha profissional, início e fim." };
  const inicio = zonedToUtc(d1, h1, salao.fuso), fim = zonedToUtc(d2, h2, salao.fuso);
  if (fim <= inicio) return { erro: "O fim precisa ser depois do início." };
  if (fim.getTime() - inicio.getTime() > 60 * 86_400_000) return { erro: "Um bloqueio pode ter no máximo 60 dias." };
  const { error } = await supabase.from("bloqueios").insert({ profissional_id: prof, inicio: inicio.toISOString(), fim: fim.toISOString(), motivo });
  if (error) {
    if (error.code === "23P01") return { erro: "Já há cliente marcado nesse período. Remarque ou cancele antes de bloquear." };
    return { erro: "Não foi possível bloquear. O profissional só bloqueia a própria agenda." };
  }
  revalidatePath("/agenda");
  return { ok: "Horário bloqueado." };
}

export async function removerBloqueio(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("bloqueios").delete().eq("id", String(f.get("id") ?? ""));
  revalidatePath("/agenda");
}

export async function entrarNaEspera(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const de = String(f.get("data_de") ?? ""), ate = String(f.get("data_ate") ?? "");
  const periodo = String(f.get("periodo") ?? "qualquer");
  if (!DATA.test(de) || !DATA.test(ate) || ate < de) return { erro: "Confira as datas." };
  const { error } = await supabase.from("lista_espera").insert({
    cliente_id: String(f.get("cliente_id") ?? ""), servico_id: String(f.get("servico_id") ?? ""),
    profissional_id: String(f.get("profissional_id") ?? "") || null, data_de: de, data_ate: ate,
    periodo: ["qualquer", "manha", "tarde", "noite"].includes(periodo) ? periodo : "qualquer",
  });
  if (error) return { erro: "Não foi possível colocar na lista (até 90 dias de espera)." };
  revalidatePath("/agenda");
  return { ok: "Na lista. Se vagar um horário que combina, a cliente é avisada pelo WhatsApp." };
}

export async function sairDaEspera(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("lista_espera").update({ estado: "cancelado" }).eq("id", String(f.get("id") ?? ""));
  revalidatePath("/agenda");
}
