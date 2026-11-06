"use client";
import { useState } from "react";

export function Copiar({ texto, rotulo }: { texto: string; rotulo?: string }) {
  const [ok, setOk] = useState(false);
  return (
    <button className="btn" type="button" onClick={async () => { await navigator.clipboard.writeText(texto); setOk(true); setTimeout(() => setOk(false), 2500); }}>
      {ok ? (rotulo ? "Copiado!" : "Copiado! Cole no app do banco") : rotulo ?? "Copiar código Pix"}
    </button>
  );
}
