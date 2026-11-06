import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Salao, Membro } from "@/lib/types";

/** Confere o login no servidor de autenticação e carrega membro e salão. Sem salão, manda para o cadastro dela. */
export async function exigirMembro() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/entrar");
  const { data } = await supabase
    .from("membros")
    .select("user_id, salao_id, papel, nome, permissoes, saloes(*)")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!data) redirect("/comecar");
  const { saloes, ...membro } = data as unknown as Membro & { saloes: Salao };
  return { supabase, user, membro: membro as Membro, salao: saloes };
}
