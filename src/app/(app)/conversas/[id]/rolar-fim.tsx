"use client";
import { useEffect, useRef } from "react";

/** Leva a lista de mensagens para o fim ao abrir e quando chega mensagem nova (sem puxar quem está lendo o histórico). */
export function RolarFim({ total, children }: { total: number; children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const primeira = useRef(true);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const perto = el.scrollHeight - el.scrollTop - el.clientHeight < 160;
    if (primeira.current || perto) el.scrollTo({ top: el.scrollHeight, behavior: primeira.current ? "auto" : "smooth" });
    primeira.current = false;
  }, [total]);
  return <div className="chat" ref={ref} aria-label="Mensagens" role="log">{children}</div>;
}
