import { createClient } from "@/lib/supabase/server";
import { escreverCsv } from "@/lib/csv";

export const dynamic = "force-dynamic";

type Linhas = Record<string, unknown>[];
const r = (v: unknown) => (typeof v === "number" ? (v / 100).toFixed(2).replace(".", ",") : "");

/** Exportação dos dados do salão (só o administrador). Com a sessão do usuário, o banco devolve só o que é do salão dele. */
export async function GET(_: Request, { params }: { params: Promise<{ tipo: string }> }) {
  const { tipo } = await params;
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) return new Response("Não autorizado", { status: 401 });
  const { data: m } = await db.from("membros").select("papel, saloes(slug)").eq("user_id", user.id).maybeSingle();
  if (m?.papel !== "admin") return new Response("Só o administrador exporta dados", { status: 403 });
  const slug = (m.saloes as unknown as { slug: string } | null)?.slug ?? "salao";
  const hoje = new Date().toISOString().slice(0, 10);
  const todos = async (tabela: string, colunas = "*") => {
    const out: Linhas = [];
    const chave = tabela === "membros" ? "user_id" : tabela === "pagamentos_contas" ? "salao_id" : "id";
    for (let de = 0; ; de += 1000) {
      const { data, error } = await db.from(tabela).select(colunas).order(chave).range(de, de + 999);
      if (error) throw new Error(`${tabela}: ${error.message}`); // exportação pela metade não pode parecer completa
      out.push(...((data ?? []) as unknown as Linhas));
      if (!data || data.length < 1000) return out;
    }
  };
  const csv = (nome: string, conteudo: string) => new Response(conteudo, {
    headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${slug}-${nome}-${hoje}.csv"`, "Cache-Control": "no-store" },
  });

  if (tipo === "clientes") {
    const cs = await todos("clientes");
    return csv("clientes", escreverCsv(["Nome", "Celular", "E-mail", "Nascimento", "Tipo de cabelo", "Origem", "Alergias", "Preferências", "Observações", "CEP", "Rua", "Número", "Complemento", "Bairro", "Cidade", "UF", "Aceite WhatsApp", "Cadastro"],
      cs.map((c) => [c.nome, c.telefone, c.email, c.nascimento, c.tipo_cabelo, c.origem, c.alergias, c.preferencias, c.observacoes, c.cep, c.logradouro, c.numero, c.complemento, c.bairro, c.cidade, c.uf, c.consentimento_em ? "sim" : "não", String(c.criado_em).slice(0, 10)] as string[])));
  }
  if (tipo === "agenda") {
    const as = await todos("agendamentos", "inicio, fim, status, origem, clientes(nome, telefone), servicos(nome), membros!agendamentos_profissional_id_salao_id_fkey(nome)");
    return csv("agenda", escreverCsv(["Início", "Fim", "Cliente", "Celular", "Serviço", "Profissional", "Situação", "Origem"],
      as.map((a) => { const x = a as Record<string, any>; return [x.inicio, x.fim, x.clientes?.nome, x.clientes?.telefone, x.servicos?.nome, x.membros?.nome, x.status, x.origem]; })));
  }
  if (tipo === "comandas") {
    const is = await todos("comanda_itens", "tipo, descricao, quantidade, preco_centavos, desconto_centavos, comandas!inner(numero, status, fechada_em, desconto_centavos, clientes(nome)), membros!comanda_itens_profissional_id_salao_id_fkey(nome)");
    return csv("comandas", escreverCsv(["Comanda", "Situação", "Fechada em", "Cliente", "Tipo", "Item", "Qtd", "Preço unitário", "Desconto do item", "Desconto da comanda", "Profissional"],
      is.map((i) => { const x = i as Record<string, any>; return [x.comandas?.numero, x.comandas?.status, x.comandas?.fechada_em, x.comandas?.clientes?.nome, x.tipo, x.descricao, x.quantidade, r(x.preco_centavos), r(x.desconto_centavos), r(x.comandas?.desconto_centavos), x.membros?.nome]; })));
  }
  if (tipo === "comissoes") {
    const cs = await todos("comissoes", "competencia, descricao, papel, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos, fechamento_id, membros!comissoes_profissional_id_salao_id_fkey(nome)");
    return csv("comissoes", escreverCsv(["Dia", "Profissional", "Item", "Papel", "Valor", "Taxa", "Custo produto", "Base", "%", "Comissão", "Paga"],
      cs.map((c) => { const x = c as Record<string, any>; return [x.competencia, x.membros?.nome, x.descricao, x.papel, r(x.bruto_centavos), r(x.taxa_centavos), r(x.custo_centavos), r(x.base_centavos), String(x.percentual).replace(".", ","), r(x.valor_centavos), x.fechamento_id ? "sim" : "não"]; })));
  }
  if (tipo === "fichas") {
    const fs = await todos("fichas_tecnicas", "data, servico, tecnica, formula, pausa_min, resultado, observacoes, clientes(nome)");
    return csv("fichas", escreverCsv(["Data", "Cliente", "Serviço", "Técnica", "Fórmula", "Pausa (min)", "Resultado", "Observações"],
      fs.map((f) => { const x = f as Record<string, any>; return [x.data, x.clientes?.nome, x.servico, x.tecnica, (x.formula ?? []).map((l: any) => [l.zona, l.produto, l.gramas && `${l.gramas} g`, l.oxidante && `${l.oxidante} vol`].filter(Boolean).join(" ")).join(" | "), x.pausa_min, x.resultado, x.observacoes]; })));
  }
  if (tipo === "tudo") {
    const tabelas = ["saloes", "membros", "servicos", "produtos", "clientes", "agendamentos", "bloqueios", "comandas", "comanda_itens", "comanda_pagamentos", "caixas", "caixa_movimentos",
      "regras_comissao", "comissoes", "vales", "fechamentos_comissao", "fichas_tecnicas", "testes_cliente", "fotos_cliente", "sinais", "aceites_politica", "conversas", "mensagens",
      "pacotes", "pacote_itens", "pacotes_cliente", "pacote_saldos", "pacote_usos", "cashback_movimentos", "vales_presente", "vale_presente_usos",
      "lista_espera", "servico_insumos", "movimentos_estoque"];
    // Tabelas com colunas internas (o hash do link) que não saem.
    const colunas: Record<string, string> = {
      fichas_previas: "id, cliente_id, expira_em, respondida_em, respostas, criado_em",
      avaliacoes: "id, cliente_id, comanda_id, profissionais, nota, comentario, respondida_em, criado_em",
    };
    const tudo: Record<string, Linhas> = {};
    try {
      for (const t of tabelas) tudo[t] = await todos(t);
      for (const [t, c] of Object.entries(colunas)) tudo[t] = await todos(t, c);
    } catch (e) {
      console.error("[exportar] falha no backup", e instanceof Error ? e.message : e);
      return new Response("Não foi possível gerar o backup completo. Tente de novo.", { status: 500 });
    }
    return new Response(JSON.stringify({ exportado_em: new Date().toISOString(), ...tudo }, null, 1), {
      headers: { "Content-Type": "application/json; charset=utf-8", "Content-Disposition": `attachment; filename="${slug}-backup-${hoje}.json"`, "Cache-Control": "no-store" },
    });
  }
  return new Response("Tipo desconhecido", { status: 404 });
}
