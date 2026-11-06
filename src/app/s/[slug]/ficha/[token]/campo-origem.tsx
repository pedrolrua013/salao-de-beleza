"use client";
import { useState } from "react";

/** "Como conheceu o salão?" — escolhendo Outro, abre um campo para escrever. */
export function CampoOrigem() {
  const [origem, setOrigem] = useState("");
  return (
    <div className="field">
      <label htmlFor="or">Como conheceu o salão?</label>
      <select id="or" name="origem" value={origem} onChange={(e) => setOrigem(e.target.value)}>
        <option value="">Prefiro não dizer</option><option value="indicacao">Indicação</option><option value="instagram">Instagram</option><option value="google">Google</option><option value="tiktok">TikTok</option><option value="facebook">Facebook</option><option value="passante">Passei na frente</option><option value="outro">Outro</option>
      </select>
      {origem === "outro" && <input name="origem_outro" maxLength={80} placeholder="Conta pra gente como foi" aria-label="Como conheceu o salão" autoFocus />}
    </div>
  );
}
