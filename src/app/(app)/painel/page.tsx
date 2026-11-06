import Link from "next/link";
import { MetasDoMes } from "@/components/metas";
import { pode } from "@/lib/permissoes";
import { CampoData } from "@/components/campo-data";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { reais } from "@/lib/dinheiro";
import { dataLocal, somarDias, zonedToUtc } from "@/lib/slots";
import { dataBR } from "@/lib/format";
import { ListaSumidas } from "@/components/lista-sumidas";

export const metadata = { title: "Painel" };

type P = {
  receita: number; servicos: number; produtos: number; gorjetas: number; comandas: number; atendimentos: number; faltas: number; cancelados: number;
  clientes_atendidos: number; clientes_retorno: number; clientes_novos: number; origem_novos: Record<string, number>;
  rebook: { sim: number; total: number }; ocupacao: { disponivel: number; ocupado: number }; online: number; whatsapp: number;
  profissionais: { id: string; nome: string; disponivel: number; ocupado: number; receita: number; atendimentos: number; comissao: number }[];
  por_dia: Record<string, number>; top_servicos: { nome: string; n: number; v: number }[];
};
const ORIGEM: Record<string, string> = { indicacao: "Indicação", instagram: "Instagram", google: "Google", whatsapp: "WhatsApp", passante: "Passou na frente", facebook: "Facebook", tiktok: "TikTok", outro: "Outro / link", nao_informado: "Não informado" };
const pct = (a: number, b: number) => (b > 0 ? Math.round((a / b) * 100) : null);
const fmtPct = (v: number | null) => (v === null ? "—" : `${v}%`);

function Variacao({ atual, antes }: { atual: number; antes: number }) {
  if (!antes) return null;
  const v = Math.round(((atual - antes) / antes) * 100);
  return <span className={`cap ${v >= 0 ? "sobe" : "desce"}`}>{v >= 0 ? "▲" : "▼"} {Math.abs(v)}% vs período anterior</span>;
}

