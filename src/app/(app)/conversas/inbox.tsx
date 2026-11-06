"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

export type ItemInbox = {
  id: string; nome: string; sub: string; previa: string; quando: string;
  naoLidas: number; botAtivo: boolean; cliente: boolean;
};

const CORES = 5;
function cor(nome: string) { let h = 0; for (const c of nome) h = (h * 31 + c.charCodeAt(0)) % 997; return h % CORES; }
export function iniciais(nome: string) {
  const p = nome.replace(/[^\p{L}\s]/gu, "").trim().split(/\s+/).filter(Boolean);
  return ((p[0]?.[0] ?? "?") + (p.length > 1 ? p[p.length - 1][0] : "")).toUpperCase();
}
export function Avatar({ nome, grande = false }: { nome: string; grande?: boolean }) {
  return <span className={`av av${cor(nome)}${grande ? " av-g" : ""}`} aria-hidden="true">{iniciais(nome)}</span>;
}

const FILTROS = [["todas", "Todas"], ["nao-lidas", "Não lidas"], ["equipe", "Com a equipe"]] as const;

/** Duas colunas no computador (lista e conversa). No celular mostra uma de cada vez. */
export function Inbox({ itens, children }: { itens: ItemInbox[]; children: React.ReactNode }) {
  const path = usePathname();
  const abertaId = path.startsWith("/conversas/") ? path.split("/")[2] : null;
  const [filtro, setFiltro] = useState<(typeof FILTROS)[number][0]>("todas");
  const [busca, setBusca] = useState("");
  const naoLidas = itens.reduce((a, i) => a + i.naoLidas, 0);
  const lista = itens.filter((i) =>
    (filtro === "todas" || (filtro === "nao-lidas" ? i.naoLidas > 0 : !i.botAtivo)) &&
    (!busca.trim() || `${i.nome} ${i.sub}`.toLowerCase().includes(busca.trim().toLowerCase())));
  return (
    <div className="inbox" data-aberta={abertaId ? "sim" : "nao"}>
      <aside className="inbox-lista" aria-label="Conversas">
        <div className="inbox-topo">
          <h1>Conversas{naoLidas > 0 && <span className="cont">{naoLidas}<span className="sr"> não lidas</span></span>}</h1>
          <input className="inbox-busca" type="search" placeholder="Buscar nome ou telefone" aria-label="Buscar conversa" value={busca} onChange={(e) => setBusca(e.target.value)} />
          <div className="inbox-filtros" role="group" aria-label="Filtrar">
            {FILTROS.map(([k, t]) => <button key={k} type="button" aria-pressed={filtro === k} onClick={() => setFiltro(k)}>{t}</button>)}
          </div>
        </div>
        <div className="inbox-itens">
          {lista.length === 0 && <p className="sm sec inbox-nada">{itens.length === 0 ? "Nenhuma conversa ainda." : "Nada por aqui com esse filtro."}</p>}
          {lista.map((i) => (
            <Link key={i.id} href={`/conversas/${i.id}`} className="cv" aria-current={i.id === abertaId ? "page" : undefined} data-nova={i.naoLidas > 0 ? "sim" : undefined}>
              <Avatar nome={i.nome} />
              <span className="cv-meio">
                <span className="cv-linha"><span className="cv-nome">{i.nome}</span><span className="cv-hora">{i.quando}</span></span>
                <span className="cv-linha">
                  <span className="cv-previa">{i.previa}</span>
                  <span className="cv-fim">
                    {!i.botAtivo && <span className="cv-eq" title="Atendimento da equipe" role="img" aria-label="Com a equipe"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4 3.5-7 8-7s8 3 8 7" /></svg></span>}
                    {i.naoLidas > 0 && <span className="cont">{i.naoLidas}<span className="sr"> não lidas</span></span>}
                  </span>
                </span>
              </span>
            </Link>
          ))}
        </div>
      </aside>
      <section className="inbox-painel">{children}</section>
    </div>
  );
}
