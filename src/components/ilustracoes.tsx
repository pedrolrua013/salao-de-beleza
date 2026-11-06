// Ilustrações do sistema: traço e cores do design system, sem imagens externas.
// Tesoura aberta: duas argolas embaixo e as lâminas cruzando no meio.
const TESOURA = (
  <g fill="none" stroke="currentColor" strokeWidth="5" strokeLinecap="round">
    <circle cx="18" cy="48" r="8" /><circle cx="46" cy="48" r="8" />
    <path d="M23 42L50 8M41 42L14 8" />
  </g>
);

export function Tesoura({ className = "" }: { className?: string }) {
  return <svg className={className} viewBox="0 0 64 64" aria-hidden="true">{TESOURA}</svg>;
}

export function Brilho({ className = "" }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1l2.2 8.8L23 12l-8.8 2.2L12 23l-2.2-8.8L1 12l8.8-2.2z" fill="currentColor" /></svg>
  );
}

type Tipo = "tesoura" | "agenda" | "conversa" | "pessoas";

const CENAS: Record<Tipo, React.ReactNode> = {
  tesoura: (
    <>
      <circle cx="60" cy="60" r="46" className="il-fundo" />
      <g className="il-flutua il-brand-traco" transform="translate(28 26) scale(.64)">{TESOURA}</g>
      <path className="il-brilho il-b1" d="M94 28l1.8 5.6L101 35.4l-5.2 1.8L94 43l-1.8-5.8L87 35.4l5.2-1.8z" />
      <path className="il-brilho il-b2" d="M24 82l1.2 3.8 3.8 1.2-3.8 1.2L24 92l-1.2-3.8L19 87l3.8-1.2z" />
    </>
  ),
  agenda: (
    <>
      <circle cx="60" cy="60" r="46" className="il-fundo" />
      <g className="il-flutua">
        <rect x="30" y="34" width="60" height="52" rx="9" className="il-card" />
        <path d="M30 46a9 9 0 0 1 9-9h42a9 9 0 0 1 9 9v2H30z" className="il-brand" />
        <rect x="42" y="28" width="5" height="12" rx="2.5" className="il-ink" /><rect x="73" y="28" width="5" height="12" rx="2.5" className="il-ink" />
        <rect x="40" y="58" width="12" height="9" rx="3" className="il-fundo" /><rect x="58" y="58" width="12" height="9" rx="3" className="il-fundo" />
        <rect x="40" y="72" width="12" height="9" rx="3" className="il-fundo" /><rect x="58" y="72" width="12" height="9" rx="3" className="il-acento" />
              </g>
      <path className="il-brilho il-b1" d="M96 30l1.8 5.6L103 37.4l-5.2 1.8L96 45l-1.8-5.8L89 37.4l5.2-1.8z" />
    </>
  ),
  conversa: (
    <>
      <circle cx="60" cy="60" r="46" className="il-fundo" />
      <g className="il-flutua">
        <path d="M36 38h40a8 8 0 0 1 8 8v18a8 8 0 0 1-8 8H58l-10 9v-9h-12a8 8 0 0 1-8-8V46a8 8 0 0 1 8-8z" className="il-brand" />
        <circle cx="45" cy="55" r="3.4" fill="#fff" className="il-ponto p1" /><circle cx="56" cy="55" r="3.4" fill="#fff" className="il-ponto p2" /><circle cx="67" cy="55" r="3.4" fill="#fff" className="il-ponto p3" />
        <circle cx="88" cy="34" r="8" className="il-acento" />
      </g>
    </>
  ),
  pessoas: (
    <>
      <circle cx="60" cy="60" r="46" className="il-fundo" />
      <g className="il-flutua">
        <circle cx="60" cy="48" r="13" className="il-brand" />
        <path d="M34 88c0-14 11-24 26-24s26 10 26 24z" className="il-brand" />
        <circle cx="90" cy="40" r="7" className="il-acento" />
      </g>
      <path className="il-brilho il-b2" d="M26 40l1.6 5L32.6 46.6l-5 1.6L26 53.2l-1.6-5L19.4 46.6l5-1.6z" />
    </>
  ),
};

/** Estado vazio com ilustração e uma frase. O texto vem como filhos, para poder ter link. */
export function Vazio({ tipo = "tesoura", children }: { tipo?: Tipo; children: React.ReactNode }) {
  return (
    <div className="vazio">
      <svg className="il" viewBox="0 0 120 120" aria-hidden="true">{CENAS[tipo]}</svg>
      <p>{children}</p>
    </div>
  );
}
