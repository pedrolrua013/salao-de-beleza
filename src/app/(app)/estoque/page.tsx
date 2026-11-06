import Link from "next/link";
import { pode } from "@/lib/permissoes";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { reais } from "@/lib/dinheiro";
import { contarEstoque, darEntrada, registrarPerda, removerInsumo, salvarInsumo } from "./actions";

export const metadata = { title: "Estoque" };

type P = { id: string; nome: string; tipo: "revenda" | "uso" | "ambos"; unidade: "un" | "g" | "ml"; conteudo: number; custo_centavos: number; estoque: number; estoque_minimo: number; ativo: boolean };
const TIPO = { revenda: "revenda", uso: "uso interno", ambos: "uso e revenda" };
const fmt = (n: number) => Number(n).toLocaleString("pt-BR", { maximumFractionDigits: 2 });
const quando = (iso: string, tz: string) => new Intl.DateTimeFormat("pt-BR", { timeZone: tz, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(iso)).replace(",", "");
const MOV = { entrada: "Entrada", venda: "Venda", uso: "Uso em serviço", ajuste: "Contagem", perda: "Perda", estorno: "Estorno" } as Record<string, string>;

/** Saldo de cada produto, alertas de reposição, entrada de mercadoria, contagem e o consumo de cada serviço. */
export default async function Estoque() {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "estoque")) redirect("/hoje");
  const admin = membro.papel === "admin";
  const [{ data: ps }, { data: ins }, { data: srvs }, { data: movs }] = await Promise.all([
    supabase.from("produtos").select("*").eq("ativo", true).order("nome"),
    supabase.from("servico_insumos").select("id, servico_id, produto_id, quantidade"),
    supabase.from("servicos").select("id, nome").eq("ativo", true).order("nome"),
    supabase.from("movimentos_estoque").select("id, produto_id, tipo, quantidade, motivo, em").order("em", { ascending: false }).limit(30),
  ]);
  const produtos = (ps ?? []) as P[];
  const nomeP = new Map(produtos.map((p) => [p.id, p]));
  const nomeS = new Map((srvs ?? []).map((s) => [s.id, s.nome as string]));
  const baixos = produtos.filter((p) => p.estoque_minimo > 0 && p.estoque <= p.estoque_minimo);
  const valor = produtos.reduce((s, p) => s + Math.max(p.estoque, 0) / (p.unidade === "un" ? 1 : p.conteudo) * p.custo_centavos, 0);
  const opcoes = produtos.map((p) => <option key={p.id} value={p.id}>{p.nome} ({p.unidade})</option>);
  return (
    <div className="stack-lg">
      <div className="row between"><h1>Estoque</h1><div className="row"><Link className="btn" href="/estoque/compras">Pedidos de compra</Link><Link className="btn sec" href="/catalogos#produtos">Cadastrar produtos</Link></div></div>
      {baixos.length > 0 && <div className="aviso" role="status"><strong>Hora de repor</strong><ul>{baixos.map((p) => <li key={p.id}>{p.nome}: restam {fmt(p.estoque)} {p.unidade} (mínimo {fmt(p.estoque_minimo)})</li>)}</ul></div>}
      <div className="kpis">
        <div className="kpi"><span className="cap sec">Produtos ativos</span><strong>{produtos.length}</strong></div>
        <div className="kpi"><span className="cap sec">Valor em estoque (custo)</span><strong>{reais(Math.round(valor))}</strong></div>
        <div className="kpi"><span className="cap sec">Para repor</span><strong>{baixos.length}</strong></div>
      </div>
      <section className="card stack">
        <h2>Saldo</h2>
        {produtos.length === 0 ? <p className="sm sec">Nenhum produto. Cadastre em Catálogos: tinta, oxidante, máscara (uso interno) e o que o salão revende.</p> : (
          <div className="scroll">
            <table className="tab">
              <thead><tr><th>Produto</th><th>Tipo</th><th className="num">Saldo</th><th className="num">Embalagens</th><th className="num">Mínimo</th></tr></thead>
              <tbody>{produtos.map((p) => (
                <tr key={p.id} className={p.estoque_minimo > 0 && p.estoque <= p.estoque_minimo ? "baixo" : ""}>
                  <td>{p.nome}</td><td className="cap">{TIPO[p.tipo]}</td><td className="num">{fmt(p.estoque)} {p.unidade}</td>
                  <td className="num">{p.unidade === "un" ? "—" : `≈ ${fmt(p.estoque / p.conteudo)} de ${fmt(p.conteudo)} ${p.unidade}`}</td><td className="num">{p.estoque_minimo ? `${fmt(p.estoque_minimo)} ${p.unidade}` : "—"}</td>
                </tr>))}</tbody>
            </table>
          </div>
        )}
      </section>
      {produtos.length > 0 && (
        <section className="card stack">
          <h2>Movimentar</h2>
          <details className="aj" open><summary>Entrada de mercadoria</summary><div className="aj-corpo">
            <AcaoForm action={darEntrada} className="row">
              <div className="field"><label htmlFor="e-p">Produto</label><select id="e-p" name="produto_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{opcoes}</select></div>
              <div className="field" style={{ width: 120 }}><label htmlFor="e-q">Embalagens</label><input id="e-q" name="embalagens" inputMode="decimal" required /></div>
              <div className="field" style={{ width: 140 }}><label htmlFor="e-c">Custo total (R$)</label><input id="e-c" name="custo" inputMode="decimal" /></div>
              <div className="field" style={{ flex: 1, minWidth: 160 }}><label htmlFor="e-m">Fornecedor / nota</label><input id="e-m" name="motivo" maxLength={200} /></div>
              <div style={{ alignSelf: "flex-end" }}><Enviar>Dar entrada</Enviar></div>
            </AcaoForm></div></details>
          <details className="aj"><summary>Contagem (conferir o que tem de verdade)</summary><div className="aj-corpo">
            <AcaoForm action={contarEstoque} className="row">
              <div className="field"><label htmlFor="c-p">Produto</label><select id="c-p" name="produto_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{opcoes}</select></div>
              <div className="field" style={{ width: 160 }}><label htmlFor="c-q">Quanto tem (na unidade)</label><input id="c-q" name="contado" inputMode="decimal" required /></div>
              <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Ajustar</Enviar></div>
            </AcaoForm></div></details>
          <details className="aj"><summary>Perda (venceu, derramou, quebrou)</summary><div className="aj-corpo">
            <AcaoForm action={registrarPerda} className="row">
              <div className="field"><label htmlFor="l-p">Produto</label><select id="l-p" name="produto_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{opcoes}</select></div>
              <div className="field" style={{ width: 140 }}><label htmlFor="l-q">Quantidade</label><input id="l-q" name="quantidade" inputMode="decimal" required /></div>
              <div className="field" style={{ flex: 1, minWidth: 160 }}><label htmlFor="l-m">Motivo</label><input id="l-m" name="motivo" maxLength={200} /></div>
              <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Registrar perda</Enviar></div>
            </AcaoForm></div></details>
        </section>
      )}
      <section className="card stack">
        <h2>Consumo por serviço</h2>
        <p className="sm sec">Quanto cada serviço gasta de produto. Quando a comanda fecha, sai sozinho do estoque, e dá para ver se o consumo real bate com o esperado na contagem.</p>
        {(ins ?? []).length > 0 && (
          <div className="list">{(ins ?? []).map((i) => (
            <div key={i.id} className="item"><span><span className="t">{nomeS.get(i.servico_id)}</span> <span className="sm sec">· usa {fmt(i.quantidade)} {nomeP.get(i.produto_id)?.unidade} de {nomeP.get(i.produto_id)?.nome}</span></span>
              {admin && <form action={removerInsumo}><input type="hidden" name="id" value={i.id} /><button className="btn ghost sm" type="submit">Remover</button></form>}</div>
          ))}</div>
        )}
        {admin && produtos.length > 0 && (
          <AcaoForm action={salvarInsumo} className="row">
            <div className="field"><label htmlFor="i-s">Serviço</label><select id="i-s" name="servico_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{(srvs ?? []).map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}</select></div>
            <div className="field"><label htmlFor="i-p">Produto</label><select id="i-p" name="produto_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{opcoes}</select></div>
            <div className="field" style={{ width: 140 }}><label htmlFor="i-q">Quantidade</label><input id="i-q" name="quantidade" inputMode="decimal" required placeholder="ex.: 45" /></div>
            <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Salvar consumo</Enviar></div>
          </AcaoForm>
        )}
      </section>
      {(movs ?? []).length > 0 && (
        <section className="card stack">
          <h2>Últimos movimentos</h2>
          <div className="list">{(movs ?? []).map((m) => (
            <div key={m.id} className="item"><span><span className="t">{nomeP.get(m.produto_id)?.nome ?? "Produto"}</span> <span className="sm sec">· {MOV[m.tipo]} · {quando(m.em, salao.fuso)}{m.motivo ? ` · ${m.motivo}` : ""}</span></span>
              <strong className={Number(m.quantidade) > 0 ? "sobe" : "desce"}>{Number(m.quantidade) > 0 ? "+" : ""}{fmt(m.quantidade)} {nomeP.get(m.produto_id)?.unidade}</strong></div>
          ))}</div>
        </section>
      )}
    </div>
  );
}
