import { redirect } from "next/navigation";
import { CampoData } from "@/components/campo-data";
import { exigirMembro } from "@/lib/auth";
import { reais } from "@/lib/dinheiro";
import { dataLocal } from "@/lib/slots";
import { dataBR } from "@/lib/format";
import { Imprimir } from "./imprimir";

export const metadata = { title: "Relatório Salão Parceiro" };

type L = { profissional_id: string; nome: string; documento: string | null; contrato_inicio: string | null; contrato_fim: string | null; contrato_homologado_em: string | null;
  servicos_centavos: number; cota_profissional_centavos: number; cota_salao_centavos: number; gorjetas_centavos: number; repassado_centavos: number };

const doc = (d: string | null) => !d ? "não informado" : d.length === 14 ? d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5") : d;

/** Comprovação da parceria (Lei 13.352/2016): o que entrou, a cota-parte de cada lado e o que foi repassado. Serve de base para o contador e para a fiscalização do ISS. */
export default async function Parceria({ searchParams }: { searchParams: Promise<{ de?: string; ate?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/hoje");
  const q = await searchParams;
  const hoje = dataLocal(new Date(), salao.fuso);
  const de = q.de && /^\d{4}-\d{2}-\d{2}$/.test(q.de) ? q.de : `${hoje.slice(0, 8)}01`;
  const ate = q.ate && /^\d{4}-\d{2}-\d{2}$/.test(q.ate) ? q.ate : hoje;
  const { data } = await supabase.rpc("relatorio_parceria", { p_inicio: de, p_fim: ate });
  const linhas = (data ?? []) as L[];
  const soma = (k: keyof L) => linhas.reduce((s, l) => s + Number(l[k] ?? 0), 0);
  return (
    <div className="stack-lg">
      <div className="row between noprint">
        <form className="row" style={{ gap: 8 }}>
          <CampoData name="de" defaultValue={de} ariaLabel="De" required /><CampoData name="ate" defaultValue={ate} ariaLabel="Até" required />
          <button className="btn sec sm" type="submit">Ver período</button>
        </form>
        <Imprimir />
      </div>
      <article className="card stack doc">
        <div><h1>Comprovação de cota-parte · Salão Parceiro</h1><p className="sec">{salao.nome} · período de {dataBR(de)} a {dataBR(ate)} · Lei 13.352/2016</p></div>
        {linhas.length === 0 ? <p>Nenhum profissional cadastrado como salão-parceiro.</p> : (
          <div className="scroll">
            <table className="tab">
              <thead><tr><th>Profissional-parceiro</th><th>Contrato</th><th className="num">Serviços prestados</th><th className="num">Cota-parte do salão</th><th className="num">Cota-parte do profissional</th><th className="num">Gorjetas</th><th className="num">Repassado no período</th></tr></thead>
              <tbody>
                {linhas.map((l) => (
                  <tr key={l.profissional_id}>
                    <td><strong>{l.nome}</strong><br /><span className="cap muted">CNPJ {doc(l.documento)}</span></td>
                    <td className="cap">{l.contrato_inicio ? `desde ${dataBR(l.contrato_inicio)}` : "sem data"}{l.contrato_fim ? ` até ${dataBR(l.contrato_fim)}` : ""}<br />{l.contrato_homologado_em ? `homologado em ${dataBR(l.contrato_homologado_em)}` : "sem homologação registrada"}</td>
                    <td className="num">{reais(Number(l.servicos_centavos))}</td>
                    <td className="num">{reais(Number(l.cota_salao_centavos))}</td>
                    <td className="num">{reais(Number(l.cota_profissional_centavos))}</td>
                    <td className="num">{reais(Number(l.gorjetas_centavos))}</td>
                    <td className="num">{reais(Number(l.repassado_centavos))}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot><tr><th colSpan={2}>Total</th><th className="num">{reais(soma("servicos_centavos"))}</th><th className="num">{reais(soma("cota_salao_centavos"))}</th><th className="num">{reais(soma("cota_profissional_centavos"))}</th><th className="num">{reais(soma("gorjetas_centavos"))}</th><th className="num">{reais(soma("repassado_centavos"))}</th></tr></tfoot>
            </table>
          </div>
        )}
        <p className="cap muted">A cota-parte do profissional-parceiro não é receita do salão (Lei 12.592/2012, art. 1º-A, §5º, incluído pela Lei 13.352/2016). O salão retém e recolhe os tributos devidos pelo parceiro sobre a cota dele. Cota do profissional inclui comissões de assistência e de venda de produto. Confira com o contador o tratamento no seu município e no regime tributário do salão.</p>
      </article>
    </div>
  );
}
