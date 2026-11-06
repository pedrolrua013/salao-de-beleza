import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { ListaSumidas, type Sumida } from "@/components/lista-sumidas";

export const metadata = { title: "Clientes para chamar de volta" };

export default async function Sumidas() {
  const { supabase, membro, salao } = await exigirMembro();
  if (membro.papel === "profissional") redirect("/clientes");
  const { data } = await supabase.rpc("clientes_sumidos", { p_limite: 200 });
  const lista = (data ?? []) as Sumida[];
  return (
    <div className="stack-lg">
      <div><h1>Clientes para chamar de volta</h1><p className="sec">Passaram de 1,5 vez o tempo que costumam levar para voltar (ou mais de 60 dias, para quem veio uma vez) e não têm horário marcado. Quem pediu PARAR no WhatsApp não aparece.</p></div>
      <section className="card">{lista.length === 0 ? <p>Ninguém sumido agora.</p> : <ListaSumidas lista={lista} salao={salao.nome} slug={salao.slug} />}</section>
    </div>
  );
}
