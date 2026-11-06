import Link from "next/link";
import { notFound } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { reais } from "@/lib/dinheiro";
import { Copiar } from "@/app/s/[slug]/h/[token]/copiar";

export const dynamic = "force-dynamic";
export const metadata = { title: "Minha área", robots: { index: false } };

type Area = {
  nome: string; salao: string; slug: string; fuso: string; cashback: number; indicacao_credito: number; codigo: string | null; taxas: number;
  fidelidade: { pontos: number; nivel: string | null; bonus: number; proximo: string | null; faltam: number | null } | null;
  proximos: { token: string; inicio: string; servico: string; profissional: string; status: string }[];
  historico: { inicio: string; servico: string; profissional: string }[];
  pacotes: { nome: string; expira_em: string; saldos: { servico: string; resta: number }[] | null }[];
};

/** A área da cliente: sem senha, o link é o segredo (vale 6 meses). Ela vê os horários, remarca, e acompanha cashback, pacotes e pontos. */
export default async function MinhaArea({ params }: { params: Promise<{ slug: string; token: string }> }) {
  const { token } = await params;
  const db = clienteAdmin();
  if (!db || !/^[0-9a-f]{64}$/.test(token)) notFound();
  await db.rpc("area_cliente_preparar", { p_token: token });
  const { data } = await db.rpc("area_cliente", { p_token: token });
  if (!data) notFound();
  const a = data as Area;
  const quando = (iso: string) => new Intl.DateTimeFormat("pt-BR", { timeZone: a.fuso, weekday: "long", day: "2-digit", month: "long", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .format(new Date(iso)).replace(/^./, (c) => c.toUpperCase());
  const dia = (iso: string) => new Intl.DateTimeFormat("pt-BR", { timeZone: a.fuso, day: "2-digit", month: "2-digit", year: "numeric" }).format(new Date(iso));
  const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") ?? "";
  const linkIndicacao = a.codigo ? `${site}/s/${a.slug}?ind=${a.codigo}` : null;
  const f = a.fidelidade;
  return (
    <main className="pub">
      <header className="pub-cab"><img src="/icone.png" alt="" width={40} height={40} /><div><h1>{a.salao}</h1><p className="cap sec">Olá, {a.nome.split(" ")[0]}!</p></div></header>

      <section className="card stack">
        <div className="row between"><h2>Seus próximos horários</h2><Link className="btn sm" href={`/s/${a.slug}`}>Marcar outro</Link></div>
        {a.proximos.length === 0 ? <p className="sm sec">Nenhum horário marcado.</p> : (
          <div className="pub-lista">{a.proximos.map((p) => (
            <Link key={p.token} className="pub-op" href={`/s/${a.slug}/h/${p.token}`}>
              <span><strong>{p.servico}</strong><span className="cap sec">{quando(p.inicio)} · com {p.profissional}</span></span>
              <span className="cap">{p.status === "confirmado" ? "Confirmado" : "Ver, remarcar ou cancelar"}</span>
            </Link>
          ))}</div>
        )}
      </section>

      {(a.cashback > 0 || f || a.pacotes.length > 0 || a.taxas > 0) && (
        <section className="card stack">
          <h2>Seus benefícios</h2>
          <div className="kpis">
            {a.cashback > 0 && <div className="kpi"><span className="cap sec">Cashback para usar</span><strong>{reais(a.cashback)}</strong><span className="cap muted">desconta na próxima visita</span></div>}
            {f && <div className="kpi"><span className="cap sec">Fidelidade</span><strong>{f.nivel ?? `${f.pontos} pontos`}</strong>
              <span className="cap muted">{f.nivel ? `${f.pontos} pontos · ${f.bonus}% de cashback extra` : "1 ponto por real gasto"}{f.proximo ? ` · faltam ${f.faltam} para ${f.proximo}` : ""}</span></div>}
          </div>
          {a.pacotes.map((p) => (
            <div key={p.nome + p.expira_em} className="pub-resumo">
              <strong>{p.nome}</strong>
              <span>{(p.saldos ?? []).map((s) => `${s.servico}: ${s.resta} restante${s.resta === 1 ? "" : "s"}`).join(" · ")}</span>
              <span className="cap">Vale até {dia(p.expira_em)}</span>
            </div>
          ))}
          {a.taxas > 0 && <p className="aviso-preco">Há uma taxa de falta de {reais(a.taxas)} que entra na sua próxima visita.</p>}
        </section>
      )}

      {linkIndicacao && (
        <section className="card stack">
          <h2>Indique uma amiga</h2>
          <p className="sm sec">Quando ela marcar pelo seu link e vier pela primeira vez, você ganha {reais(a.indicacao_credito)} para usar no salão.</p>
          <div className="pub-link"><code>{linkIndicacao}</code></div>
          <div className="row" style={{ gap: 8 }}>
            <a className="btn" href={`https://wa.me/?text=${encodeURIComponent(`Olha esse salão que eu adoro, ${a.salao}! Marca por aqui: ${linkIndicacao}`)}`} target="_blank" rel="noopener">Enviar pelo WhatsApp</a>
            <Copiar texto={linkIndicacao} rotulo="Copiar link" />
          </div>
        </section>
      )}

      {a.historico.length > 0 && (
        <section className="card stack">
          <h2>Suas últimas visitas</h2>
          <div className="list">{a.historico.map((h, i) => (
            <div key={i} className="item"><span><span className="t">{h.servico}</span> <span className="sm sec">· {h.profissional}</span></span><span className="sm sec">{dia(h.inicio)}</span></div>
          ))}</div>
        </section>
      )}
      <p className="cap muted pub-rodape">Este link é só seu. Não compartilhe (para indicar, use o link de indicação acima).</p>
    </main>
  );
}
