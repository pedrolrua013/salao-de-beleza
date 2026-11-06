import Link from "next/link";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { entrar } from "./actions";

export const metadata = { title: "Entrar" };

export default async function Entrar({ searchParams }: { searchParams: Promise<{ confirmado?: string }> }) {
  const { confirmado } = await searchParams;
  return (
    <main className="auth">
      <div className="card stack-lg">
        <div className="row"><img src="/icone.png" alt="" width={40} height={40} /><h1>Entrar no Belezando</h1></div>
        {confirmado && <p className="okmsg" role="status">E-mail confirmado. Agora é só entrar.</p>}
        <AcaoForm action={entrar}>
          <div className="field"><label htmlFor="email">E-mail</label><input id="email" name="email" type="email" autoComplete="email" required /></div>
          <div className="field"><label htmlFor="senha">Senha</label><input id="senha" name="senha" type="password" autoComplete="current-password" required /></div>
          <Enviar>Entrar</Enviar>
        </AcaoForm>
        <p className="sm sec">Ainda não tem conta? <Link href="/cadastro">Criar conta do salão</Link></p>
      </div>
    </main>
  );
}
