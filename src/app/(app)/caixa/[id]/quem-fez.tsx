"use client";
import { useState } from "react";

/** Quem fez e assistente: o assistente nunca é a mesma pessoa (a lista dele some com quem fez). */
export function QuemFez({ equipe, padrao }: { equipe: { id: string; nome: string }[]; padrao: string }) {
  const [prof, setProf] = useState(padrao);
  const [assist, setAssist] = useState("");
  return (
    <>
      <div className="field"><label htmlFor="ip">Quem fez</label>
        <select id="ip" name="profissional_id" required value={prof} onChange={(e) => { setProf(e.target.value); if (e.target.value === assist) setAssist(""); }}>
          <option value="" disabled>Escolha</option>
          {equipe.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
        </select></div>
      <div className="field"><label htmlFor="ia">Assistente (divide a comissão)</label>
        <select id="ia" name="assistente_id" value={assist} onChange={(e) => setAssist(e.target.value)}>
          <option value="">Ninguém</option>
          {equipe.filter((p) => p.id !== prof).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
        </select></div>
    </>
  );
}
