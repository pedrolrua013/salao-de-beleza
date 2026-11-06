"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";

/** Marca como vistos os avisos de quem está logado (o banco só deixa mexer nos próprios). */
export async function marcarAvisosLidos() {
  const { supabase, user } = await exigirMembro();
  await supabase.from("avisos_equipe").update({ lido_em: new Date().toISOString() }).eq("membro_id", user.id).is("lido_em", null);
  revalidatePath("/hoje");
}
