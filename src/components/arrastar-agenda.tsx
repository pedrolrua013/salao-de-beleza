"use client";
import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { moverAgendamento } from "@/app/(app)/agenda/actions";

/** Arrastar um horário na grade para outra hora ou outro profissional (no computador). Encaixa de 5 em 5 minutos. */
export function ArrastarAgenda({ data, children }: { data: string; children: React.ReactNode }) {
  const router = useRouter();
  const [aviso, setAviso] = useState<{ erro?: string; ok?: string } | null>(null);
  const [movendo, iniciar] = useTransition();
  const arrastando = useRef<{ id: string; deslocY: number } | null>(null);

  const alvo = (e: React.DragEvent) => (e.target as HTMLElement).closest<HTMLElement>(".grade-corpo");

  return (
    <div
      onDragStart={(e) => {
        const bloco = (e.target as HTMLElement).closest<HTMLElement>(".gb[data-id]");
        if (!bloco) return;
        arrastando.current = { id: bloco.dataset.id!, deslocY: e.clientY - bloco.getBoundingClientRect().top };
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", bloco.dataset.id!);
      }}
      onDragOver={(e) => { if (arrastando.current && alvo(e)) { e.preventDefault(); e.dataTransfer.dropEffect = "move"; } }}
      onDrop={(e) => {
        const col = alvo(e), atual = arrastando.current;
        arrastando.current = null;
        if (!col || !atual) return;
        e.preventDefault();
        const pm = Number(col.dataset.pm), ini = Number(col.dataset.ini);
        const y = e.clientY - col.getBoundingClientRect().top - atual.deslocY;
        const min = Math.max(0, Math.min(1435, Math.round((ini + y / pm) / 5) * 5));
        const hora = `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;
        iniciar(async () => {
          const r = await moverAgendamento(atual.id, data, hora, col.dataset.prof!);
          setAviso(r.erro ? { erro: r.erro } : { ok: `Horário movido para ${hora.replace(":", "h")}.` });
          router.refresh();
        });
      }}
      onDragEnd={() => { arrastando.current = null; }}
      aria-busy={movendo}
    >
      {aviso && <p className={aviso.erro ? "err" : "okmsg"} role="status" style={{ marginBottom: 8 }}>{aviso.erro ?? aviso.ok}</p>}
      {children}
      <p className="cap muted" style={{ marginTop: 6 }}>No computador, arraste um horário para mudar a hora ou o profissional.</p>
    </div>
  );
}
