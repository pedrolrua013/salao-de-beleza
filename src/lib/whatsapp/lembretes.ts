// Lembretes de horário pelo WhatsApp. O banco decide QUANDO enviar (reservar_lembretes); aqui decidimos o QUE enviar e registramos o resultado.
// Os três textos abaixo são os que você cadastra na Meta (categoria "Utilidade") com exatamente estas variáveis e botões.
import type { SupabaseClient } from "@supabase/supabase-js";
import { enviarModelo, type ContaMeta, type Modelo } from "./meta.ts";

export type TipoLembrete = "confirmacao" | "vespera" | "mesmo_dia";

export const MODELOS_META: Record<TipoLembrete, { nome: string; corpo: string }> = {
  vespera: {
    nome: "belezando_lembrete_vespera",
    corpo: "Olá, {{1}}! Passando para lembrar do seu horário em {{2}} amanhã, {{3}}, às {{4}}, com {{5}}. Você confirma presença?",
  },
  mesmo_dia: {
    nome: "belezando_lembrete_mesmo_dia",
    corpo: "Olá, {{1}}! Seu horário em {{2}} é hoje, {{3}}, às {{4}}, com {{5}}. Ainda podemos contar com você?",
  },
  confirmacao: {
    nome: "belezando_confirmacao_horario",
    corpo: "Olá, {{1}}! Seu horário em {{2}} foi marcado para {{3}}, às {{4}}, com {{5}}. Você confirma?",
  },
};
/** Botões de resposta rápida, na ordem. Rodapé sugerido na Meta: "Para não receber lembretes, responda PARAR". */
export const BOTOES_META = ["Confirmo", "Preciso remarcar", "Cancelar horário"];

export type Reservado = {
  id: string; salao_id: string; agendamento_id: string; tipo: TipoLembrete; wa_id: string;
  cliente_nome: string; salao_nome: string; inicio: string; fuso: string; profissional: string; servico: string;
};

function formatar(inicio: string, fuso: string) {
  const d = new Date(inicio);
  const data = new Intl.DateTimeFormat("pt-BR", { timeZone: fuso, weekday: "long", day: "2-digit", month: "2-digit" }).format(d).replace(",", "");
  const hora = new Intl.DateTimeFormat("pt-BR", { timeZone: fuso, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d);
  return { data, hora };
}

export function parametros(l: Reservado): string[] {
  const { data, hora } = formatar(l.inicio, l.fuso);
  return [l.cliente_nome.trim().split(/\s+/)[0] || "cliente", l.salao_nome, data, hora, l.profissional];
}

export function modeloDe(l: Reservado): Modelo {
  return {
    nome: MODELOS_META[l.tipo].nome,
    parametros: parametros(l),
    botoes: ["c", "r", "x"].map((a) => `lem:${l.id}:${a}`),
  };
}

/** O texto como a pessoa recebe, para aparecer no histórico da conversa. */
export function textoDoHistorico(l: Reservado): string {
  const corpo = MODELOS_META[l.tipo].corpo.replace(/\{\{(\d)\}\}/g, (_, n) => parametros(l)[Number(n) - 1]);
  return `${corpo}\n[${BOTOES_META.join(" | ")}]`;
}

export type Balanco = { reservados: number; enviados: number; falhas: number };

/** Envia o que está na hora. Seguro para rodar a cada poucos minutos e até em paralelo: o banco entrega cada lembrete a uma execução só. */
export async function executarLembretes(db: SupabaseClient, f: typeof fetch = fetch, limite = 20): Promise<Balanco> {
  const { data, error } = await db.rpc("reservar_lembretes", { p_limite: limite });
  if (error) throw new Error(`reservar_lembretes: ${error.message}`);
  const lista = (data ?? []) as Reservado[];
  const contas = new Map<string, ContaMeta | null>();
  const balanco: Balanco = { reservados: lista.length, enviados: 0, falhas: 0 };

  for (const l of lista) {
    try {
      if (!contas.has(l.salao_id)) {
        const { data: c } = await db.from("whatsapp_contas").select("phone_number_id, token").eq("salao_id", l.salao_id).maybeSingle();
        contas.set(l.salao_id, c ? { phone_number_id: c.phone_number_id, token: c.token } : null);
      }
      const conta = contas.get(l.salao_id);
      if (!conta) {
        await db.rpc("concluir_lembrete", { p_id: l.id, p_ok: false, p_wa_msg_id: null, p_erro: "WhatsApp não conectado neste salão", p_definitivo: true });
        balanco.falhas++;
        continue;
      }
      const r = await enviarModelo(conta, l.wa_id, modeloDe(l), f);
      await db.rpc("concluir_lembrete", { p_id: l.id, p_ok: r.ok, p_wa_msg_id: r.ok ? r.msgId : null, p_erro: r.ok ? null : r.erro, p_definitivo: r.ok ? false : r.definitivo === true });
      r.ok ? balanco.enviados++ : balanco.falhas++;
      // O lembrete aparece na conversa, para a equipe ver o que o cliente recebeu.
      const { data: conversaId } = await db.rpc("abrir_conversa", { p_salao: l.salao_id, p_wa_id: l.wa_id, p_nome: l.cliente_nome });
      if (conversaId) {
        await db.from("mensagens").insert({
          salao_id: l.salao_id, conversa_id: conversaId, direcao: "saida", autor: "robo", tipo: "modelo",
          corpo: textoDoHistorico(l), wa_msg_id: r.ok ? r.msgId : null, erro: r.ok ? null : r.erro,
        });
      }
    } catch (e) {
      balanco.falhas++;
      console.error("[lembretes] erro ao enviar", { lembrete: l.id, erro: e instanceof Error ? e.message : String(e) });
      await db.rpc("concluir_lembrete", { p_id: l.id, p_ok: false, p_wa_msg_id: null, p_erro: "erro interno ao enviar", p_definitivo: false });
    }
  }
  return balanco;
}
