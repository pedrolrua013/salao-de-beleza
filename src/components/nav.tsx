"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { pode, type Permissao } from "@/lib/permissoes";
import type { Papel } from "@/lib/types";

const ICONES: Record<string, React.ReactNode> = {
  "/hoje": <><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.900l1.4 1.400M17.7 17.700l1.4 1.400M4.9 19.100l1.4-1.400M17.7 6.300l1.4-1.4" /></>,
  "/painel": <><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" /></>,
  "/relatorios": <><rect x="4" y="3" width="16" height="18" rx="2.5" /><path d="M8 8h8M8 12h8M8 16h5" /></>,
  "/agenda": <><rect x="3" y="5" width="18" height="16" rx="3" /><path d="M3 10h18M8 3v4M16 3v4" /></>,
  "/fila": <><circle cx="7" cy="7" r="3" /><circle cx="17" cy="7" r="3" /><path d="M2 20c0-3 2.200-5 5-5s5 2 5 5M12 20c0-3 2.200-5 5-5s5 2 5 5" /></>,
  "/divulgar": <><path d="M3 11v2a1 1 0 0 0 1 1h2l5 4V6L6 10H4a1 1 0 0 0-1 1z" /><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13" /></>,
  "/conversas": <path d="M5 5h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-6l-4 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />,
  "/caixa": <><rect x="3" y="6" width="18" height="13" rx="2.5" /><path d="M3 10h18M7 15h4" /></>,
  "/comissoes": <><circle cx="12" cy="12" r="9" /><path d="M15 9.5c-.5-1-1.6-1.5-3-1.5-1.7 0-3 .8-3 2s1.3 1.7 3 2 3 .9 3 2.1-1.3 1.9-3 1.9c-1.4 0-2.6-.6-3-1.6M12 6.5v11" /></>,
  "/extrato": <><circle cx="12" cy="12" r="9" /><path d="M15 9.5c-.5-1-1.6-1.5-3-1.5-1.7 0-3 .8-3 2s1.3 1.7 3 2 3 .9 3 2.1-1.3 1.9-3 1.9c-1.4 0-2.6-.6-3-1.6M12 6.5v11" /></>,
  "/estoque": <><path d="M3 7l9-4 9 4-9 4-9-4z" /><path d="M3 7v10l9 4 9-4V7M12 11v10" /></>,
  "/clientes": <><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6M16 4.500a3.5 3.5 0 0 1 0 7M18 14.300c2 .7 3.5 2.5 3.5 5.7" /></>,
  "/catalogos": <><path d="M4 6h16M4 12h16M4 18h10" /></>,
  "/ajuda": <><circle cx="12" cy="12" r="9" /><path d="M9.500 9.500a2.500 2.500 0 1 1 3.500 2.300c-.7.400-1 .9-1 1.700M12 17h.01" /></>,
  "/configuracoes": <><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.800l.1.1a2 2 0 1 1-2.8 2.800l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.500V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.800l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.800l-.1-.1a2 2 0 1 1 2.8-2.800l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.500V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.800l-.1.100a1.7 1.7 0 0 0-.3 1.800V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" /></>,
};

const ITENS: { href: string; texto: string; papeis?: string[]; perm?: Permissao }[] = [
  { href: "/hoje", texto: "Hoje" },
  { href: "/painel", texto: "Painel", perm: "painel" },
  { href: "/relatorios", texto: "Relatórios", perm: "painel" },
  { href: "/agenda", texto: "Agenda" },
  { href: "/fila", texto: "Fila" },
  { href: "/caixa", texto: "Caixa" },
  { href: "/comissoes", texto: "Comissões", perm: "comissoes" },
  { href: "/extrato", texto: "Meu extrato", papeis: ["profissional"] },
  { href: "/estoque", texto: "Estoque", perm: "estoque" },
  { href: "/conversas", texto: "Conversas" },
  { href: "/divulgar", texto: "Divulgar", perm: "divulgar" },
  { href: "/clientes", texto: "Clientes" },
  { href: "/catalogos", texto: "Catálogos" },
  { href: "/configuracoes", texto: "Salão" },
  { href: "/ajuda", texto: "Ajuda" },
];

export function Nav({ naoLidas = 0, papel = "admin", permissoes = null }: { naoLidas?: number; papel?: string; permissoes?: Record<string, unknown> | null }) {
  const path = usePathname();
  return (
    <nav className="nav" aria-label="Principal">
      {ITENS.filter((i) => (!i.papeis || i.papeis.includes(papel)) && (!i.perm || pode({ papel: papel as Papel, permissoes }, i.perm))).map((i) => (
        <Link key={i.href} href={i.href} aria-current={path.startsWith(i.href) ? "page" : undefined}><svg className="ni" viewBox="0 0 24 24" aria-hidden="true">{ICONES[i.href]}</svg><span>{i.texto}</span>{i.href === "/conversas" && naoLidas > 0 && <span className="cont">{naoLidas > 99 ? "99+" : naoLidas}<span className="sr"> mensagens não lidas</span></span>}</Link>
      ))}
    </nav>
  );
}
