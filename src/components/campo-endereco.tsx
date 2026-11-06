"use client";
import { useRef, useState } from "react";
import { buscarCep, formatarCep, UFS } from "@/lib/cep";

type Inicial = { cep?: string | null; logradouro?: string | null; numero?: string | null; complemento?: string | null; bairro?: string | null; cidade?: string | null; uf?: string | null };

/** Endereço opcional: fica fechado até pedir; ao completar o CEP, rua, bairro, cidade e estado vêm sozinhos. */
export function CampoEndereco({ inicial, sempreAberto, legenda = "Endereço", dica }: { inicial?: Inicial | null; sempreAberto?: boolean; legenda?: string; dica?: string }) {
  const temAlgo = !!(inicial?.cep || inicial?.logradouro || inicial?.bairro || inicial?.cidade);
  const [aberto, setAberto] = useState(temAlgo || !!sempreAberto);
  const [cep, setCep] = useState(formatarCep(inicial?.cep ?? ""));
  const [rua, setRua] = useState(inicial?.logradouro ?? "");
  const [bairro, setBairro] = useState(inicial?.bairro ?? "");
  const [cidade, setCidade] = useState(inicial?.cidade ?? "");
  const [uf, setUf] = useState(inicial?.uf ?? "");
  const [aviso, setAviso] = useState("Preenche o endereço automaticamente.");
  const numero = useRef<HTMLInputElement>(null);
  const ultimo = useRef("");

  async function mudarCep(v: string) {
    const f = formatarCep(v);
    setCep(f);
    const d = f.replace(/\D/g, "");
    if (d.length !== 8 || d === ultimo.current) return;
    ultimo.current = d;
    setAviso("Buscando o endereço...");
    const r = await buscarCep(d);
    if (ultimo.current !== d) return; // já digitou outro CEP
    if (r === "falhou") { setAviso("Não deu para buscar agora. Preencha à mão."); return; }
    if (!r) { setAviso("CEP não encontrado. Confira os números ou preencha à mão."); return; }
    setRua(r.logradouro); setBairro(r.bairro); setCidade(r.cidade); setUf(r.uf);
    if (numero.current?.value.trim()) { setAviso("Endereço preenchido."); return; }
    setAviso("Endereço preenchido. Falta o número.");
    numero.current?.focus();
  }

  if (!aberto) return <button type="button" className="btn sec sm" style={{ width: "fit-content" }} onClick={() => setAberto(true)}>+ Adicionar endereço</button>;
  return (
    <fieldset className="endereco">
      <legend>{legenda}</legend>
      {dica && <p className="cap muted" style={{ margin: "-4px 0 0" }}>{dica}</p>}
      <div className="end-l1">
        <div className="field"><label htmlFor="cep">CEP</label>
          <input id="cep" name="cep" inputMode="numeric" autoComplete="postal-code" placeholder="00000-000" value={cep} onChange={(e) => mudarCep(e.target.value)} aria-describedby="cep-aviso" autoFocus={!temAlgo && !sempreAberto} />
          <span id="cep-aviso" className="cap muted" aria-live="polite">{aviso}</span></div>
        <div className="field"><label htmlFor="logradouro">Rua</label><input id="logradouro" name="logradouro" maxLength={200} autoComplete="address-line1" value={rua} onChange={(e) => setRua(e.target.value)} /></div>
      </div>
      <div className="end-l1">
        <div className="field"><label htmlFor="numero">Número</label><input id="numero" name="numero" ref={numero} maxLength={20} defaultValue={inicial?.numero ?? ""}
          onChange={(e) => setAviso((a) => (a.startsWith("Endereço preenchido") ? (e.target.value.trim() ? "Endereço preenchido." : "Endereço preenchido. Falta o número.") : a))} /></div>
        <div className="field"><label htmlFor="complemento">Complemento</label><input id="complemento" name="complemento" maxLength={100} defaultValue={inicial?.complemento ?? ""} placeholder="Apartamento, bloco, casa" /></div>
      </div>
      <div className="end-l3">
        <div className="field"><label htmlFor="bairro">Bairro</label><input id="bairro" name="bairro" maxLength={100} value={bairro} onChange={(e) => setBairro(e.target.value)} /></div>
        <div className="field"><label htmlFor="cidade">Cidade</label><input id="cidade" name="cidade" maxLength={100} autoComplete="address-level2" value={cidade} onChange={(e) => setCidade(e.target.value)} /></div>
        <div className="field"><label htmlFor="uf">Estado</label>
          <select id="uf" name="uf" value={uf} onChange={(e) => setUf(e.target.value)}><option value="">—</option>{UFS.map((u) => <option key={u} value={u}>{u}</option>)}</select></div>
      </div>
    </fieldset>
  );
}
