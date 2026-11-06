// Promoções (iguais às do banco, função promocao_em) e o mapa de ocupação que mostra os horários mais vazios.
import { dataLocal, diaIso, horaLocal, minutos } from "./slots.ts";

export type Promocao = {
  id: string; nome: string; tipo: "horario" | "ultima_hora"; percentual: number; dias_semana: number[];
  hora_inicio: string | null; hora_fim: string | null; horas_antes: number | null; servico_ids: string[] | null; valida_ate: string | null; ativa: boolean;
};

export const DIAS_CURTOS = ["", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];

/** A maior promoção que vale para o serviço começando naquele instante (mesma regra do banco). */
export function promocaoPara(promos: Promocao[], servico: string, inicio: Date, tz: string, agora = new Date()): Promocao | null {
  const dia = dataLocal(inicio, tz), hora = horaLocal(inicio, tz), dow = diaIso(dia);
  const valem = promos.filter((p) =>
    p.ativa
    && (!p.valida_ate || dia <= p.valida_ate)
    && (!p.servico_ids || p.servico_ids.includes(servico))
    && p.dias_semana.includes(dow)
    && (!p.hora_inicio || hora >= p.hora_inicio.slice(0, 5))
    && (!p.hora_fim || hora < p.hora_fim.slice(0, 5))
    && (p.tipo === "horario" || (inicio > agora && inicio.getTime() <= agora.getTime() + (p.horas_antes ?? 0) * 3_600_000)));
  return valem.sort((a, b) => b.percentual - a.percentual)[0] ?? null;
}

export const comDesconto = (centavos: number, percentual: number) => centavos - Math.round(centavos * percentual / 100);

/** Frase curta para a cliente: "Terça e quinta, das 9h às 12h: 20% off". */
export function descreverPromocao(p: Promocao): string {
  if (p.tipo === "ultima_hora") return `${p.percentual}% off para horários nas próximas ${p.horas_antes} horas`;
  const dias = p.dias_semana.length === 7 ? "Todos os dias" : [...p.dias_semana].sort().map((d) => DIAS_CURTOS[d]).join(", ");
  const h = (x: string) => { const [hh, mm] = x.slice(0, 5).split(":"); return `${Number(hh)}h${mm === "00" ? "" : mm}`; };
  const faixa = p.hora_inicio && p.hora_fim ? `, das ${h(p.hora_inicio)} às ${h(p.hora_fim)}` : p.hora_inicio ? `, a partir das ${h(p.hora_inicio)}` : p.hora_fim ? `, até as ${h(p.hora_fim)}` : "";
  return `${dias}${faixa}: ${p.percentual}% off`;
}

export type Jornada = { dias: number[]; abre: string; fecha: string; almoco: { inicio: string; fim: string } | null };
export type Celula = { dia: number; hora: number; ocupacao: number | null };
export type Mapa = { horas: number[]; celulas: Celula[]; vazios: Celula[] };

/**
 * Ocupação de cada dia da semana e hora nas últimas semanas: minutos marcados ÷ minutos de profissional trabalhando.
 * Sem ninguém trabalhando naquela hora, a célula fica vazia (null). Os "vazios" são as horas abertas mais desocupadas.
 */
export function mapaOcupacao(ags: { inicio: string; fim: string; profissional_id: string }[], jornadas: Map<string, Jornada>, tz: string, semanas: number): Mapa {
  const cap = new Map<string, number>(), uso = new Map<string, number>();
  const k = (d: number, h: number) => `${d}|${h}`;
  let hMin = 24, hMax = 0;
  for (const j of jornadas.values()) {
    const ab = minutos(j.abre), fe = minutos(j.fecha);
    hMin = Math.min(hMin, Math.floor(ab / 60)); hMax = Math.max(hMax, Math.ceil(fe / 60));
    for (const d of j.dias) for (let m = ab; m < fe; m += 5) {
      if (j.almoco && m >= minutos(j.almoco.inicio) && m < minutos(j.almoco.fim)) continue;
      cap.set(k(d, Math.floor(m / 60)), (cap.get(k(d, Math.floor(m / 60))) ?? 0) + 5 * semanas);
    }
  }
  for (const a of ags) {
    if (!jornadas.has(a.profissional_id)) continue;
    for (let t = Date.parse(a.inicio); t < Date.parse(a.fim); t += 5 * 60_000) {
      const d = new Date(t), m = minutos(horaLocal(d, tz)), dow = diaIso(dataLocal(d, tz));
      const chave = k(dow, Math.floor(m / 60));
      if (cap.has(chave)) uso.set(chave, (uso.get(chave) ?? 0) + 5);
    }
  }
  const horas = hMin < hMax ? Array.from({ length: hMax - hMin }, (_, i) => hMin + i) : [];
  const celulas: Celula[] = [];
  for (const h of horas) for (let d = 1; d <= 7; d++) {
    const c = cap.get(k(d, h));
    celulas.push({ dia: d, hora: h, ocupacao: c ? Math.min(1, (uso.get(k(d, h)) ?? 0) / c) : null });
  }
  const vazios = celulas.filter((c) => c.ocupacao !== null && c.ocupacao < 0.4).sort((a, b) => a.ocupacao! - b.ocupacao!).slice(0, 4);
  return { horas, celulas, vazios };
}
