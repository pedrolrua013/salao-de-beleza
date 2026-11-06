"use server";
import { revalidatePath } from "next/cache";
import { clienteAdmin } from "@/lib/supabase/admin";
import type { Estado } from "@/components/acao-form";

export async function avaliar(_: Estado, f: FormData): Promise<Estado> {
  const db = clienteAdmin();
  const token = String(f.get("token") ?? ""), nota = Number(f.get("nota"));
  if (!db || !/^[0-9a-f]{64}$/.test(token)) return { erro: "Link inválido." };
  if (!Number.isInteger(nota) || nota < 0 || nota > 10) return { erro: "Escolha uma nota de 0 a 10." };
  const { data } = await db.rpc("responder_avaliacao", { p_token: token, p_nota: nota, p_comentario: String(f.get("comentario") ?? "").slice(0, 1000), p_publica: f.get("publica") === "on" });
  if (data === "respondida" || data === "ja_respondida") {
    revalidatePath(`/s/${String(f.get("slug") ?? "")}/avaliar/${token}`);
    return { ok: "Obrigado!" };
  }
  return { erro: data === "expirada" ? "Este link expirou." : "Não foi possível enviar." };
}
