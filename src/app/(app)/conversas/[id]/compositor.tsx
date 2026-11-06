"use client";
import { useActionState, useRef } from "react";
import { useFormStatus } from "react-dom";
import { enviarMensagem } from "../actions";

function Botao() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" className="btn envia" disabled={pending} aria-label="Enviar mensagem">
      {pending ? <span className="spin" aria-hidden="true" /> : <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path d="M3 11.5L21 3l-6.5 18-3.5-7.5z" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" /></svg>}
    </button>
  );
}

/** Enter envia, Shift+Enter quebra a linha. */
export function Compositor({ id, aberta, horas }: { id: string; aberta: boolean; horas: number }) {
  const [estado, enviar] = useActionState(enviarMensagem, {});
  const form = useRef<HTMLFormElement>(null);
  return (
    <form ref={form} action={enviar} className="comp">
      {estado.erro && <p className="err" role="alert">{estado.erro}</p>}
      <input type="hidden" name="id" value={id} />
      <div className="comp-linha">
        <textarea name="texto" rows={1} maxLength={4000} required disabled={!aberta} aria-label="Mensagem"
          placeholder={aberta ? "Escreva uma resposta…" : "O cliente precisa escrever primeiro"}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); form.current?.requestSubmit(); } }} />
        <Botao />
      </div>
      <p className="comp-dica sm">
        {aberta ? <>Janela do WhatsApp aberta por mais {horas <= 1 ? "menos de 1 hora" : `${horas} horas`}. Ao responder, o robô para de atender esta conversa.</>
          : <>Passaram mais de 24 horas desde a última mensagem do cliente. O WhatsApp só deixa responder depois que ele escrever de novo.</>}
      </p>
    </form>
  );
}
