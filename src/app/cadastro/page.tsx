import Link from "next/link";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { cadastrar } from "../entrar/actions";

export const metadata = { title: "Criar conta" };

export default function Cadastro() {
  return (
    <main className="auth">
      <div className="card stack-lg">
        <div className="row"><img src="/icone.png" alt="" width={40} height={40} /><h1>Criar conta</h1></div>
        <AcaoForm action={cadastrar}>
          <div className="field"><label htmlFor="email">E-mail</label><input id="email" name="email" type="email" autoComplete="email" required /></div>
          <div className="field">
            <label htmlFor="senha">Senha</label>
            <input id="senha" name="senha" type="password" autoComplete="new-password" minLength={8} required />
            <span className="hint">Mínimo de 8 caracteres.</span>
          </div>
          <Enviar>Criar conta</Enviar>
        </AcaoForm>
        <p className="sm sec">Já tem conta? <Link href="/entrar">Entrar</Link></p>
      </div>
    </main>
  );
}
