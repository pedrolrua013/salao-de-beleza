import { exigirMembro } from "@/lib/auth";
import { CampoData } from "@/components/campo-data";
import { Vazio } from "@/components/ilustracoes";
import { reais } from "@/lib/dinheiro";
import { dataLocal } from "@/lib/slots";
import { dataBR } from "@/lib/format";

export const metadata = { title: "Extrato" };

type Linha = { id: string; competencia: string; descricao: string; papel: string; bruto_centavos: number; taxa_centavos: number; custo_centavos: number; base_centavos: number; percentual: number; valor_centavos: number; fechamento_id: string | null };
const PAPEL: Record<string, string> = { profissional: "Serviço", assistente: "Assistente", vendedor: "Venda", gorjeta: "Gorjeta" };

/** O profissional vê, linha a linha, de onde vem cada real que vai receber. O administrador vê o de qualquer um. */
export default async function Extrato({ searchParams }: { searchParams: Promise<{ prof?: string; de?: string; ate?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  const q = await searchParams;
  const hoje = dataLocal(new Date(), salao.fuso);
  const de = q.de && /^\d{4}-\d{2}-\d{2}$/.test(q.de) ? q.de : `${hoje.slice(0, 8)}01`;
  const ate = q.ate && /^\d{4}-\d{2}-\d{2}$/.test(q.ate) ? q.ate : hoje;
  const prof = membro.papel === "admin" && q.prof ? q.prof : membro.user_id;
  const [{ data: m }, { data: ls }, { data: vs }, { data: fs }, { data: equipe }] = await Promise.all([
    supabase.from("membros").select("nome, vinculo").eq("user_id", prof).maybeSingle(),
    supabase.from("comissoes").select("*").eq("profissional_id", prof).gte("competencia", de).lte("competencia", ate).order("competencia", { ascending: false }),
    supabase.from("vales").select("id, valor_centavos, data, motivo, fechamento_id").eq("profissional_id", prof).is("fechamento_id", null),
    supabase.from("fechamentos_comissao").select("*").eq("profissional_id", prof).order("pago_em", { ascending: false }).limit(6),
    membro.papel === "admin" ? supabase.from("membros").select("user_id, nome").neq("papel", "recepcao").order("nome") : Promise.resolve({ data: [] }),
  ]);
  const linhas = (ls ?? []) as Linha[];
  const com = linhas.filter((l) => l.papel !== "gorjeta").reduce((s, l) => s + l.valor_centavos, 0);
  const gor = linhas.filter((l) => l.papel === "gorjeta").reduce((s, l) => s + l.valor_centavos, 0);
  const pendente = linhas.filter((l) => !l.fechamento_id).reduce((s, l) => s + l.valor_centavos, 0);
  const vales = (vs ?? []).reduce((s, v) => s + v.valor_centavos, 0);
  const atendidos = new Set(linhas.filter((l) => l.papel === "profissional").map((l) => l.id)).size;
  return (
    <div className="stack-lg">
      <div className="row between">
        <h1>{prof === membro.user_id ? "Meu extrato" : `Extrato de ${m?.nome ?? ""}`}</h1>
        <form className="row" style={{ gap: 8 }}>
          {membro.papel === "admin" && <select name="prof" defaultValue={prof} aria-label="Profissional">{(equipe ?? []).map((e) => <option key={e.user_id} value={e.user_id}>{e.nome}</option>)}</select>}
          <CampoData name="de" defaultValue={de} ariaLabel="De" required /><CampoData name="ate" defaultValue={ate} ariaLabel="Até" required />
          <button className="btn sec sm" type="submit">Ver</button>
        </form>
      </div>
      {m?.vinculo === "socio" && <p className="sm sec">Sócio não recebe comissão pelo sistema. Aqui aparecem só as gorjetas.</p>}
      <div className="kpis">
        <div className="kpi"><span className="cap sec">Comissões no período</span><strong>{reais(com)}</strong><span className="cap muted">{atendidos} serviços</span></div>
        <div className="kpi"><span className="cap sec">Gorjetas</span><strong>{reais(gor)}</strong></div>
        <div className="kpi"><span className="cap sec">Vales em aberto</span><strong>− {reais(vales)}</strong></div>
        <div className="kpi destaque"><span className="cap">A receber</span><strong>{reais(pendente - vales)}</strong><span className="cap">ainda não pago</span></div>
      </div>
      <section className="card stack">
        <h2>Linha a linha</h2>
        {linhas.length === 0 ? <Vazio tipo="agenda">Nenhum atendimento fechado nesse período.</Vazio> : (
          <div className="scroll">
            <table className="tab">
              <thead><tr><th>Dia</th><th>O quê</th><th className="num">Valor</th><th className="num">Taxa e produto</th><th className="num">Base</th><th className="num">%</th><th className="num">Você recebe</th></tr></thead>
              <tbody>
                {linhas.map((l) => (
                  <tr key={l.id}>
                    <td>{dataBR(l.competencia)}</td>
                    <td>{l.descricao} <span className="cap muted">· {PAPEL[l.papel]}{l.fechamento_id ? " · pago" : ""}</span></td>
                    <td className="num">{reais(l.bruto_centavos)}</td>
                    <td className="num">{l.taxa_centavos + l.custo_centavos ? `− ${reais(l.taxa_centavos + l.custo_centavos)}` : "—"}</td>
                    <td className="num">{reais(l.base_centavos)}</td>
                    <td className="num">{l.percentual}%</td>
                    <td className="num"><strong>{reais(l.valor_centavos)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      {(vs ?? []).length > 0 && (
        <section className="card stack"><h2>Vales em aberto</h2>
          <div className="list">{(vs ?? []).map((v) => <div key={v.id} className="item"><span className="t">{dataBR(v.data)}{v.motivo ? ` · ${v.motivo}` : ""}</span><strong>− {reais(v.valor_centavos)}</strong></div>)}</div>
        </section>
      )}
      {(fs ?? []).length > 0 && (
        <section className="card stack"><h2>Pagamentos recebidos</h2>
          <div className="list">{(fs ?? []).map((x) => <div key={x.id} className="item"><span><span className="t">{dataBR(x.periodo_inicio)} a {dataBR(x.periodo_fim)}</span> <span className="sm sec">· comissões {reais(x.comissoes_centavos)} · gorjetas {reais(x.gorjetas_centavos)} · vales −{reais(x.vales_centavos)}</span></span><strong>{reais(x.pago_centavos)}</strong></div>)}</div>
        </section>
      )}
    </div>
  );
}
