import Link from "next/link";
import { notFound } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { reais } from "@/lib/dinheiro";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { CampoTelefone } from "@/components/campo-telefone";
import { comprarOnline } from "./actions";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const db = clienteAdmin();
  const { data } = db ? await db.from("saloes").select("nome").eq("slug", slug).maybeSingle() : { data: null };
  return { title: data ? `Vale-presente e pacotes · ${data.nome}` : "Comprar" };
}

/** Vale-presente e pacotes vendidos pelo link, pagos por Pix. */
export default async function Comprar({ params, searchParams }: { params: Promise<{ slug: string }>; searchParams: Promise<{ pacote?: string }> }) {
  const { slug } = await params;
  const { pacote } = await searchParams;
  const db = clienteAdmin();
  if (!db) notFound();
  const { data: s } = await db.from("saloes").select("id, nome, venda_online").eq("slug", slug).maybeSingle();
  if (!s) notFound();
  if (!s.venda_online) return <main className="pub"><section className="card"><p>Este salão ainda não vende pelo link. Fale com ele pelo WhatsApp.</p></section></main>;
  const { data: pks } = await db.from("pacotes").select("id, nome, tipo, preco_centavos, validade_dias, pacote_itens(quantidade, servicos(nome))").eq("salao_id", s.id).eq("ativo", true).eq("online", true).order("preco_centavos");
  const pacotes = (pks ?? []) as unknown as { id: string; nome: string; tipo: string; preco_centavos: number; validade_dias: number; pacote_itens: { quantidade: number; servicos: { nome: string } | null }[] }[];
  const escolhido = pacotes.find((p) => p.id === pacote);
  return (
    <main className="pub">
      <header className="pub-cab"><img src="/icone.png" alt="" width={40} height={40} /><div><h1>{s.nome}</h1><p className="cap sec">Vale-presente e pacotes</p></div></header>
      {escolhido ? (
        <section className="card stack">
          <h2>{escolhido.nome}</h2>
          <div className="pub-resumo"><strong>{reais(escolhido.preco_centavos)}</strong>
            <span>{escolhido.pacote_itens.map((i) => `${i.quantidade}× ${i.servicos?.nome ?? "serviço"}`).join(" + ")}</span>
            <span className="cap">{escolhido.tipo === "clube" ? "Renova todo mês" : `Vale ${escolhido.validade_dias} dias depois de liberado`}</span></div>
          <AcaoForm action={comprarOnline}>
            <input type="hidden" name="slug" value={slug} /><input type="hidden" name="tipo" value="pacote" /><input type="hidden" name="pacote" value={escolhido.id} />
            <div className="field"><label htmlFor="cn">Seu nome</label><input id="cn" name="nome" required minLength={2} maxLength={120} autoComplete="name" /></div>
            <div className="field"><label htmlFor="ct">Celular com DDD</label><CampoTelefone id="ct" name="telefone" required autoComplete="tel" /></div>
            <p className="cap muted" style={{ margin: 0 }}>Depois do Pix, o salão confere e libera o pacote no seu cadastro.</p>
            <Enviar className="btn pub-btn">Pagar com Pix</Enviar>
          </AcaoForm>
          <Link className="btn ghost" href={`/s/${slug}/comprar`}>← Voltar</Link>
        </section>
      ) : (
        <>
          <section className="card stack">
            <h2>Vale-presente</h2>
            <p className="sm sec">Um presente para usar em qualquer serviço ou produto do salão. Vale por 1 ano.</p>
            <AcaoForm action={comprarOnline}>
              <input type="hidden" name="slug" value={slug} /><input type="hidden" name="tipo" value="vale" />
              <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Valor</span>
                <div className="pub-chips">{[5000, 10000, 15000, 20000, 30000].map((v, i) => (
                  <label key={v} className="pub-chip"><input type="radio" name="valor" value={v / 100} defaultChecked={i === 1} style={{ marginRight: 6 }} />{reais(v)}</label>
                ))}</div></div>
              <div className="grid2">
                <div className="field"><label htmlFor="vp">Para quem é</label><input id="vp" name="para" required minLength={2} maxLength={80} /></div>
                <div className="field"><label htmlFor="vm">Mensagem (opcional)</label><input id="vm" name="mensagem" maxLength={200} placeholder="Feliz aniversário!" /></div>
                <div className="field"><label htmlFor="vn">Seu nome</label><input id="vn" name="nome" required minLength={2} maxLength={120} autoComplete="name" /></div>
                <div className="field"><label htmlFor="vt">Seu celular com DDD</label><CampoTelefone id="vt" name="telefone" required autoComplete="tel" /></div>
              </div>
              <p className="cap muted" style={{ margin: 0 }}>Depois do Pix, o salão confere e manda o código do vale para você.</p>
              <Enviar className="btn pub-btn">Pagar com Pix</Enviar>
            </AcaoForm>
          </section>
          {pacotes.length > 0 && (
            <section className="card stack">
              <h2>Pacotes</h2>
              <div className="pub-lista">{pacotes.map((p) => (
                <Link key={p.id} className="pub-op" href={`/s/${slug}/comprar?pacote=${p.id}`}>
                  <span><strong>{p.nome}</strong><span className="cap sec">{p.pacote_itens.map((i) => `${i.quantidade}× ${i.servicos?.nome ?? "serviço"}`).join(" + ")}</span></span>
                  <span className="pub-preco">{reais(p.preco_centavos)}</span>
                </Link>
              ))}</div>
            </section>
          )}
        </>
      )}
      <Link className="btn ghost" href={`/s/${slug}`}>Agendar um horário</Link>
    </main>
  );
}
