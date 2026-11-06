// Pix de uma cobrança (comanda pelo celular, vale ou pacote comprado pelo link). Só no servidor, com a chave de serviço.
// Com Mercado Pago ligado, o Pix é dinâmico e confirma sozinho; senão, Pix na chave do salão e a recepção confirma.
import type { SupabaseClient } from "@supabase/supabase-js";
import { pixCopiaECola } from "./pix.ts";
import { criarPixMP } from "./pagamentos/mercadopago.ts";

type Salao = { id: string; nome: string; pix_chave: string | null; pix_nome: string | null; pix_cidade: string | null };

export async function gerarPixCobranca(db: SupabaseClient, salao: Salao, c: { id: string; valor_centavos: number }, descricao: string): Promise<boolean> {
  const txid = `C${c.id.replace(/-/g, "").slice(0, 24)}`;
  const { data: conta } = await db.from("pagamentos_contas").select("mp_access_token").eq("salao_id", salao.id).maybeSingle();
  if (conta?.mp_access_token) {
    try {
      const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "");
      const pix = await criarPixMP({
        token: conta.mp_access_token, valorCentavos: c.valor_centavos, descricao, referencia: c.id,
        expiraEm: new Date(Date.now() + 2 * 86_400_000), avisoUrl: site ? `${site}/api/pagamentos/mercadopago?salao=${salao.id}` : undefined,
      });
      await db.rpc("registrar_pix_cobranca", { p_id: c.id, p_copia_cola: pix.copiaECola, p_mp_payment_id: pix.id, p_modo: "mercadopago" });
      return true;
    } catch (e) {
      console.error("[cobranca] Mercado Pago falhou, usando Pix da chave", e instanceof Error ? e.message : e);
    }
  }
  if (!salao.pix_chave) return false;
  const copia = pixCopiaECola({ chave: salao.pix_chave, nome: salao.pix_nome || salao.nome, cidade: salao.pix_cidade || "BRASIL", valorCentavos: c.valor_centavos, txid });
  await db.rpc("registrar_pix_cobranca", { p_id: c.id, p_copia_cola: copia, p_mp_payment_id: null, p_modo: "pix_manual" });
  return true;
}
