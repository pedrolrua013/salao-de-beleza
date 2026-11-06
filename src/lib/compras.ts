// Pedido de compra: o que repor e quanto, em embalagens, a partir do estoque mínimo e do ideal.

export type ProdutoEstoque = { id: string; nome: string; unidade: "un" | "g" | "ml"; conteudo: number; estoque: number; estoque_minimo: number; estoque_ideal: number | null; custo_centavos: number; fornecedor_id: string | null };
export type Sugestao = { produto: ProdutoEstoque; embalagens: number };

/** Abaixo do mínimo: pede até o ideal (sem ideal, até o dobro do mínimo), em embalagens inteiras. */
export function sugerirCompra(produtos: ProdutoEstoque[]): Sugestao[] {
  return produtos
    .filter((p) => p.estoque_minimo > 0 && p.estoque <= p.estoque_minimo)
    .map((p) => {
      const alvo = p.estoque_ideal && p.estoque_ideal > p.estoque_minimo ? p.estoque_ideal : p.estoque_minimo * 2;
      const porEmbalagem = p.unidade === "un" ? 1 : Math.max(Number(p.conteudo), 1);
      return { produto: p, embalagens: Math.max(1, Math.ceil((alvo - Math.max(p.estoque, 0)) / porEmbalagem)) };
    });
}

/** Texto para mandar ao fornecedor pelo WhatsApp. */
export function textoPedido(salao: string, itens: { nome: string; embalagens: number }[]): string {
  return [`Olá! Pedido do ${salao}:`, ...itens.map((i) => `• ${String(i.embalagens).replace(".", ",")} × ${i.nome}`), "Pode confirmar o valor e o prazo de entrega? Obrigado!"].join("\n");
}
