import Link from "next/link";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { pode } from "@/lib/permissoes";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { CampoTelefone } from "@/components/campo-telefone";
import { campoReais } from "@/lib/dinheiro";
import { dataCurta } from "@/lib/format";
import { sugerirCompra, textoPedido, type ProdutoEstoque } from "@/lib/compras";
import { apagarFornecedor, cancelarPedido, criarPedido, receberPedido, salvarFornecedor, salvarProdutoCompra } from "./actions";

export const metadata = { title: "Pedidos de compra" };

type Pedido = { id: string; fornecedor_id: string | null; status: string; criado_em: string; pedido_compra_itens: { produto_id: string; embalagens: number }[] };

/** O que repor (abaixo do mínimo), separado por fornecedor; o pedido sai pronto para o WhatsApp e, quando chega, entra no estoque de uma vez. */
export default async function Compras() {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "estoque")) redirect("/hoje");
  const [{ data: ps }, { data: fs }, { data: peds }] = await Promise.all([
    supabase.from("produtos").select("id, nome, unidade, conteudo, estoque, estoque_minimo, estoque_ideal, custo_centavos, fornecedor_id").eq("ativo", true).order("nome"),
    supabase.from("fornecedores").select("id, nome, telefone").order("nome"),
    supabase.from("pedidos_compra").select("id, fornecedor_id, status, criado_em, pedido_compra_itens(produto_id, embalagens)").eq("status", "aberto").order("criado_em", { ascending: false }),
  ]);
  const produtos = (ps ?? []) as ProdutoEstoque[];
  const fornecedores = (fs ?? []) as { id: string; nome: string; telefone: string | null }[];
  const nomeP = new Map(produtos.map((p) => [p.id, p.nome]));
  const nomeF = new Map(fornecedores.map((f) => [f.id, f]));
  const sugestoes = sugerirCompra(produtos);
  const grupos = [...new Set(sugestoes.map((s) => s.produto.fornecedor_id ?? ""))];
  return (
    <div className="stack-lg">
      <div className="row between"><h1>Pedidos de compra</h1><Link className="btn ghost sm" href="/estoque">← Estoque</Link></div>

      {((peds ?? []) as Pedido[]).length > 0 && (
        <section className="card stack">
          <h2>Pedidos em aberto</h2>
          <div className="list">{((peds ?? []) as Pedido[]).map((p) => {
            const f = p.fornecedor_id ? nomeF.get(p.fornecedor_id) : undefined;
            const itens = p.pedido_compra_itens.map((i) => ({ nome: nomeP.get(i.produto_id) ?? "Produto", embalagens: Number(i.embalagens) }));
            return (
              <div key={p.id} className="item">
                <span><span className="t">{f?.nome ?? "Sem fornecedor"}</span> <span className="sm sec">· {dataCurta(p.criado_em, salao.fuso)} · {itens.map((i) => `${i.embalagens}× ${i.nome}`).join(", ")}</span></span>
                <div className="row" style={{ gap: 6 }}>
                  {f?.telefone && <a className="btn sec sm" href={`https://wa.me/55${f.telefone.replace(/^55/, "")}?text=${encodeURIComponent(textoPedido(salao.nome, itens))}`} target="_blank" rel="noopener">Mandar no WhatsApp</a>}
                  <form action={receberPedido}><input type="hidden" name="id" value={p.id} /><button className="btn sm" type="submit">Chegou: dar entrada</button></form>
                  <form action={cancelarPedido}><input type="hidden" name="id" value={p.id} /><button className="btn ghost sm" type="submit">Cancelar</button></form>
                </div>
              </div>
            );
          })}</div>
        </section>
      )}

      <section className="card stack">
        <h2>Hora de repor</h2>
        {sugestoes.length === 0 ? <p className="sm sec">Nada abaixo do mínimo. Defina o estoque mínimo dos produtos em Catálogos para o sistema avisar.</p> : grupos.map((g) => (
          <AcaoForm key={g || "sem"} action={criarPedido}>
            <input type="hidden" name="fornecedor_id" value={g} />
            <h3>{g ? nomeF.get(g)?.nome ?? "Fornecedor" : "Sem fornecedor definido"}</h3>
            <div className="scroll"><table className="tab">
              <thead><tr><th>Produto</th><th className="num">Tem</th><th>Pedir (embalagens)</th><th>Custo por embalagem (R$)</th></tr></thead>
              <tbody>{sugestoes.filter((s) => (s.produto.fornecedor_id ?? "") === g).map((s) => (
                <tr key={s.produto.id}><td>{s.produto.nome}<input type="hidden" name="produto_id" value={s.produto.id} /></td>
                  <td className="num">{Number(s.produto.estoque)} {s.produto.unidade}</td>
                  <td><input name="embalagens" inputMode="decimal" defaultValue={s.embalagens} aria-label={`Embalagens de ${s.produto.nome}`} style={{ width: 90 }} /></td>
                  <td><input name="custo" inputMode="decimal" defaultValue={s.produto.custo_centavos ? campoReais(s.produto.custo_centavos) : ""} aria-label={`Custo de ${s.produto.nome}`} style={{ width: 110 }} /></td></tr>
              ))}</tbody>
            </table></div>
            <div><Enviar className="btn sm">Criar pedido</Enviar></div>
          </AcaoForm>
        ))}
      </section>

      {membro.papel === "admin" && <section className="card stack">
        <h2>Fornecedor e estoque ideal de cada produto</h2>
        <p className="sm sec">O ideal é quanto você quer ter depois de repor (na unidade do produto). Sem ideal, o pedido repõe o dobro do mínimo.</p>
        <div className="list">{produtos.map((p) => (
          <AcaoForm key={p.id} action={salvarProdutoCompra} className="item compra-prod">
            <input type="hidden" name="produto_id" value={p.id} />
            <span className="t">{p.nome} <span className="sm sec">· tem {Number(p.estoque)} {p.unidade} · mínimo {Number(p.estoque_minimo)}</span></span>
            <div className="row" style={{ gap: 6 }}>
              <select name="fornecedor_id" defaultValue={p.fornecedor_id ?? ""} aria-label={`Fornecedor de ${p.nome}`}><option value="">Sem fornecedor</option>{fornecedores.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}</select>
              <input name="estoque_ideal" inputMode="decimal" defaultValue={p.estoque_ideal ?? ""} placeholder="ideal" aria-label={`Estoque ideal de ${p.nome}`} style={{ width: 90 }} />
              <Enviar className="btn ghost sm">Salvar</Enviar>
            </div>
          </AcaoForm>
        ))}</div>
      </section>}

      <section className="card stack">
        <h2>Fornecedores</h2>
        {fornecedores.length > 0 && (
          <div className="list">{fornecedores.map((f) => (
            <div key={f.id} className="item"><span className="t">{f.nome}</span><span className="row" style={{ gap: 6 }}>{f.telefone && <span className="sm sec">{f.telefone}</span>}
              <form action={apagarFornecedor}><input type="hidden" name="id" value={f.id} /><button className="btn ghost sm" type="submit">Apagar</button></form></span></div>
          ))}</div>
        )}
        <AcaoForm action={salvarFornecedor}>
          <div className="grid2">
            <div className="field"><label htmlFor="fn">Nome</label><input id="fn" name="nome" required minLength={2} maxLength={120} /></div>
            <div className="field"><label htmlFor="ft">WhatsApp</label><CampoTelefone id="ft" name="telefone" /></div>
            <div className="field"><label htmlFor="fe">E-mail</label><input id="fe" name="email" type="email" maxLength={200} /></div>
          </div>
          <div><Enviar>Cadastrar fornecedor</Enviar></div>
        </AcaoForm>
      </section>
    </div>
  );
}
