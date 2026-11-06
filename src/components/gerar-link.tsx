"use client";
import { useActionState, useState } from "react";
import { Enviar } from "@/components/acao-form";

export type EstadoLink = { erro?: string; link?: string; mensagem?: string };

/** Botão que gera um link (área da cliente, cobrança...) e mostra para abrir, copiar ou mandar no WhatsApp. */
export function GerarLink({ acao, campos, rotulo, telefone }: {
  acao: (e: EstadoLink, f: FormData) => Promise<EstadoLink>; campos: Record<string, string>; rotulo: string; telefone?: string | null;
}) {
  const [estado, enviar] = useActionState(acao, {} as EstadoLink);
  const [copiado, setCopiado] = useState(false);
  const tel = telefone?.replace(/\D/g, "");
  return (
    <div className="stack" style={{ gap: 8 }}>
      <form action={enviar} className="row">
        {Object.entries(campos).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
        <Enviar className="btn sec sm">{rotulo}</Enviar>
      </form>
      {estado.erro && <p className="err" role="alert">{estado.erro}</p>}
      {estado.link && (
        <div className="pub-link">
          <code>{estado.link}</code>
          <a className="btn ghost sm" href={estado.link} target="_blank" rel="noopener">Abrir</a>
          <button type="button" className="btn ghost sm" onClick={async () => { await navigator.clipboard.writeText(estado.link!); setCopiado(true); setTimeout(() => setCopiado(false), 2500); }}>{copiado ? "Copiado!" : "Copiar"}</button>
          {tel && <a className="btn sm" href={`https://wa.me/55${tel}?text=${encodeURIComponent(`${estado.mensagem ?? ""} ${estado.link}`.trim())}`} target="_blank" rel="noopener">Mandar no WhatsApp</a>}
        </div>
      )}
    </div>
  );
}
