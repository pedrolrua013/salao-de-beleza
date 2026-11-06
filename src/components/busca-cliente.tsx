"use client";
import { useEffect, useRef, useState, useTransition } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { buscarClientes, type ClienteAchada } from "@/app/(app)/clientes/busca";
import { formatarTelefone } from "@/lib/telefone";

/**
 * Escolher a cliente digitando o nome ou o telefone (no lugar de uma lista que rola).
 * Não achou? Abre a tela de cadastro completa e, ao salvar, volta para esta página com a cliente escolhida.
 * Envia o id no nome indicado.
 * `avulso`: deixa ficar sem cliente (comanda de quem não quer cadastro).
 */
export function BuscaCliente({ id, name, inicial, required, avulso, ariaLabel, onEscolher }: {
  id?: string; name: string; inicial?: ClienteAchada | null; required?: boolean; avulso?: boolean; ariaLabel?: string;
  onEscolher?: (c: ClienteAchada | null) => void;
}) {
  const [escolhida, setEscolhida] = useState<ClienteAchada | null>(inicial ?? null);
  const [termo, setTermo] = useState("");
  const [achadas, setAchadas] = useState<ClienteAchada[]>([]);
  const [aberto, setAberto] = useState(false);
  const [ativo, setAtivo] = useState(0);
  const [erro, setErro] = useState("");
  const [buscando, iniciar] = useTransition();
  const caixa = useRef<HTMLDivElement>(null);
  const campo = useRef<HTMLInputElement>(null);
  const router = useRouter(), caminho = usePathname(), params = useSearchParams();

  // Busca enquanto digita (espera a pessoa parar 200 ms).
  useEffect(() => {
    if (escolhida || termo.trim().length < 2) { setAchadas([]); return; }
    let vivo = true;
    const t = setTimeout(() => iniciar(async () => { const r = await buscarClientes(termo); if (vivo) { setAchadas(r); setAtivo(0); } }), 200);
    return () => { vivo = false; clearTimeout(t); };
  }, [termo, escolhida]);

  useEffect(() => {
    if (!aberto) return;
    const fora = (e: PointerEvent) => { if (!caixa.current?.contains(e.target as Node)) { setAberto(false); } };
    document.addEventListener("pointerdown", fora);
    return () => document.removeEventListener("pointerdown", fora);
  }, [aberto]);

  function escolher(c: ClienteAchada | null) {
    setEscolhida(c); setAberto(false); setErro(""); setTermo("");
    onEscolher?.(c);
    if (!c) requestAnimationFrame(() => campo.current?.focus());
  }

  function abrirCadastro() {
    const t = termo.trim(), soNumero = /^[\d\s()+.-]+$/.test(t);
    const volta = new URLSearchParams(params.toString()); volta.delete("cliente");
    const q = new URLSearchParams({ voltar: `${caminho}${volta.size ? `?${volta}` : ""}` });
    if (t) q.set(soNumero ? "telefone" : "nome", t);
    router.push(`/clientes/novo?${q}`);
  }

  const opcoes = achadas.length + 1; // + "cadastrar nova"
  function teclado(e: React.KeyboardEvent) {
    if (e.key === "ArrowDown") { e.preventDefault(); setAberto(true); setAtivo((a) => (a + 1) % opcoes); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setAtivo((a) => (a - 1 + opcoes) % opcoes); }
    else if (e.key === "Enter" && aberto && termo.trim().length >= 2) { e.preventDefault(); if (ativo < achadas.length) escolher(achadas[ativo]); else abrirCadastro(); }
    else if (e.key === "Escape") setAberto(false);
  }

  return (
    <div className="bc" ref={caixa}>
      <input type="hidden" name={name} value={escolhida?.id ?? ""} />
      {escolhida ? (
        <div className="bc-escolhida">
          <span className="bc-avatar" aria-hidden="true">{escolhida.nome.trim()[0]?.toUpperCase()}</span>
          <span className="bc-nome"><strong>{escolhida.nome}</strong>{escolhida.telefone && <span className="cap sec">{formatarTelefone(escolhida.telefone)}</span>}</span>
          <button type="button" className="btn ghost sm" onClick={() => escolher(null)}>Trocar</button>
        </div>
      ) : (
        <div className="bc-campo">
          <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" strokeWidth="2" /><path d="m20 20-4-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>
          <input ref={campo} id={id} aria-label={ariaLabel} role="combobox" aria-expanded={aberto} aria-autocomplete="list" autoComplete="off"
            placeholder={avulso ? "Cliente avulso, ou busque pelo nome ou celular" : "Busque pelo nome ou celular"}
            value={termo} required={required && !escolhida}
            onChange={(e) => { setTermo(e.target.value); setAberto(true); }} onFocus={() => setAberto(true)} onKeyDown={teclado} />
          {buscando && <span className="spin" aria-hidden="true" />}
        </div>
      )}
      {aberto && !escolhida && termo.trim().length >= 2 && (
        <ul className="bc-lista" role="listbox">
          {achadas.map((c, i) => (
            <li key={c.id} role="option" aria-selected={i === ativo}>
              <button type="button" className={i === ativo ? "on" : ""} onMouseEnter={() => setAtivo(i)} onClick={() => escolher(c)}>
                <strong>{c.nome}</strong>{c.telefone && <span className="cap sec">{formatarTelefone(c.telefone)}</span>}
              </button>
            </li>
          ))}
          {!buscando && achadas.length === 0 && <li className="bc-nada cap muted">Nenhuma cliente com “{termo.trim()}”.</li>}
          <li role="option" aria-selected={ativo === achadas.length}>
            <button type="button" className={`bc-cadastrar${ativo === achadas.length ? " on" : ""}`} onMouseEnter={() => setAtivo(achadas.length)} onClick={abrirCadastro}>
              + Cadastrar cliente nova{termo.trim() && !/^[\d\s()+.-]+$/.test(termo.trim()) ? ` “${termo.trim()}”` : ""}
            </button>
          </li>
        </ul>
      )}
      {erro && <p className="err" role="alert">{erro}</p>}
    </div>
  );
}
