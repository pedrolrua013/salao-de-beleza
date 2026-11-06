"use client";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

export type Estado = { erro?: string; ok?: string };
export type Acao = (anterior: Estado, dados: FormData) => Promise<Estado>;

export function Enviar({ children, className = "btn" }: { children: React.ReactNode; className?: string }) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" className={className} disabled={pending}>
      {pending && <span className="spin" aria-hidden="true" />}{pending ? "Aguarde…" : children}
    </button>
  );
}

/** Formulário ligado a uma Server Action. Mostra erro ou sucesso devolvidos pela ação. */
export function AcaoForm({ action, children, className = "stack" }: { action: Acao; children: React.ReactNode; className?: string }) {
  const [estado, enviar] = useActionState(action, {} as Estado);
  return (
    <form action={enviar} className={className}>
      {estado.erro && <p className="err" role="alert">{estado.erro}</p>}
      {estado.ok && <p className="okmsg" role="status">{estado.ok}</p>}
      {children}
    </form>
  );
}
