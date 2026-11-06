"use client";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { MESES, MESES_CURTOS, dataBr, hojeIso, iso, lerDataBr, mascararData, semanasDoMes } from "@/lib/calendario";

type Vista = "dias" | "meses" | "anos";
const SEMANA = ["D", "S", "T", "Q", "Q", "S", "S"];

/**
 * Campo de data: digita DD/MM/AAAA ou escolhe no calendário. Clicar no mês e no ano troca a vista,
 * então chegar em 1990 são dois toques (e não rolar uma lista). Envia AAAA-MM-DD no nome indicado.
 * `ano`: abre direto na escolha do ano (bom para data de nascimento).
 */
export function CampoData({ id, name, defaultValue, value, onChange, required, ariaLabel, inicio = "dias", min, max: maxBruto }: {
  id?: string; name: string; defaultValue?: string | null; value?: string; onChange?: (v: string) => void;
  required?: boolean; ariaLabel?: string; inicio?: "dias" | "ano"; min?: string; max?: string;
}) {
  // "hoje" é calculado no aparelho de quem usa (no servidor, à noite, já seria amanhã em UTC).
  const max = maxBruto === "hoje" ? hojeIso() : maxBruto;
  const controlado = value !== undefined;
  const [interno, setInterno] = useState(defaultValue ?? "");
  const atual = controlado ? value : interno;
  const [texto, setTexto] = useState(dataBr(atual));
  const [aberto, setAberto] = useState(false);
  const [vista, setVista] = useState<Vista>("dias");
  const base = atual || hojeIso();
  const [cursor, setCursor] = useState({ ano: +base.slice(0, 4), mes: +base.slice(5, 7) });
  const [aDireita, setADireita] = useState(false);
  const caixa = useRef<HTMLDivElement>(null);
  const hoje = hojeIso();

  // Valor mudou por fora (ex.: escolheu um horário sugerido de outro dia): o texto acompanha.
  useEffect(() => { if (controlado) setTexto(dataBr(value)); }, [controlado, value]);

  function escolher(v: string) {
    if (!controlado) setInterno(v);
    onChange?.(v);
    setTexto(dataBr(v));
  }

  function abrir() {
    const b = atual || (inicio === "ano" ? `${new Date().getFullYear() - 30}-01-01` : hojeIso());
    setCursor({ ano: +b.slice(0, 4), mes: +b.slice(5, 7) });
    setVista(inicio === "ano" && !atual ? "anos" : "dias");
    setAberto(true);
  }

  // Fecha ao clicar fora ou apertar Esc.
  useEffect(() => {
    if (!aberto) return;
    const fora = (e: PointerEvent) => { if (!caixa.current?.contains(e.target as Node)) setAberto(false); };
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") setAberto(false); };
    document.addEventListener("pointerdown", fora);
    document.addEventListener("keydown", esc);
    return () => { document.removeEventListener("pointerdown", fora); document.removeEventListener("keydown", esc); };
  }, [aberto]);

  // Perto da borda direita da tela, o calendário abre alinhado à direita.
  useLayoutEffect(() => {
    if (!aberto || !caixa.current) return;
    setADireita(caixa.current.getBoundingClientRect().left + 312 > window.innerWidth);
  }, [aberto]);

  const fora = (v: string) => (!!min && v < min) || (!!max && v > max);
  const mudarMes = (n: number) => setCursor(({ ano, mes }) => {
    const t = ano * 12 + (mes - 1) + n;
    return { ano: Math.floor(t / 12), mes: (t % 12) + 1 };
  });
  const maxAno = max ? +max.slice(0, 4) : null, minAno = min ? +min.slice(0, 4) : null;
  // Com data máxima (ex.: nascimento), as páginas de anos terminam no ano atual: nada de anos que ainda não chegaram.
  const inicioAnos = maxAno !== null ? maxAno - 11 - 12 * Math.max(0, Math.floor((maxAno - cursor.ano) / 12)) : Math.floor(cursor.ano / 12) * 12;
  const anos = Array.from({ length: 12 }, (_, i) => inicioAnos + i).filter((a) => (maxAno === null || a <= maxAno) && (minAno === null || a >= minAno));
  const mesFora = (ano: number, mes: number) => (!!max && iso(ano, mes, 1) > max) || (!!min && iso(ano, mes, new Date(Date.UTC(ano, mes, 0)).getUTCDate()) < min);
  const proximo = { ano: cursor.mes === 12 ? cursor.ano + 1 : cursor.ano, mes: cursor.mes === 12 ? 1 : cursor.mes + 1 };
  const anterior = { ano: cursor.mes === 1 ? cursor.ano - 1 : cursor.ano, mes: cursor.mes === 1 ? 12 : cursor.mes - 1 };
  const semProximo = vista === "dias" ? mesFora(proximo.ano, proximo.mes) : maxAno !== null && (vista === "anos" ? inicioAnos + 12 : cursor.ano + 1) > maxAno;
  const semAnterior = vista === "dias" ? mesFora(anterior.ano, anterior.mes) : minAno !== null && (vista === "anos" ? inicioAnos - 1 : cursor.ano - 1) < minAno;

  return (
    <div className="cal" ref={caixa}>
      <input type="hidden" name={name} value={atual} />
      <div className="cal-campo">
        <input id={id} aria-label={ariaLabel} inputMode="numeric" autoComplete="off" placeholder="DD/MM/AAAA"
          value={texto} required={required} pattern="\d{2}/\d{2}/\d{4}" title="Use DD/MM/AAAA"
          onChange={(e) => {
            const t = mascararData(e.target.value);
            setTexto(t);
            const v = lerDataBr(t);
            if (v) { if (!controlado) setInterno(v); onChange?.(v); setCursor({ ano: +v.slice(0, 4), mes: +v.slice(5, 7) }); }
            else if (!t) { if (!controlado) setInterno(""); onChange?.(""); }
          }}
          onBlur={() => { if (texto && !lerDataBr(texto)) setTexto(dataBr(atual)); }} />
        <button type="button" className="cal-icone" aria-label="Abrir calendário" aria-expanded={aberto} onClick={() => (aberto ? setAberto(false) : abrir())}>
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" d="M7 3v3M17 3v3M4 9h16M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z" /></svg>
        </button>
      </div>

      {aberto && (
        <div className={`cal-pop${aDireita ? " direita" : ""}`} role="dialog" aria-label="Escolher data">
          <div className="cal-topo">
            <button type="button" className="cal-seta" aria-label="Anterior" disabled={semAnterior}
              onClick={() => (vista === "dias" ? mudarMes(-1) : setCursor((c) => ({ ...c, ano: c.ano - (vista === "anos" ? 12 : 1) })))}>‹</button>
            <div className="cal-titulo">
              {vista === "dias" && <>
                <button type="button" onClick={() => setVista("meses")}>{MESES[cursor.mes - 1]}</button>
                <button type="button" onClick={() => setVista("anos")}>{cursor.ano}</button>
              </>}
              {vista === "meses" && <button type="button" onClick={() => setVista("anos")}>{cursor.ano}</button>}
              {vista === "anos" && <span>{anos[0]} – {anos[anos.length - 1]}</span>}
            </div>
            <button type="button" className="cal-seta" aria-label="Próximo" disabled={semProximo}
              onClick={() => (vista === "dias" ? mudarMes(1) : setCursor((c) => ({ ...c, ano: c.ano + (vista === "anos" ? 12 : 1) })))}>›</button>
          </div>

          {vista === "dias" && (
            <div className="cal-dias" role="grid">
              {SEMANA.map((s, i) => <span key={i} className="cal-sem" aria-hidden="true">{s}</span>)}
              {semanasDoMes(cursor.ano, cursor.mes).flat().map((d, i) => {
                if (!d) return <span key={i} />;
                const v = iso(cursor.ano, cursor.mes, d);
                return (
                  <button key={i} type="button" disabled={fora(v)}
                    className={`cal-dia${v === atual ? " on" : ""}${v === hoje ? " hoje" : ""}`}
                    aria-label={`${d} de ${MESES[cursor.mes - 1]} de ${cursor.ano}`} aria-pressed={v === atual}
                    onClick={() => { escolher(v); setAberto(false); }}>{d}</button>
                );
              })}
            </div>
          )}
          {vista === "meses" && (
            <div className="cal-grade">
              {MESES_CURTOS.map((m, i) => (
                <button key={m} type="button" disabled={mesFora(cursor.ano, i + 1)} className={`cal-opcao${cursor.mes === i + 1 && atual.startsWith(String(cursor.ano)) ? " on" : ""}`}
                  onClick={() => { setCursor((c) => ({ ...c, mes: i + 1 })); setVista("dias"); }}>{m}</button>
              ))}
            </div>
          )}
          {vista === "anos" && (
            <div className="cal-grade">
              {anos.map((a) => (
                <button key={a} type="button" className={`cal-opcao${atual.startsWith(String(a)) ? " on" : ""}${a === new Date().getFullYear() ? " hoje" : ""}`}
                  onClick={() => { setCursor((c) => ({ ...c, ano: a })); setVista("meses"); }}>{a}</button>
              ))}
            </div>
          )}

          <div className="cal-rodape">
            {!required && atual ? <button type="button" className="btn ghost sm" onClick={() => { escolher(""); setAberto(false); }}>Limpar</button> : <span />}
            {inicio !== "ano" && !fora(hoje) && <button type="button" className="btn ghost sm" onClick={() => { escolher(hoje); setAberto(false); }}>Hoje</button>}
          </div>
        </div>
      )}
    </div>
  );
}
