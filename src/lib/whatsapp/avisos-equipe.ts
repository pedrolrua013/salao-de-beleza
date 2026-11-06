// Avisos para o profissional: horário novo, remarcado ou cancelado na agenda dele, pelo WhatsApp do salão.
// O banco decide quem recebe (avisar_equipe); aqui montamos a mensagem e registramos o envio.
import type { SupabaseClient } from "@supabase/supabase-js";
import { enviarModelo, type ContaMeta } from "./meta.ts";

export const MODELO_EQUIPE = {
  nome: "belezando_equipe",
  categoria: "Utilidade",
  corpo: "{{1}}, {{2}} na sua agenda: {{3}}, {{4}}.",
};

export type AvisoEquipe = { id: string; salao_id: string; tipo: "novo" | "mudou" | "cancelou"; wa_id: string; membro_nome: string; fuso: string;
  dados: { cliente?: string; servico?: string; inicio?: string; inicio_antigo?: string } };

const quando = (iso: string, tz: string) => new Intl.DateTimeFormat("pt-BR", { timeZone: tz, weekday: "short", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
  .format(new Date(iso)).replace(",", "").replace(/,? (\d{2}:\d{2})$/, " às $1");

export function parametrosEquipe(a: AvisoEquipe): string[] {
  const o = { novo: "horário novo", mudou: "horário remarcado", cancelou: "horário cancelado" }[a.tipo];
  const em = a.dados.inicio ? quando(a.dados.inicio, a.fuso) : "";
  const detalhe = a.tipo === "mudou" && a.dados.inicio_antigo ? `${a.dados.servico ?? "serviço"}, de ${quando(a.dados.inicio_antigo, a.fuso)} para ${em}` : `${a.dados.servico ?? "serviço"}, ${em}`;
  return [a.membro_nome.trim().split(/\s+/)[0] || "Oi", o, a.dados.cliente ?? "cliente", detalhe];
}

export async function executarAvisosEquipe(db: SupabaseClient, f: typeof fetch = fetch, limite = 30) {
  const { data, error } = await db.rpc("reservar_avisos_equipe", { p_limite: limite });
  if (error) throw new Error(`reservar_avisos_equipe: ${error.message}`);
  const lista = (data ?? []) as AvisoEquipe[];
  const contas = new Map<string, ContaMeta | null>();
  let enviados = 0, falhas = 0;
  for (const a of lista) {
    try {
      if (!contas.has(a.salao_id)) {
        const { data: c } = await db.from("whatsapp_contas").select("phone_number_id, token").eq("salao_id", a.salao_id).maybeSingle();
        contas.set(a.salao_id, c ? { phone_number_id: c.phone_number_id, token: c.token } : null);
      }
      const conta = contas.get(a.salao_id);
      if (!conta) { await db.rpc("concluir_aviso_equipe", { p_id: a.id, p_ok: false, p_wa_msg_id: null, p_erro: "WhatsApp não conectado neste salão" }); falhas++; continue; }
      const r = await enviarModelo(conta, a.wa_id, { nome: MODELO_EQUIPE.nome, parametros: parametrosEquipe(a), botoes: [] }, f);
      await db.rpc("concluir_aviso_equipe", { p_id: a.id, p_ok: r.ok, p_wa_msg_id: r.ok ? r.msgId : null, p_erro: r.ok ? null : r.erro });
      r.ok ? enviados++ : falhas++;
    } catch (e) {
      falhas++;
      console.error("[avisos-equipe] erro ao enviar", { aviso: a.id, erro: e instanceof Error ? e.message : String(e) });
      await db.rpc("concluir_aviso_equipe", { p_id: a.id, p_ok: false, p_wa_msg_id: null, p_erro: "erro interno ao enviar" });
    }
  }
  return { reservados: lista.length, enviados, falhas };
}
