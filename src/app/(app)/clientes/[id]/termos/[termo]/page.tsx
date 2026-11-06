import Link from "next/link";
import { notFound } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { dataCurta } from "@/lib/format";
import { Imprimir } from "@/app/(app)/comissoes/parceria/imprimir";

export const metadata = { title: "Termo assinado" };

const SIM_NAO: Record<string, string> = { sim: "Sim", nao: "Não", ns: "Não sei" };

/** O termo como foi assinado: texto, respostas, assinatura e os dados que provam quem, quando e de onde. */
export default async function TermoAssinado({ params }: { params: Promise<{ id: string; termo: string }> }) {
  const { id, termo } = await params;
  const { supabase, salao } = await exigirMembro();
  const { data: t } = await supabase.from("termos_assinados").select("*, clientes(nome)").eq("id", termo).eq("cliente_id", id).maybeSingle();
  if (!t || !t.assinado_em) notFound();
  const r = (t.respostas ?? {}) as Record<string, string | undefined>;
  const hora = new Intl.DateTimeFormat("pt-BR", { timeZone: salao.fuso, dateStyle: "long", timeStyle: "medium" }).format(new Date(t.assinado_em));
  return (
    <div className="stack-lg termo-doc">
      <div className="row between nao-imprimir"><Link className="btn ghost sm" href={`/clientes/${id}#termos`}>← Voltar</Link><Imprimir /></div>
      <section className="card stack">
        <p className="cap sec">{salao.nome}</p>
        <h1>{t.titulo}</h1>
        <div className="termo-texto">{String(t.texto).split(/\n{2,}/).map((p, i) => <p key={i}>{p}</p>)}</div>
        {t.tipo === "quimica" && (r.alergia || r.gestante || r.teste) && (
          <dl className="ficha-previa">
            {r.alergia && <div><dt className="cap sec">Alergia ou reação a produto</dt><dd>{SIM_NAO[r.alergia] ?? r.alergia}{r.alergia_qual ? `: ${r.alergia_qual}` : ""}</dd></div>}
            {r.gestante && <div><dt className="cap sec">Grávida ou amamentando</dt><dd>{SIM_NAO[r.gestante] ?? r.gestante}</dd></div>}
            {r.teste && <div><dt className="cap sec">Fez teste de mecha ou alergia</dt><dd>{SIM_NAO[r.teste] ?? r.teste}</dd></div>}
          </dl>
        )}
        <div className="termo-assinatura">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={t.assinatura} alt={`Assinatura de ${t.nome_assinado}`} />
          <p><strong>{t.nome_assinado}</strong>{t.documento ? ` · CPF ${String(t.documento).replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4")}` : ""}</p>
        </div>
        <p className="cap muted">Assinado eletronicamente em {hora}{t.ip ? `, do endereço ${t.ip}` : ""}. Aparelho: {t.aparelho || "não informado"}. Link criado em {dataCurta(t.criado_em, salao.fuso)}. Código do texto (SHA-256): {t.texto_hash}</p>
      </section>
    </div>
  );
}
