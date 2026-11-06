"use client";
import { useEffect, useRef } from "react";

/** Menu "⋯" com ações secundárias. Fecha ao clicar fora, ao apertar Esc e depois de escolher uma ação. */
export function MaisAcoes({ children, rotulo = "Mais ações" }: { children: React.ReactNode; rotulo?: string }) {
  const ref = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const fora = (e: Event) => { if (el.open && !el.contains(e.target as Node)) el.open = false; };
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape" && el.open) { el.open = false; el.querySelector("summary")?.focus(); } };
    document.addEventListener("pointerdown", fora);
    document.addEventListener("keydown", esc);
    return () => { document.removeEventListener("pointerdown", fora); document.removeEventListener("keydown", esc); };
  }, []);
  return (
    <details className="mais" ref={ref}>
      <summary className="btn ghost sm" aria-label={rotulo}>
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><circle cx="5" cy="12" r="1.8" fill="currentColor" /><circle cx="12" cy="12" r="1.8" fill="currentColor" /><circle cx="19" cy="12" r="1.8" fill="currentColor" /></svg>
      </summary>
      <div className="mais-menu">{children}</div>
    </details>
  );
}
