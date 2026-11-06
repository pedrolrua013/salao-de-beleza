"use server";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Estado } from "@/components/acao-form";

function slugify(s: string) {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40);
}

export async function criarSalao(_: Estado, f: FormData): Promise<Estado> {
  const nome = String(f.get("nome") ?? "").trim();
  const seu = String(f.get("seu_nome") ?? "").trim();
  if (nome.length < 2 || seu.length < 2) return { erro: "Preencha o nome do salão e o seu nome." };
  const slug = `${slugify(nome).slice(0, 30) || "salao"}-${Math.random().toString(36).slice(2, 7)}`;
  const supabase = await createClient();
  const { error } = await supabase.rpc("criar_salao", { p_nome: nome, p_slug: slug, p_nome_usuario: seu });
  if (error) {
    if (error.code === "23505" && error.message.includes("slug")) return { erro: "Tente de novo." };
    if (error.code === "23505") redirect("/hoje");
    return { erro: "Não foi possível criar o salão. Tente de novo." };
  }
  redirect("/guia");
}
