import { campoReais } from "@/lib/dinheiro";

export type ProdutoCampos = { nome: string; preco_centavos: number; tipo: string; unidade: string; conteudo: number; custo_centavos: number; estoque_minimo: number };

/** Produto de revenda (vai para a comanda) ou de uso interno (gasto nos serviços, controlado no estoque). */
export function CamposProduto({ id, p }: { id: string; p?: ProdutoCampos }) {
  return (
    <div className="srv-campos">
      <div className="field srv-nome"><label htmlFor={`${id}-n`}>Produto</label><input id={`${id}-n`} name="nome" defaultValue={p?.nome ?? ""} required minLength={2} maxLength={120} placeholder="Ex.: Tinta 7.1, Shampoo 300 ml" /></div>
      <div className="field"><label htmlFor={`${id}-t`}>Uso</label><select id={`${id}-t`} name="tipo" defaultValue={p?.tipo ?? "revenda"}><option value="revenda">Revenda</option><option value="uso">Uso interno</option><option value="ambos">Os dois</option></select></div>
      <div className="field"><label htmlFor={`${id}-u`}>Controlar em</label><select id={`${id}-u`} name="unidade" defaultValue={p?.unidade ?? "un"}><option value="un">unidades</option><option value="g">gramas</option><option value="ml">ml</option></select></div>
      <div className="field"><label htmlFor={`${id}-c`}>Embalagem tem</label><input id={`${id}-c`} name="conteudo" inputMode="decimal" defaultValue={p?.conteudo ?? 1} /></div>
      <div className="field"><label htmlFor={`${id}-cu`}>Custo da embalagem (R$)</label><input id={`${id}-cu`} name="custo" inputMode="decimal" defaultValue={p?.custo_centavos ? campoReais(p.custo_centavos) : ""} /></div>
      <div className="field"><label htmlFor={`${id}-p`}>Preço de venda (R$)</label><input id={`${id}-p`} name="preco" inputMode="decimal" defaultValue={p?.preco_centavos ? campoReais(p.preco_centavos) : ""} /></div>
      <div className="field"><label htmlFor={`${id}-m`}>Avisar quando tiver menos de</label><input id={`${id}-m`} name="minimo" inputMode="decimal" defaultValue={p?.estoque_minimo || ""} /></div>
    </div>
  );
}
