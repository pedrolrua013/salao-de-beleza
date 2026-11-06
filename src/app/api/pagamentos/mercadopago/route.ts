import { NextResponse } from "next/server";
import { clienteAdmin } from "@/lib/supabase/admin";
import { consultarPagamentoMP } from "@/lib/pagamentos/mercadopago";

export const dynamic = "force-dynamic";

/**
 * Aviso do Mercado Pago de que um pagamento mudou. O corpo não é confiável: o servidor consulta o pagamento
 * na API com o token do próprio salão e só confirma o sinal se estiver aprovado e com o valor certo.
 */
export async function POST(req: Request) {
  const url = new URL(req.url);
  const salao = url.searchParams.get("salao") ?? "";
  const corpo = await req.json().catch(() => ({}));
  const id = String(corpo?.data?.id ?? url.searchParams.get("data.id") ?? url.searchParams.get("id") ?? "");
  const tipo = String(corpo?.type ?? url.searchParams.get("type") ?? url.searchParams.get("topic") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(salao) || !id || (tipo && tipo !== "payment")) return NextResponse.json({ ok: true });
  if (!/^\d{1,20}$/.test(id)) return NextResponse.json({ ok: true });
  const db = clienteAdmin();
  if (!db) return new Response("Servidor sem chave de serviço", { status: 503 });
  // Só consulta o Mercado Pago se for um sinal nosso esperando pagamento: aviso falso não gasta a cota do salão na API.
  const { data: sinal } = await db.from("sinais").select("id").eq("salao_id", salao).eq("mp_payment_id", id).in("status", ["pendente", "expirado", "cancelado"]).maybeSingle();
  const { data: cobranca } = sinal ? { data: null } : await db.from("cobrancas").select("id").eq("salao_id", salao).eq("mp_payment_id", id).eq("status", "pendente").maybeSingle();
  if (!sinal && !cobranca) return NextResponse.json({ ok: true });
  const { data: conta } = await db.from("pagamentos_contas").select("mp_access_token").eq("salao_id", salao).maybeSingle();
  if (!conta?.mp_access_token) return NextResponse.json({ ok: true });
  const st = await consultarPagamentoMP(conta.mp_access_token, id);
  if (!st) return new Response("Falha ao consultar", { status: 502 }); // o Mercado Pago tenta de novo
  if (st.aprovado) {
    if (sinal) await db.rpc("sinal_pago_mp", { p_payment_id: id, p_valor_centavos: st.valorCentavos, p_salao: salao });
    else await db.rpc("cobranca_paga_mp", { p_payment_id: id, p_valor_centavos: st.valorCentavos, p_salao: salao });
  }
  return NextResponse.json({ ok: true });
}
