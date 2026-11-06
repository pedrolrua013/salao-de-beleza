import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

/** Link do e-mail de confirmação: já entra na conta e segue para o cadastro do salão. Aberto em outro aparelho, só confirma. */
export async function GET(req: Request) {
  const url = new URL(req.url);
  // O endereço que o servidor enxerga pode ser 0.0.0.0 ou interno; o do site configurado é o que o navegador abre.
  const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") || url.origin;
  const code = url.searchParams.get("code");
  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL("/comecar", site));
  }
  // Link vencido ou já usado: volta para o login sem dizer que confirmou.
  if (url.searchParams.has("error")) return NextResponse.redirect(new URL("/entrar", site));
  return NextResponse.redirect(new URL("/entrar?confirmado=1", site));
}
