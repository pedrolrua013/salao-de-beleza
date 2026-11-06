// Limite de tentativas por pessoa (login, cadastro, agendamento online). Só no servidor.
import { isIP } from "node:net";
import { clienteAdmin } from "./supabase/admin.ts";

/**
 * Endereço de quem está acessando. Só confia no cabeçalho que a hospedagem escreve
 * (na Vercel, x-real-ip; atrás do Cloudflare, defina IP_CABECALHO=cf-connecting-ip). Os outros a pessoa pode inventar.
 */
export function ipDoCliente(h: Headers, env: Record<string, string | undefined> = process.env): string | null {
  const nome = env.IP_CABECALHO || "x-real-ip";
  const v = (h.get(nome) ?? (nome === "x-real-ip" ? h.get("x-forwarded-for")?.split(",").at(-1) : null) ?? "").trim();
  if (isIP(v)) return v;
  // Sem IP confiável, todos os visitantes cairiam no mesmo balde do limite: avisa no log para corrigir a hospedagem.
  if (env.NODE_ENV === "production" && !avisouSemIp) { avisouSemIp = true; console.error(`[limite] sem IP válido no cabeçalho ${nome}: confira IP_CABECALHO (atrás do Cloudflare use cf-connecting-ip)`); }
  return null;
}
let avisouSemIp = false;

/** Registra a tentativa e diz se ainda está dentro do limite. Sem a chave de serviço (desenvolvimento), não limita. */
export async function dentroDoLimite(chave: string, limite: number, janelaMin: number): Promise<boolean> {
  const db = clienteAdmin();
  if (!db) return true;
  const { data, error } = await db.rpc("registrar_tentativa", { p_chave: chave.slice(0, 200), p_limite: limite, p_janela_min: janelaMin });
  if (error) { console.error("[limite] falha ao registrar", error.message); return true; }
  return data === true;
}
