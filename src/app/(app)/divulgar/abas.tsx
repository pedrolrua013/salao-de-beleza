import Link from "next/link";

const ABAS = [
  ["/divulgar", "Horários vazios e promoções"],
  ["/divulgar/campanhas", "Campanhas no WhatsApp"],
  ["/divulgar/vitrine", "Página do salão"],
] as const;

/** Cabeçalho comum das páginas de divulgação. */
export function AbasDivulgar({ atual }: { atual: (typeof ABAS)[number][0] }) {
  return (
    <div className="stack">
      <h1>Divulgar</h1>
      <nav className="seg abas" aria-label="Divulgar">
        {ABAS.map(([href, texto]) => <Link key={href} href={href} aria-current={href === atual ? "page" : undefined}>{texto}</Link>)}
      </nav>
    </div>
  );
}
