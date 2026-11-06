export const dynamic = "force-dynamic";

/** Verificação de saúde para o balanceador e o monitoramento. Não toca no banco: só diz que o servidor está de pé. */
export function GET() {
  return Response.json({ ok: true }, { headers: { "Cache-Control": "no-store" } });
}
