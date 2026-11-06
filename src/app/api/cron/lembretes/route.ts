import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { clienteAdmin } from "@/lib/supabase/admin";
import { executarLembretes } from "@/lib/whatsapp/lembretes";
import { executarAvisos } from "@/lib/whatsapp/avisos";
import { executarAvisosEquipe } from "@/lib/whatsapp/avisos-equipe";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function autorizado(req: Request) {
  const segredo = process.env.CRON_SECRET;
  const recebido = req.headers.get("authorization");
  if (!segredo || !recebido?.startsWith("Bearer ")) return false;
  const a = Buffer.from(recebido.slice(7)), b = Buffer.from(segredo);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Chamada a cada poucos minutos pelo agendador (agendador externo, com o cabeçalho Authorization: Bearer CRON_SECRET). */
export async function GET(req: Request) {
  if (!autorizado(req)) return new Response("Não autorizado", { status: 401 });
  const db = clienteAdmin();
  if (!db) return new Response("Servidor sem chave de serviço", { status: 503 });
  try {
    // Sinal de agendamento online não pago no prazo: cancela e libera o horário.
    const { data: sinaisExpirados } = await db.rpc("expirar_sinais");
    // Convites de retorno e avisos de vaga da lista de espera.
    const { data: retornosProgramados } = await db.rpc("programar_retornos");
    await db.rpc("limpar_tentativas");
    const { data: aniversarios } = await db.rpc("programar_aniversarios");
    // Sem o endereço do site o link iria quebrado para a cliente: os avisos esperam até ele ser configurado.
    const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "");
    if (!site) console.error("[avisos] NEXT_PUBLIC_SITE_URL não configurado: retorno, vaga e avaliação não foram enviados");
    // Campanhas entram na mesma fila: 60 por rodada.
    const avisos = site ? await executarAvisos(db, site, fetch, 60) : null;
    const avisosEquipe = await executarAvisosEquipe(db);
    return NextResponse.json({ ok: true, sinaisExpirados, retornosProgramados, aniversarios, avisos, avisosEquipe, ...(await executarLembretes(db)) });
  } catch (e) {
    console.error("[lembretes] falha na execução", e instanceof Error ? e.message : String(e));
    return NextResponse.json({ ok: false }, { status: 500 });
  }
}
