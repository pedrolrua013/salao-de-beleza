import { notFound } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { reais } from "@/lib/dinheiro";
import { Imprimir } from "@/app/(app)/comissoes/parceria/imprimir";

export const metadata = { title: "Vale-presente" };

/** O vale para entregar: imprime ou salva em PDF e manda pelo WhatsApp. */
export default async function Vale({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, salao } = await exigirMembro();
  const { data: v } = await supabase.from("vales_presente").select("codigo, para, mensagem, valor_centavos, expira_em").eq("id", id).maybeSingle();
  if (!v) notFound();
  const ate = new Intl.DateTimeFormat("pt-BR", { timeZone: salao.fuso, day: "2-digit", month: "long", year: "numeric" }).format(new Date(v.expira_em));
  return (
    <div className="stack-lg">
      <div className="noprint"><Imprimir /></div>
      <article className="vale">
        <img src="/icone.png" alt="" width={56} height={56} />
        <p className="cap">Vale-presente</p>
        <h1>{salao.nome}</h1>
        <p className="vale-para">Para {v.para}</p>
        {v.mensagem && <p className="vale-msg">“{v.mensagem}”</p>}
        <p className="vale-valor">{reais(v.valor_centavos)}</p>
        <p className="vale-codigo">{v.codigo}</p>
        <p className="cap">Válido até {ate}. Apresente o código no salão.{salao.telefone ? ` Agende: ${salao.telefone}` : ""}</p>
      </article>
    </div>
  );
}
