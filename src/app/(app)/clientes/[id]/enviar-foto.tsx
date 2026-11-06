"use client";
import { useFormStatus } from "react-dom";
import { AcaoForm } from "@/components/acao-form";
import { enviarFoto } from "./actions";

function Botao({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <label className={`fotos-add${pending ? " enviando" : ""}`}>
      <input type="file" name="foto" accept="image/*" capture="environment" required disabled={pending}
        onChange={(e) => { if (e.currentTarget.files?.length) e.currentTarget.form?.requestSubmit(); }} />
      {pending ? <><span className="spin" aria-hidden="true" /> Enviando…</> : <>+ {rotulo}</>}
    </label>
  );
}

/** Escolheu a foto, ela já sobe na coluna certa (sem precisar escolher o momento numa lista). */
export function EnviarFoto({ clienteId, momento, rotulo }: { clienteId: string; momento: string; rotulo: string }) {
  return (
    <AcaoForm action={enviarFoto} className="fotos-form">
      <input type="hidden" name="cliente_id" value={clienteId} /><input type="hidden" name="momento" value={momento} />
      <Botao rotulo={rotulo} />
    </AcaoForm>
  );
}
