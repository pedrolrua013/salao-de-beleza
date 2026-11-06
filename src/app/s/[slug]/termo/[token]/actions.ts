"use server";
import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { clienteAdmin } from "@/lib/supabase/admin";
import { ipDoCliente } from "@/lib/limite";
import { assinaturaValida, cpfValido } from "@/lib/termos";
import type { Estado } from "@/components/acao-form";

const texto = (f: FormData, k: string, max: number) => String(f.get(k) ?? "").trim().slice(0, max) || undefined;

export async function assinarTermo(_: Estado, f: FormData): Promise<Estado> {
  const db = clienteAdmin();
  const token = String(f.get("token") ?? "");
  if (!db || !/^[0-9a-f]{64}$/.test(token)) return { erro: "Link inválido." };
  const nome = String(f.get("nome") ?? "").trim().replace(/\s+/g, " ");
  if (nome.length < 3) return { erro: "Escreva seu nome completo." };
  const cpf = String(f.get("cpf") ?? "").replace(/\D/g, "");
  if (cpf && !cpfValido(cpf)) return { erro: "Esse CPF não parece certo. Confira ou deixe em branco." };
  if (f.get("concordo") !== "on") return { erro: "Marque que leu e concorda com o termo." };
  const assinatura = String(f.get("assinatura") ?? "");
  if (!assinaturaValida(assinatura)) return { erro: "Desenhe sua assinatura no quadro." };
  const respostas = {
    alergia: texto(f, "alergia", 3), alergia_qual: f.get("alergia") === "sim" ? texto(f, "alergia_qual", 200) : undefined,
    gestante: texto(f, "gestante", 3), teste: texto(f, "teste", 3),
  };
  const h = await headers();
  const { data } = await db.rpc("assinar_termo", {
    p_token: token, p_nome: nome, p_documento: cpf || null, p_respostas: Object.values(respostas).some(Boolean) ? respostas : null,
    p_assinatura: assinatura, p_ip: ipDoCliente(h) ?? "", p_aparelho: (h.get("user-agent") ?? "").slice(0, 300),
  });
  if (data === "assinado" || data === "ja_assinado") {
    revalidatePath(`/s/${String(f.get("slug") ?? "")}/termo/${token}`);
    return { ok: "Termo assinado. Obrigado!" };
  }
  return { erro: data === "expirado" ? "Este link expirou. Peça um novo ao salão." : "Não foi possível assinar. Tente de novo." };
}
