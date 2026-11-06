import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { criarSalao } from "./actions";

export const metadata = { title: "Criar salão" };

export default async function Comecar() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/entrar");
  const { data: membro } = await supabase.from("membros").select("user_id").eq("user_id", user.id).maybeSingle();
  if (membro) redirect("/hoje");
  return (
    <main className="auth">
      <div className="card stack-lg">
        <div className="stack">
          <h1>Vamos criar a seu salão</h1>
          <p className="sec">Você será o administrador. Cadastramos alguns serviços de partida para você ajustar depois.</p>
        </div>
        <AcaoForm action={criarSalao}>
          <div className="field"><label htmlFor="nome">Nome do salão</label><input id="nome" name="nome" required minLength={2} maxLength={120} placeholder="Studio Bela" /></div>
          <div className="field"><label htmlFor="seu_nome">Seu nome</label><input id="seu_nome" name="seu_nome" required minLength={2} maxLength={120} placeholder="Ana Souza" /></div>
          <Enviar>Criar salão</Enviar>
        </AcaoForm>
      </div>
    </main>
  );
}
