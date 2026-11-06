"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { clienteAdmin } from "@/lib/supabase/admin";
import { validarConta } from "@/lib/whatsapp/meta";
import type { Estado } from "@/components/acao-form";

export async function salvarConexao(_: Estado, f: FormData): Promise<Estado> {
  const { membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador conecta o WhatsApp." };
  const db = clienteAdmin();
  if (!db) return { erro: "O servidor está sem a chave de serviço do Supabase (SUPABASE_SERVICE_ROLE_KEY)." };
  const phone = String(f.get("phone_number_id") ?? "").replace(/\s/g, "");
  const waba = String(f.get("waba_id") ?? "").replace(/\s/g, "");
  const token = String(f.get("token") ?? "").trim();
  if (!/^\d{5,30}$/.test(phone)) return { erro: "O ID do número deve ter só dígitos (está no painel da Meta, em WhatsApp > Configuração da API)." };
  if (waba && !/^\d{5,30}$/.test(waba)) return { erro: "O ID da conta do WhatsApp Business deve ter só dígitos." };
  const { data: atual } = await db.from("whatsapp_contas").select("token").eq("salao_id", salao.id).maybeSingle();
  const novoToken = token || atual?.token;
  if (!novoToken) return { erro: "Cole o token de acesso permanente." };
  if (novoToken.length < 20) return { erro: "O token parece curto demais. Copie ele inteiro." };
  const prova = await validarConta({ phone_number_id: phone, token: novoToken });
  if (!prova.ok) return { erro: `A Meta não confirmou que esse token dá acesso a esse número (${prova.erro}). Confira o ID do número e o token permanente.` };
  const { error } = await db.from("whatsapp_contas").upsert({ salao_id: salao.id, phone_number_id: phone, waba_id: waba || null, token: novoToken }, { onConflict: "salao_id" });
  if (error) return { erro: error.code === "23505" ? "Esse número já está conectado a outro salão." : "Não foi possível salvar." };
  revalidatePath("/whatsapp");
  return { ok: "Conexão salva. Agora cadastre o endereço do webhook na Meta, como mostram as instruções abaixo." };
}

export async function desconectar() {
  const { membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") return;
  const db = clienteAdmin();
  await db?.from("whatsapp_contas").delete().eq("salao_id", salao.id);
  revalidatePath("/whatsapp");
}
