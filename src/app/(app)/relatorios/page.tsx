import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { pode } from "@/lib/permissoes";
import { FORMAS, reais, type Forma } from "@/lib/dinheiro";
import { dataBR } from "@/lib/format";
import { dataLocal, somarDias } from "@/lib/slots";
import { CampoData } from "@/components/campo-data";

export const metadata = { title: "Relatórios" };

type R = {
  formas: Record<string, number>;
  servicos: { nome: string; qtd: number; valor: number }[];
  produtos: { nome: string; qtd: number; valor: number; custo: number }[];
  profissionais: { nome: string; atendimentos: number; faturamento: number; clientes: number; faltas: number; cancelados: number }[];
  por_hora: Record<string, number>;
  clientes: { novas: number; voltaram: number };
  previsao: { realizado_mes: number; agendado_mes: number; semanas: { semana: string; valor: number; horarios: number }[] };
};

/** Relatórios do período e a previsão de faturamento com base no que já está marcado. */
export default async function Relatorios({ searchParams }: { searchParams: Promise<{ de?: string; ate?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "painel")) redirect("/hoje");
  const q = await searchParams;
  const hoje = dataLocal(new Date(), salao.fuso);
  const de = q.de && /^\d{4}-\d{2}-\d{2}$/.test(q.de) ? q.de : `${hoje.slice(0, 8)}01`;
  const ate = q.ate && /^\d{4}-\d{2}-\d{2}$/.test(q.ate) ? q.ate : hoje;
  const { data, error } = await supabase.rpc("relatorios", { p_inicio: de, p_fim: ate });
  if (error || !data) return <div className="stack-lg"><h1>Relatórios</h1><p>Não foi possível carregar os relatórios.</p></div>;
  const r = data as R;
  const { data: bz } = await supabase.rpc("bairros_clientes");
  const bairros = bz as { com_endereco: number; total: number; bairros: { bairro: string; cidade: string | null; clientes: number }[] } | null;
  const totalFormas = Object.values(r.formas).reduce((a, b) => a + b, 0);
  const maxHora = Math.max(1, ...Object.values(r.por_hora));
  const horas = Object.keys(r.por_hora).map(Number).sort((a, b) => a - b);
  const previsaoMes = r.previsao.realizado_mes + r.previsao.agendado_mes;
  const pctBarra = (v: number, max: number) => `${Math.max(2, Math.round((v / Math.max(1, max)) * 100))}%`;
  return (
    <div className="stack-lg">
      <h1>Relatórios</h1>
      <form className="row" action="/relatorios" style={{ alignItems: "flex-end" }}>
        <div className="field"><label htmlFor="rde">De</label><CampoData id="rde" name="de" defaultValue={de} /></div>
        <div className="field"><label htmlFor="rate">Até</label><CampoData id="rate" name="ate" defaultValue={ate} /></div>
        <button className="btn sec" type="submit">Ver</button>
      </form>

      <section className="card stack">
        <h2>Previsão de faturamento</h2>
        <div className="kpis">
          <div className="kpi"><span className="cap sec">Já entrou este mês</span><strong>{reais(r.previsao.realizado_mes)}</strong></div>
          <div className="kpi"><span className="cap sec">Marcado até o fim do mês</span><strong>{reais(r.previsao.agendado_mes)}</strong></div>
          <div className="kpi destaque"><span className="cap">Previsão do mês</span><strong>{reais(previsaoMes)}</strong><span className="cap">se todos os marcados vierem</span></div>
        </div>
        {r.previsao.semanas.length > 0 && (
          <table className="tab"><thead><tr><th>Semana de</th><th className="num">Horários marcados</th><th className="num">Valor previsto</th></tr></thead>
            <tbody>{r.previsao.semanas.map((s) => <tr key={s.semana}><td>{dataBR(s.semana)}</td><td className="num">{s.horarios}</td><td className="num">{reais(Number(s.valor))}</td></tr>)}</tbody></table>
        )}
        <p className="cap muted" style={{ margin: 0 }}>A previsão usa o preço de cada horário marcado (com tamanho, profissional e promoção). Encaixes e vendas de produto entram quando acontecem.</p>
      </section>

      <section className="card stack">
        <h2>Por profissional</h2>
        <div className="scroll"><table className="tab">
          <thead><tr><th>Profissional</th><th className="num">Atendimentos</th><th className="num">Faturamento</th><th className="num">Ticket por cliente</th><th className="num">Faltas</th><th className="num">Cancelados</th></tr></thead>
          <tbody>{r.profissionais.map((p) => (
            <tr key={p.nome}><td>{p.nome}</td><td className="num">{p.atendimentos}</td><td className="num">{reais(Number(p.faturamento))}</td>
              <td className="num">{p.clientes ? reais(Math.round(Number(p.faturamento) / p.clientes)) : "—"}</td><td className="num">{p.faltas}</td><td className="num">{p.cancelados}</td></tr>
          ))}</tbody>
        </table></div>
      </section>

      <div className="grid2">
        <section className="card stack">
          <h2>Formas de pagamento</h2>
          {totalFormas === 0 ? <p className="sm sec">Nada no período.</p> : (
            <div className="stack" style={{ gap: 8 }}>{Object.entries(r.formas).sort((a, b) => b[1] - a[1]).map(([f, v]) => (
              <div key={f} className="rel-barra"><span>{FORMAS[f as Forma] ?? f}</span><i style={{ width: pctBarra(v, totalFormas) }} /><strong>{reais(v)}</strong></div>
            ))}</div>
          )}
        </section>
        <section className="card stack">
          <h2>Clientes no período</h2>
          <div className="kpis">
            <div className="kpi"><span className="cap sec">Primeira visita</span><strong>{r.clientes.novas}</strong></div>
            <div className="kpi"><span className="cap sec">Voltaram</span><strong>{r.clientes.voltaram}</strong></div>
          </div>
        </section>
      </div>

      <section className="card stack">
        <h2>De onde vêm suas clientes</h2>
        {!bairros || bairros.bairros.length === 0 ? <p className="sm sec">Coloque o CEP no cadastro das clientes para ver os bairros de onde elas vêm.</p> : (
          <>
            <div className="stack" style={{ gap: 8 }}>{bairros.bairros.map((b) => (
              <div key={`${b.bairro}-${b.cidade}`} className="rel-barra"><span>{b.bairro}{b.cidade ? <span className="cap sec"> · {b.cidade}</span> : null}</span><i style={{ width: pctBarra(b.clientes, bairros.bairros[0].clientes) }} /><strong>{b.clientes}</strong></div>
            ))}</div>
            <p className="cap muted" style={{ margin: 0 }}>{bairros.com_endereco} de {bairros.total} clientes têm endereço no cadastro. Use para escolher onde divulgar.</p>
          </>
        )}
      </section>

      <section className="card stack">
        <h2>Horários mais procurados</h2>
        {horas.length === 0 ? <p className="sm sec">Nada no período.</p> : (
          <div className="rel-horas">{horas.map((h) => (
            <div key={h} className="rel-hora"><i style={{ height: pctBarra(r.por_hora[h], maxHora) }} title={`${r.por_hora[h]} horários`} /><span>{h}h</span></div>
          ))}</div>
        )}
      </section>

      <div className="grid2">
        <section className="card stack">
          <h2>Serviços</h2>
          {r.servicos.length === 0 ? <p className="sm sec">Nada no período.</p> : (
            <table className="tab"><thead><tr><th>Serviço</th><th className="num">Qtd.</th><th className="num">Valor</th></tr></thead>
              <tbody>{r.servicos.slice(0, 20).map((s) => <tr key={s.nome}><td>{s.nome}</td><td className="num">{s.qtd}</td><td className="num">{reais(Number(s.valor))}</td></tr>)}</tbody></table>
          )}
        </section>
        <section className="card stack">
          <h2>Produtos vendidos</h2>
          {r.produtos.length === 0 ? <p className="sm sec">Nada no período.</p> : (
            <table className="tab"><thead><tr><th>Produto</th><th className="num">Qtd.</th><th className="num">Valor</th><th className="num">Lucro</th></tr></thead>
              <tbody>{r.produtos.slice(0, 20).map((s) => <tr key={s.nome}><td>{s.nome}</td><td className="num">{s.qtd}</td><td className="num">{reais(Number(s.valor))}</td><td className="num">{reais(Number(s.valor) - Number(s.custo))}</td></tr>)}</tbody></table>
          )}
        </section>
      </div>
      <p className="cap muted">Período: {dataBR(de)} a {dataBR(ate)}. Valores de comandas fechadas. Para comparar com o período anterior, veja o Painel. Últimos 30 dias: <a href={`/relatorios?de=${somarDias(hoje, -29)}&ate=${hoje}`}>ver</a>.</p>
    </div>
  );
}
