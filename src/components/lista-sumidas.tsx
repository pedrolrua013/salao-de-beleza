import Link from "next/link";
import { dataBR } from "@/lib/format";

export type Sumida = { cliente_id: string; nome: string; telefone: string | null; ultima: string; visitas: number; intervalo_dias: number | null; dias_sem_vir: number };

/** Clientes que passaram do tempo de voltar, com o atalho para chamar no WhatsApp já com o link de agendamento. */
export function ListaSumidas({ lista, salao, slug }: { lista: Sumida[]; salao: string; slug: string }) {
  const site = process.env.NEXT_PUBLIC_SITE_URL ?? "";
  return (
    <div className="list">
      {lista.map((c) => {
        const msg = `Oi, ${c.nome.split(" ")[0]}! Aqui é do ${salao}. Sentimos sua falta! Quer marcar um horário? ${site}/s/${slug}`;
        return (
          <div key={c.cliente_id} className="item">
            <span><Link className="t" href={`/clientes/${c.cliente_id}`}>{c.nome}</Link> <span className="sm sec">· última visita {dataBR(c.ultima)} · {c.dias_sem_vir} dias{c.intervalo_dias ? ` (costuma vir a cada ${c.intervalo_dias})` : ""}</span></span>
            {c.telefone && <a className="btn sec sm" href={`https://wa.me/55${c.telefone}?text=${encodeURIComponent(msg)}`} target="_blank" rel="noopener noreferrer">Chamar no WhatsApp</a>}
          </div>
        );
      })}
    </div>
  );
}
