"use client";
import Link from "next/link";
import { useMemo, useRef, useState } from "react";
import { lerCsv } from "@/lib/csv";
import { lerPlanilha } from "@/lib/planilha";
import { CAMPOS, detectarMapa, letraColuna, prepararClientes, type Campo, type Mapa } from "@/lib/importar-clientes";
import { formatarTelefone } from "@/lib/telefone";
import { dataBR } from "@/lib/format";
import { importarLote } from "./actions";

const MAX = 20000, LOTE = 1000;
const MODELO = "﻿Nome;Celular;E-mail;Nascimento;CEP;Número;Complemento;Observações\r\nAna Souza;(13) 99999-0000;ana@email.com;31/12/1990;11430-090;120;Apto 12;Gosta de café\r\n";

/** "1 linha sem nome", "3 linhas sem nome". */
const qtd = (n: number, um: string, varios: string) => `${n.toLocaleString("pt-BR")} ${n === 1 ? um : varios}`;

type Fase = { f: "escolher" } | { f: "conferir" } | { f: "importando"; feitas: number } | { f: "pronto"; criadas: number; repetidas: number; erro?: string };

/** Planilha → conferir as colunas → importar em pedaços, com progresso. */
export function Importador({ dddPadrao, depois }: { dddPadrao: string | null; depois?: { href: string; rotulo: string } }) {
  const [fase, setFase] = useState<Fase>({ f: "escolher" });
  const [erro, setErro] = useState("");
  const [linhas, setLinhas] = useState<string[][]>([]);
  const [nomeArq, setNomeArq] = useState("");
  const [temCab, setTemCab] = useState(true);
  const [mapa, setMapa] = useState<Mapa | null>(null);
  const [ddd, setDdd] = useState(dddPadrao ?? "");
  const [colado, setColado] = useState("");
  const arquivo = useRef<HTMLInputElement>(null);

  function carregar(l: string[][], nome: string) {
    const uteis = l.filter((x) => x.some((c) => c.trim()));
    if (uteis.length === 0) { setErro("Não achamos nenhuma linha preenchida."); return; }
    if (uteis.length > MAX + 1) { setErro(`São ${uteis.length} linhas: importe até ${MAX.toLocaleString("pt-BR")} por vez (divida a planilha).`); return; }
    const d = detectarMapa(uteis[0]);
    setErro(""); setLinhas(uteis); setNomeArq(nome); setTemCab(d.temCabecalho); setMapa(d.mapa); setFase({ f: "conferir" });
  }

  async function escolher(f: File | undefined) {
    if (!f) return;
    if (f.size > 15 * 1024 * 1024) { setErro("O arquivo pode ter até 15 MB."); return; }
    setErro("Lendo a planilha...");
    const r = await lerPlanilha(new Uint8Array(await f.arrayBuffer()));
    if ("erro" in r) { setErro(r.erro); return; }
    carregar(r.linhas, f.name);
  }

  const dados = useMemo(() => (temCab ? linhas.slice(1) : linhas), [linhas, temCab]);
  const resumo = useMemo(() => (mapa ? prepararClientes(dados, mapa, /^\d{2}$/.test(ddd) ? ddd : null) : null), [dados, mapa, ddd]);
  const nCols = Math.max(0, ...linhas.slice(0, 50).map((l) => l.length));
  const exemplo = (i: number) => dados.find((l) => (l[i] ?? "").trim())?.[i]?.slice(0, 30) ?? "";

  async function importar() {
    if (!resumo || resumo.clientes.length === 0) return;
    let criadas = 0, repetidas = 0;
    setFase({ f: "importando", feitas: 0 });
    for (let i = 0; i < resumo.clientes.length; i += LOTE) {
      let r;
      try { r = await importarLote(resumo.clientes.slice(i, i + LOTE)); }
      catch { r = { erro: "A conexão caiu no meio da importação." }; }
      if ("erro" in r) {
        setFase({ f: "pronto", criadas, repetidas, erro: `${r.erro} Você pode importar a mesma planilha de novo: quem já entrou não é duplicado.` });
        return;
      }
      criadas += r.criadas; repetidas += r.repetidas;
      setFase({ f: "importando", feitas: Math.min(resumo.clientes.length, i + LOTE) });
    }
    setFase({ f: "pronto", criadas, repetidas });
  }

  if (fase.f === "pronto") return (
    <div className="stack">
      {fase.erro ? <div className="aviso" role="alert">{fase.erro}</div> : <div className="imp-ok" role="status"><strong>{qtd(fase.criadas, "cliente importada", "clientes importadas")}.</strong></div>}
      <ul className="imp-resumo">
        {fase.erro && <li>{qtd(fase.criadas, "cliente entrou", "clientes entraram")} antes do erro.</li>}
        {fase.repetidas > 0 && <li>{qtd(fase.repetidas, "já estava no cadastro (mesmo celular ou mesmo nome) e não foi duplicada", "já estavam no cadastro (mesmo celular ou mesmo nome) e não foram duplicadas")}.</li>}
        {resumo && resumo.semNome > 0 && <li>{qtd(resumo.semNome, "linha sem nome foi pulada", "linhas sem nome foram puladas")}.</li>}
        {resumo && resumo.repetidasNaPlanilha > 0 && <li>{qtd(resumo.repetidasNaPlanilha, "aparecia mais de uma vez na planilha e entrou uma vez só", "apareciam mais de uma vez na planilha e entraram uma vez só")}.</li>}
      </ul>
      <p className="cap muted" style={{ margin: 0 }}>Clientes importadas não recebem lembretes pelo WhatsApp até autorizarem (LGPD). A autorização é marcada no cadastro de cada uma ou quando ela marca pelo link.</p>
      <div className="row">
        {depois ? <Link className="btn" href={depois.href}>{depois.rotulo}</Link> : <Link className="btn" href="/clientes">Ver clientes</Link>}
        <button type="button" className="btn sec" onClick={() => { setFase({ f: "escolher" }); setLinhas([]); setColado(""); }}>Importar outra planilha</button>
      </div>
    </div>
  );

  if (fase.f === "importando" && resumo) {
    const pct = Math.round((fase.feitas / resumo.clientes.length) * 100);
    return (
      <div className="stack" role="status" aria-live="polite">
        <p><span className="spin" aria-hidden="true" /> Importando {resumo.clientes.length.toLocaleString("pt-BR")} clientes... {pct}%</p>
        <div className="imp-barra"><i style={{ width: `${Math.max(3, pct)}%` }} /></div>
        <p className="cap muted" style={{ margin: 0 }}>Não feche esta página até terminar.</p>
      </div>
    );
  }

  if (fase.f === "conferir" && mapa && resumo) return (
    <div className="stack">
      <div className="row between"><p style={{ margin: 0 }}><strong>{nomeArq}</strong> · {dados.length.toLocaleString("pt-BR")} linhas</p>
        <button type="button" className="btn sec sm" onClick={() => { setFase({ f: "escolher" }); setLinhas([]); }}>Escolher outra</button></div>

      <div className="stack" style={{ gap: 8 }}>
        <h3 style={{ margin: 0 }}>1. Confira as colunas</h3>
        <p className="sm sec" style={{ margin: 0 }}>Reconhecemos as colunas pelo nome. Se alguma estiver errada, troque aqui.</p>
        <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}>
          <input type="checkbox" checked={temCab} onChange={(e) => setTemCab(e.target.checked)} />A primeira linha é o título das colunas
        </label>
        <div className="imp-mapa">
          {CAMPOS.map(([k, rotulo]) => (
            <div key={k} className="field">
              <label htmlFor={`m-${k}`}>{rotulo}{k === "nome" && " *"}</label>
              <select id={`m-${k}`} value={mapa[k]} onChange={(e) => setMapa({ ...mapa, [k]: Number(e.target.value) } as Record<Campo, number>)}>
                <option value={-1}>Não importar</option>
                {Array.from({ length: nCols }, (_, i) => (
                  <option key={i} value={i}>{temCab && linhas[0][i] ? linhas[0][i].slice(0, 30) : `Coluna ${letraColuna(i)}`}{exemplo(i) ? ` (ex.: ${exemplo(i)})` : ""}</option>
                ))}
              </select>
            </div>
          ))}
        </div>
        <div className="field" style={{ maxWidth: 260 }}>
          <label htmlFor="ddd">DDD para celulares sem DDD</label>
          <input id="ddd" inputMode="numeric" maxLength={2} value={ddd} onChange={(e) => setDdd(e.target.value.replace(/\D/g, ""))} placeholder="13" />
        </div>
      </div>

      <div className="stack" style={{ gap: 8 }}>
        <h3 style={{ margin: 0 }}>2. Veja como vão ficar</h3>
        {mapa.nome < 0 ? <div className="aviso" role="alert">Escolha qual coluna tem o nome da cliente.</div> : (
          <>
            <div className="scroll"><table className="tab">
              <thead><tr><th>Nome</th><th>Celular</th><th>E-mail</th><th>Nascimento</th><th>Endereço</th></tr></thead>
              <tbody>{resumo.clientes.slice(0, 5).map((c, i) => (
                <tr key={i}><td>{c.nome}</td><td>{c.telefone ? formatarTelefone(c.telefone) : <span className="muted">—</span>}</td><td>{c.email ?? <span className="muted">—</span>}</td>
                  <td>{c.nascimento ? dataBR(c.nascimento) : <span className="muted">—</span>}</td>
                  <td>{[c.logradouro && [c.logradouro, c.numero].filter(Boolean).join(", "), c.bairro, c.cidade].filter(Boolean).join(" · ") || <span className="muted">—</span>}</td></tr>
              ))}</tbody>
            </table></div>
            <ul className="imp-resumo">
              <li><strong>{qtd(resumo.clientes.length, "cliente pronta para entrar", "clientes prontas para entrar")}</strong></li>
              {resumo.semNome > 0 && <li>{qtd(resumo.semNome, "linha sem nome será pulada", "linhas sem nome serão puladas")}</li>}
              {resumo.repetidasNaPlanilha > 0 && <li>{qtd(resumo.repetidasNaPlanilha, "repetida", "repetidas")} na planilha (mesmo celular ou nome): {resumo.repetidasNaPlanilha === 1 ? "entra" : "entram"} uma vez só</li>}
              {resumo.comAviso > 0 && <li>{qtd(resumo.comAviso, "com celular, e-mail ou data que não deu para ler: entra", "com celular, e-mail ou data que não deu para ler: entram")} sem esse dado, e o celular original fica nas observações</li>}
              <li>Quem já está no seu cadastro não é duplicado</li>
            </ul>
          </>
        )}
      </div>
      <div><button type="button" className="btn" disabled={mapa.nome < 0 || resumo.clientes.length === 0} onClick={importar}>Importar {qtd(resumo.clientes.length, "cliente", "clientes")}</button></div>
    </div>
  );

  return (
    <div className="stack">
      <label className="imp-drop" onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); escolher(e.dataTransfer.files[0]); }}>
        <input ref={arquivo} type="file" accept=".xlsx,.csv,.txt,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv" onChange={(e) => escolher(e.target.files?.[0])} />
        <strong>Escolha a planilha ou arraste aqui</strong>
        <span className="sm sec">Excel (.xlsx) ou CSV, de uma planilha sua ou exportada de outro sistema</span>
      </label>
      {erro && <p className={erro.startsWith("Lendo") ? "sm sec" : "aviso"} role={erro.startsWith("Lendo") ? "status" : "alert"} style={{ margin: 0 }}>{erro}</p>}
      <details className="aj">
        <summary>Ou copie e cole da planilha</summary>
        <div className="stack" style={{ paddingTop: 8 }}>
          <label htmlFor="colar" className="sm sec">No Excel ou no Google Planilhas, selecione as colunas (com os títulos), copie e cole aqui.</label>
          <textarea id="colar" value={colado} onChange={(e) => setColado(e.target.value)} style={{ minHeight: 120 }} placeholder={"Nome\tCelular\nAna Souza\t(13) 99999-0000"} />
          <div><button type="button" className="btn sec" disabled={!colado.trim()} onClick={() => carregar(lerCsv(colado), "Texto colado")}>Continuar</button></div>
        </div>
      </details>
      <p className="cap muted" style={{ margin: 0 }}>
        Reconhecemos Nome, Celular (ou Telefone/WhatsApp), E-mail, Nascimento, CEP, endereço, Alergias e Observações. Não tem planilha pronta?{" "}
        <a href={`data:text/csv;charset=utf-8,${encodeURIComponent(MODELO)}`} download="modelo-clientes-belezando.csv">Baixe o modelo</a>.
      </p>
    </div>
  );
}
