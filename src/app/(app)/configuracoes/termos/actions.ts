"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import type { Estado } from "@/components/acao-form";

/** Salva o texto: um modelo pronto vira o modelo do salão; um do salão é atualizado. */
export async function salvarModelo(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera os termos." };
  const id = String(f.get("id") ?? ""), tipo = String(f.get("tipo") ?? "outro");
  const titulo = String(f.get("titulo") ?? "").trim().slice(0, 80);
  const texto = String(f.get("texto") ?? "").replace(/\r\n/g, "\n").trim().slice(0, 8000);
  if (titulo.length < 3) return { erro: "Escreva o título." };
  if (texto.length < 20) return { erro: "O texto está curto demais." };
  if (!["quimica", "imagem", "outro"].includes(tipo)) return { erro: "Tipo inválido." };
  const { error } = /^[0-9a-f-]{36}$/.test(id)
    ? await supabase.from("termos_modelos").update({ titulo, texto, atualizado_em: new Date().toISOString() }).eq("id", id)
    : await supabase.from("termos_modelos").insert({ tipo, titulo, texto });
  if (error) return { erro: error.code === "23505" ? "Já existe um termo com esse título." : "Não foi possível salvar." };
  revalidatePath("/configuracoes/termos");
  return { ok: "Termo salvo. Os próximos links usam este texto; os já assinados continuam com o texto da época." };
}

export async function apagarModelo(f: FormData) {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return;
  await supabase.from("termos_modelos").delete().eq("id", String(f.get("id")));
  revalidatePath("/configuracoes/termos");
}
