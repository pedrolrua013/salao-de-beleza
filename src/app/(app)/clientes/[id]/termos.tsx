"use client";
import { useActionState, useState } from "react";
import { Enviar } from "@/components/acao-form";
import { gerarLinkTermo, type EstadoTermo } from "./termos-actions";

/** Escolhe o termo e gera o link: a cliente assina no celular dela, ou ali mesmo no tablet do salão. */
export function GerarTermo({ clienteId, modelos }: { clienteId: string; modelos: { id: string; titulo: string }[] }) {
  const [estado, enviar] = useActionState(gerarLinkTermo, {} as EstadoTermo);
  const [copiado, setCopiado] = useState(false);
  return (
    <div className="stack">
      <form action={enviar} className="row" style={{ gap: 8 }}>
        <input type="hidden" name="cliente_id" value={clienteId} />
        <select name="modelo" aria-label="Termo" required defaultValue={modelos[0]?.id}>{modelos.map((m) => <option key={m.id} value={m.id}>{m.titulo}</option>)}</select>
        <Enviar className="btn sec sm">Gerar link para assinar</Enviar>
      </form>
      {estado.erro && <p className="err" role="alert">{estado.erro}</p>}
      {estado.link && (
        <div className="pub-link">
          <code>{estado.link}</code>
          <a className="btn sm" href={estado.link} target="_blank" rel="noopener">Assinar aqui no salão</a>
          <button type="button" className="btn ghost sm" onClick={async () => { await navigator.clipboard.writeText(estado.link!); setCopiado(true); setTimeout(() => setCopiado(false), 2500); }}>{copiado ? "Copiado!" : "Copiar para enviar"}</button>
        </div>
      )}
    </div>
  );
}