/** Os números que mostram se o salão está saudável, comparados com o período anterior de mesmo tamanho. */
export default async function Painel({ searchParams }: { searchParams: Promise<{ de?: string; ate?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "painel")) redirect("/hoje");
  const q = await searchParams;
  const hoje = dataLocal(new Date(), salao.fuso);
  const de = q.de && /^\d{4}-\d{2}-\d{2}$/.test(q.de) ? q.de : `${hoje.slice(0, 8)}01`;
  const ate = q.ate && /^\d{4}-\d{2}-\d{2}$/.test(q.ate) ? q.ate : hoje;
  const dias = Math.round((Date.parse(ate) - Date.parse(de)) / 86_400_000) + 1;
  const [{ data: a }, { data: b }, { data: sumidas }, { data: nps }, { data: baixas }] = await Promise.all([
    supabase.rpc("painel", { p_inicio: de, p_fim: ate }),
    supabase.rpc("painel", { p_inicio: somarDias(de, -dias), p_fim: somarDias(de, -1) }),
    supabase.rpc("clientes_sumidos", { p_limite: 12 }),
    supabase.rpc("nps", { p_inicio: de, p_fim: ate }),
    supabase.from("avaliacoes").select("id, nota, comentario, respondida_em, profissionais, clientes(id, nome, telefone)").lte("nota", 6).gte("respondida_em", zonedToUtc(de, "00:00", salao.fuso).toISOString()).lt("respondida_em", zonedToUtc(somarDias(ate, 1), "00:00", salao.fuso).toISOString()).order("respondida_em", { ascending: false }).limit(10),
  ]);
  const n = (nps ?? null) as { respostas: number; nps: number | null; media: number | null; promotores: number; detratores: number } | null;
  if (!a) return <div className="stack-lg"><h1>Painel</h1><p>Não foi possível carregar o painel.</p></div>;
  const p = a as P, ant = (b ?? null) as P | null;
  const ticket = p.comandas ? Math.round(p.receita / p.comandas) : 0;
  const ticketAnt = ant?.comandas ? Math.round(ant.receita / ant.comandas) : 0;
  const ocup = pct(p.ocupacao.ocupado, p.ocupacao.disponivel);
  const faltas = pct(p.faltas, p.atendimentos + p.faltas);
  const retorno = pct(p.clientes_retorno, p.clientes_atendidos);
  const rebook = pct(p.rebook.sim, p.rebook.total);
  const varejo = pct(p.produtos, p.servicos + p.produtos);
  const maxDia = Math.max(1, ...Object.values(p.por_dia));
  const diasLista = Array.from({ length: Math.min(dias, 62) }, (_, i) => somarDias(de, i));
  const atalhos = [
    ["Este mês", `${hoje.slice(0, 8)}01`, hoje],
    ["Últimos 7 dias", somarDias(hoje, -6), hoje],
    ["Últimos 30 dias", somarDias(hoje, -29), hoje],
  ] as const;
  return (
    <div className="stack-lg">
      <div className="row between">
        <h1>Painel</h1>
        <form className="row" style={{ gap: 8 }}>
          <CampoData name="de" defaultValue={de} ariaLabel="De" required /><CampoData name="ate" defaultValue={ate} ariaLabel="Até" required />
          <button className="btn sec sm" type="submit">Ver</button>
        </form>
      </div>
      <div className="seg" role="group" aria-label="Períodos">{atalhos.map(([t, d1, d2]) => <Link key={t} href={`/painel?de=${d1}&ate=${d2}`} aria-current={d1 === de && d2 === ate ? "page" : undefined}>{t}</Link>)}</div>

      <div className="kpis">
        <div className="kpi destaque"><span className="cap">Faturamento</span><strong>{reais(p.receita)}</strong>{ant && <Variacao atual={p.receita} antes={ant.receita} />}</div>
        <div className="kpi"><span className="cap sec">Ticket médio</span><strong>{reais(ticket)}</strong>{ant && <Variacao atual={ticket} antes={ticketAnt} />}</div>
        <div className="kpi"><span className="cap sec">Atendimentos</span><strong>{p.atendimentos}</strong>{ant && <Variacao atual={p.atendimentos} antes={ant.atendimentos} />}</div>
        <div className="kpi"><span className="cap sec">Ocupação da agenda</span><strong>{fmtPct(ocup)}</strong><span className="cap muted">tempo de trabalho marcado</span></div>
      </div>
      <div className="kpis">
        <div className="kpi"><span className="cap sec">Saíram com retorno marcado</span><strong>{fmtPct(rebook)}</strong><span className="cap muted">meta de mercado: 60% ou mais</span></div>
        <div className="kpi"><span className="cap sec">Clientes que voltaram</span><strong>{fmtPct(retorno)}</strong><span className="cap muted">{p.clientes_retorno} de {p.clientes_atendidos}</span></div>
        <div className="kpi"><span className="cap sec">Faltas</span><strong>{fmtPct(faltas)}</strong><span className="cap muted">{p.faltas} faltas · {p.cancelados} cancelados</span></div>
        <div className="kpi"><span className="cap sec">Venda de produtos</span><strong>{fmtPct(varejo)}</strong><span className="cap muted">{reais(p.produtos)} do faturamento</span></div>
      </div>

      {n && n.respostas > 0 && (
        <section className="card stack">
          <div className="row between"><h2>O que as clientes acham</h2><span className="cap muted">{n.respostas} respostas</span></div>
          <div className="kpis">
            <div className="kpi"><span className="cap sec">NPS</span><strong>{n.nps}</strong><span className="cap muted">de −100 a 100; acima de 50 é muito bom</span></div>
            <div className="kpi"><span className="cap sec">Nota média</span><strong>{n.media}</strong></div>
            <div className="kpi"><span className="cap sec">Recomendam (9 e 10)</span><strong>{n.promotores}</strong></div>
            <div className="kpi"><span className="cap sec">Insatisfeitas (0 a 6)</span><strong>{n.detratores}</strong></div>
          </div>
          {(baixas ?? []).length > 0 && (
            <div className="list">
              {(baixas ?? []).map((x) => { const cl = x.clientes as unknown as { id: string; nome: string; telefone: string | null } | null; return (
                <div key={x.id} className="item"><span><Link className="t" href={`/clientes/${cl?.id}`}>{cl?.nome}</Link> <span className="bd no">nota {x.nota}</span> <span className="sm sec">{x.profissionais ? `· atendida por ${x.profissionais}` : ""}{x.comentario ? ` · “${x.comentario}”` : ""}</span></span>
                  {cl?.telefone && <a className="btn sec sm" href={`https://wa.me/55${cl.telefone}`} target="_blank" rel="noopener noreferrer">Falar com ela</a>}</div>
              ); })}
            </div>
          )}
        </section>
      )}

      <MetasDoMes supabase={supabase} hoje={hoje} nomes={new Map(p.profissionais.map((x) => [x.id, x.nome]))} />

      <section className="card stack">
        <h2>Faturamento por dia</h2>
        <div className="barras" role="img" aria-label="Faturamento por dia">
          {diasLista.map((d) => {
            const v = p.por_dia[d] ?? 0;
            return <div key={d} className="barra" title={`${dataBR(d)}: ${reais(v)}`}><i style={{ height: `${Math.round((v / maxDia) * 100)}%` }} /><span className="cap">{d.slice(8)}</span></div>;
          })}
        </div>
      </section>

      <section className="card stack">
        <h2>Por profissional</h2>
        <div className="scroll">
          <table className="tab">
            <thead><tr><th>Profissional</th><th className="num">Faturou</th><th className="num">Atendimentos</th><th className="num">Ticket</th><th className="num">Ocupação</th><th className="num">Comissão</th></tr></thead>
            <tbody>{p.profissionais.map((x) => (
              <tr key={x.id}><td><Link href={`/extrato?prof=${x.id}&de=${de}&ate=${ate}`}>{x.nome}</Link></td><td className="num">{reais(x.receita)}</td><td className="num">{x.atendimentos}</td>
                <td className="num">{x.atendimentos ? reais(Math.round(x.receita / x.atendimentos)) : "—"}</td><td className="num">{fmtPct(pct(x.ocupado, x.disponivel))}</td><td className="num">{reais(x.comissao)}</td></tr>
            ))}</tbody>
          </table>
        </div>
      </section>

      <div className="grid2">
        <section className="card stack">
          <h2>Serviços que mais faturam</h2>
          {p.top_servicos.length === 0 ? <p className="sm sec">Sem comandas no período.</p> : (
            <div className="list">{p.top_servicos.map((s) => <div key={s.nome} className="item"><span><span className="t">{s.nome}</span> <span className="sm sec">· {s.n}×</span></span><strong>{reais(s.v)}</strong></div>)}</div>
          )}
        </section>
        <section className="card stack">
          <h2>Clientes novos: {p.clientes_novos}</h2>
          <p className="sm sec">De onde vieram (cadastre a origem na ficha da cliente).</p>
          <div className="list">{Object.entries(p.origem_novos).sort((x, y) => y[1] - x[1]).map(([k, n]) => <div key={k} className="item"><span className="t">{ORIGEM[k] ?? k}</span><strong>{n}</strong></div>)}</div>
          <p className="cap muted">Marcados pelo link: {p.online} · pelo robô do WhatsApp: {p.whatsapp}</p>
        </section>
      </div>

      <section className="card stack">
        <div className="row between"><h2>Clientes para chamar de volta</h2><Link className="btn ghost sm" href="/clientes/sumidas">Ver todas</Link></div>
        <p className="sm sec">Passaram do tempo de costume e não têm horário marcado.</p>
        {(sumidas ?? []).length === 0 ? <p className="sm">Ninguém sumido. Ótimo sinal!</p> : <ListaSumidas lista={sumidas ?? []} salao={salao.nome} slug={salao.slug} />}
      </section>
    </div>
  );
}
