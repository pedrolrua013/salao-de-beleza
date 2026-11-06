"use server";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { dentroDoLimite, ipDoCliente } from "@/lib/limite";
import { createClient } from "@/lib/supabase/server";
import type { Estado } from "@/components/acao-form";

const MUITAS = "Muitas tentativas. Espere 15 minutos e tente de novo.";

export async function entrar(_: Estado, f: FormData): Promise<Estado> {
  const email = String(f.get("email") ?? "").trim().toLowerCase();
  const ip = ipDoCliente(await headers()) ?? "sem-ip";
  // Contra quem tenta adivinhar senha: por endereço e por e-mail.
  if (!(await dentroDoLimite(`login:ip:${ip}`, 20, 15)) || !(await dentroDoLimite(`login:email:${email}`, 8, 15))) return { erro: MUITAS };
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email,
    password: String(f.get("senha") ?? ""),
  });
  if (error) {
    // Só dá "não confirmado" com a senha certa: não revela se o e-mail tem conta.
    if (error.code === "email_not_confirmed") return { erro: "Falta confirmar o seu e-mail. Abra a mensagem que enviamos e toque no link (veja também o spam)." };
    return { erro: "E-mail ou senha incorretos." };
  }
  redirect("/hoje");
}

export async function cadastrar(_: Estado, f: FormData): Promise<Estado> {
  const senha = String(f.get("senha") ?? "");
  if (senha.length < 8) return { erro: "A senha precisa ter pelo menos 8 caracteres." };
  if (senha.length > 72) return { erro: "A senha pode ter no máximo 72 caracteres." };
  if (!(await dentroDoLimite(`cadastro:ip:${ipDoCliente(await headers()) ?? "sem-ip"}`, 5, 60))) return { erro: "Muitos cadastros seguidos. Tente de novo mais tarde." };
  const supabase = await createClient();
  const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "");
  const { data, error } = await supabase.auth.signUp({
    email: String(f.get("email") ?? "").trim(), password: senha,
    options: site ? { emailRedirectTo: `${site}/auth/confirmar` } : undefined,
  });
  if (error) {
    const msg: Record<string, string> = {
      over_email_send_rate_limit: "Muitos cadastros em pouco tempo: o envio do e-mail de confirmação está no limite. Tente de novo daqui a alguns minutos.",
      email_address_invalid: "Esse e-mail não parece válido. Confira e tente de novo.",
      weak_password: "Essa senha é fraca ou já apareceu em vazamentos. Escolha outra.",
      user_already_exists: "Esse e-mail já tem conta. Entre pela tela de login.",
      signup_disabled: "Novos cadastros estão desligados no momento.",
    };
    return { erro: msg[error.code ?? ""] ?? "Não foi possível criar a conta. Confira o e-mail e tente de novo." };
  }
  // Com confirmação de e-mail ligada, o Supabase não dá erro para e-mail já cadastrado: devolve um usuário sem identidades.
  if (data.user && data.user.identities?.length === 0) return { erro: "Esse e-mail já tem conta. Entre pela tela de login." };
  if (!data.session) return { ok: "Enviamos um e-mail para confirmar sua conta. Depois de confirmar, entre aqui." };
  redirect("/comecar");
}

export async function sair() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/entrar");
}
