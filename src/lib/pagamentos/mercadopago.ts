// Pix dinâmico pelo Mercado Pago (opcional). Com ele, o sinal confirma sozinho quando a cliente paga.
// Implementado pela documentação pública (POST /v1/payments com payment_method_id "pix"); ainda não testado com conta real.

const API = "https://api.mercadopago.com";

export type PixMP = { id: string; copiaECola: string; qrBase64: string | null };

export async function criarPixMP(o: { token: string; valorCentavos: number; descricao: string; referencia: string; expiraEm: Date; email?: string; avisoUrl?: string }): Promise<PixMP> {
  const r = await fetch(`${API}/v1/payments`, {
    method: "POST",
    headers: { Authorization: `Bearer ${o.token}`, "Content-Type": "application/json", "X-Idempotency-Key": o.referencia },
    body: JSON.stringify({
      transaction_amount: o.valorCentavos / 100,
      payment_method_id: "pix",
      description: o.descricao.slice(0, 100),
      external_reference: o.referencia,
      date_of_expiration: o.expiraEm.toISOString().replace("Z", "-00:00"),
      payer: { email: o.email ?? "cliente@belezando.app" },
      ...(o.avisoUrl ? { notification_url: o.avisoUrl } : {}),
    }),
  });
  const j = await r.json().catch(() => ({}));
  const td = j?.point_of_interaction?.transaction_data;
  if (!r.ok || !j?.id || !td?.qr_code) throw new Error(`Mercado Pago ${r.status}: ${j?.message ?? "sem QR"}`);
  return { id: String(j.id), copiaECola: td.qr_code, qrBase64: td.qr_code_base64 ?? null };
}

export type StatusMP = { aprovado: boolean; valorCentavos: number };

/** O webhook só diz "o pagamento X mudou". A verdade vem desta consulta, feita com o token do próprio salão. */
export async function consultarPagamentoMP(token: string, id: string): Promise<StatusMP | null> {
  if (!/^\d{1,20}$/.test(id)) return null;
  const r = await fetch(`${API}/v1/payments/${id}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) return null;
  const j = await r.json().catch(() => null);
  if (!j) return null;
  return { aprovado: j.status === "approved", valorCentavos: Math.round(Number(j.transaction_amount ?? 0) * 100) };
}
