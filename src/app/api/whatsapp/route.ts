import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { clienteAdmin } from "@/lib/supabase/admin";
import { assinaturaValida, lerWebhook } from "@/lib/whatsapp/meta";
import { processarEntrada } from "@/lib/whatsapp/processar";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

/** A Meta chama este endereço uma vez, ao cadastrar o webhook, para provar que ele é seu. */
export async function GET(req: Request) {
  const q = new URL(req.url).searchParams;
  const token = process.env.WHATSAPP_VERIFY_TOKEN;
  const recebido = q.get("hub.verify_token") ?? "";
  const igual = !!token && recebido.length === token.length && timingSafeEqual(Buffer.from(recebido), Buffer.from(token));
  if (igual && q.get("hub.mode") === "subscribe") {
    return new Response(q.get("hub.challenge") ?? "", { status: 200 });
  }
  return new Response("Forbidden", { status: 403 });
}

export async function POST(req: Request) {
  const bruto = await req.text();
  if (!assinaturaValida(bruto, req.headers.get("x-hub-signature-256"), process.env.META_APP_SECRET)) {
    return new Response("Assinatura inválida", { status: 401 });
  }
  const db = clienteAdmin();
  if (!db) return new Response("Servidor sem chave de serviço", { status: 503 });

  let corpo: unknown;
  try { corpo = JSON.parse(bruto); } catch { return new Response("JSON inválido", { status: 400 }); }

  let falhas = 0;
  for (const ev of lerWebhook(corpo)) {
    try {
      const { data: conta } = await db.from("whatsapp_contas").select("salao_id, phone_number_id, token").eq("phone_number_id", ev.phoneNumberId).maybeSingle();
      if (!conta) continue; // número que não é de nenhum salão nosso
      const { data: salao } = await db.from("saloes").select("id, nome, slug, telefone, endereco, mensagem, fuso, abre, fecha, dias_semana, antecedencia_min_horas, antecedencia_max_dias, ia_ativa, ia_instrucoes").eq("id", conta.salao_id).single();
      if (!salao) continue;
      await processarEntrada(db, salao, { phone_number_id: conta.phone_number_id, token: conta.token }, ev);
    } catch (e) {
      // Uma mensagem com problema não trava as outras. Respondemos erro no fim para a Meta reenviar o lote:
      // o que já foi tratado é ignorado no reenvio, e o banco desiste de uma mensagem depois de 3 tentativas.
      falhas++;
      console.error("[whatsapp] erro ao processar", { msg: ev.msgId, erro: e instanceof Error ? e.message : String(e) });
    }
  }
  return NextResponse.json({ ok: falhas === 0 }, { status: falhas === 0 ? 200 : 500 });
}
