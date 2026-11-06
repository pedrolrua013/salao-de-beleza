"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

/** Recarrega os dados da página de tempos em tempos, só com a aba visível. */
export function Atualizar({ segundos = 8 }: { segundos?: number }) {
  const router = useRouter();
  useEffect(() => {
    const t = setInterval(() => { if (document.visibilityState === "visible") router.refresh(); }, segundos * 1000);
    return () => clearInterval(t);
  }, [router, segundos]);
  return null;
}
