"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { FORMAS, FORMAS_DIGITADAS, lerReais, reais } from "@/lib/dinheiro";
import { pode } from "@/lib/permissoes";
import type { Estado } from "@/components/acao-form";

const atualizar = (id?: string) => { revalidatePath("/caixa"); if (id) revalidatePath(`/caixa/${id}`); revalidatePath("/agenda"); revalidatePath("/hoje"); };
const SEM_CAIXA = "Receber pagamento e fechar comanda é com a recepção. Se você também cobra, peça ao administrador a permissão de caixa.";
const MSG: Record<string, string> = {
  caixa_fechado: "Abra o caixa antes de fechar a comanda.",
  comanda_fechada: "Essa comanda já foi fechada.",
  comanda_vazia: "Adicione pelo menos um item.",
  comanda_com_credito_da_cliente: "Esta comanda já usou pacote, cashback ou sinal desta cliente. Para trocar de cliente, tire esses pagamentos antes.",
  pacote_ja_usado: "Esta comanda vendeu um pacote que já começou a ser usado: não dá para reabrir.",
  comissao_ja_paga: "A comissão desta comanda já foi paga: não dá para reabrir.",
  comanda_nao_reabre: "Só dá para reabrir enquanto o caixa do dia estiver aberto.",
  pacote_sem_cliente: "Para vender pacote, escolha a cliente da comanda.",
  vale_nao_encontrado: "Código de vale-presente não encontrado.",
  vale_vencido: "Este vale-presente venceu ou foi cancelado.",
  vale_da_propria_comanda: "Este vale foi vendido nesta mesma comanda.",
  vale_ja_usado: "Esta comanda vendeu um vale-presente que já foi usado: não dá para reabrir.",
  cashback_ja_usado: "O cashback desta comanda já foi usado pela cliente: não dá para reabrir.",
  pagamento_diferente: "Os pagamentos precisam somar exatamente o total.",
  desconto_maior_que_total: "O desconto é maior que o total.",
  comanda_com_nota: "Esta comanda tem nota fiscal emitida: cancele a nota antes de reabrir.",
  sem_permissao_desconto: "Você não tem permissão para dar desconto. Peça ao administrador.",
  taxa_invalida: "Essa taxa de falta já foi cobrada ou não é desta cliente.",
  sem_permissao_caixa: SEM_CAIXA,
};
const traduzir = (m?: string) => Object.entries(MSG).find(([k]) => m?.includes(k))?.[1];

/** Campo de valor opcional: vazio é "não informado"; preenchido errado é erro (nunca vira outro valor em silêncio). */
function valorOpcional(f: FormData, campo: string): { valor: number | null } | { erro: string } {
  const texto = String(f.get(campo) ?? "").trim();
  if (!texto) return { valor: null };
  const valor = lerReais(texto);
  return valor === null ? { erro: `Valor inválido: "${texto.slice(0, 20)}". Use só números, como 35 ou 35,90 (até R$ 100.000).` } : { valor };
}

/** Quem recebe pagamento e fecha comanda: admin, recepção ou quem tiver a permissão de caixa. */
async function exigirCaixa() {
  const m = await exigirMembro();
  return pode(m.membro, "caixa") ? m : null;
}

// ───────────── caixa ─────────────

export async function abrirCaixa(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const troco = lerReais(String(f.get("troco") ?? "0")) ?? 0;
  const { error } = await supabase.from("caixas").insert({ troco_inicial_centavos: troco });
  if (error) return { erro: error.code === "23505" ? "Já existe um caixa aberto." : "Só administrador ou recepção abrem o caixa." };
  atualizar();
  return { ok: "Caixa aberto." };
}

export async function movimentarCaixa(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const tipo = String(f.get("tipo")), valor = lerReais(String(f.get("valor") ?? ""));
  const prof = String(f.get("profissional_id") ?? "");
  if (!["sangria", "suprimento", "vale"].includes(tipo) || !valor) return { erro: "Informe o valor." };
  if (tipo === "vale" && !prof) return { erro: "Escolha o profissional que recebeu o vale." };
  const motivo = String(f.get("motivo") ?? "").trim().slice(0, 200) || null;
  if (tipo === "vale") {
    const { error } = await supabase.rpc("vale_do_caixa", { p_caixa: String(f.get("caixa_id")), p_prof: prof, p_valor: valor, p_motivo: motivo });
    if (error) return { erro: error.message.includes("caixa_fechado") ? "O caixa já foi fechado." : "Não foi possível lançar o vale. Só administrador ou recepção mexem no caixa." };
    atualizar(); revalidatePath("/comissoes");
    return { ok: "Vale lançado: saiu da gaveta e será descontado no próximo pagamento." };
  }
  const { error } = await supabase.from("caixa_movimentos").insert({ caixa_id: String(f.get("caixa_id")), tipo, valor_centavos: valor, motivo });
  if (error) return { erro: "Não foi possível registrar. Só administrador ou recepção mexem no caixa." };
  atualizar();
  return { ok: tipo === "sangria" ? "Retirada registrada." : "Entrada de troco registrada." };
}

export async function fecharCaixa(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const contado: Record<string, number> = {};
  for (const forma of Object.keys(FORMAS)) {
    const v = lerReais(String(f.get(`c_${forma}`) ?? ""));
    if (v !== null) contado[forma] = v;
  }
  const { error } = await supabase.rpc("fechar_caixa", { p_caixa: String(f.get("caixa_id")), p_contado: contado, p_obs: String(f.get("obs") ?? "").trim() || null });
  if (error) return { erro: traduzir(error.message) ?? "Só administrador ou recepção fecham o caixa." };
  atualizar();
  return { ok: "Caixa fechado. O resumo fica no histórico." };
}

// ───────────── comanda ─────────────

export async function novaComanda(f: FormData) {
  const { supabase } = await exigirMembro();
  const cliente = String(f.get("cliente_id") ?? "") || null;
  const { data } = await supabase.from("comandas").insert({ cliente_id: cliente }).select("id").single();
  if (!data) redirect("/caixa");
  redirect(`/caixa/${data.id}`);
}

/** Da agenda: abre (ou reaproveita) a comanda aberta da cliente e lança o serviço do horário. */
export async function comandaDoHorario(f: FormData) {
  const { supabase, membro } = await exigirMembro();
  const ag = String(f.get("agendamento_id") ?? "");
  const { data: a } = await supabase.from("agendamentos").select("id, cliente_id, servico_id, profissional_id, status").eq("id", ag).maybeSingle();
  if (!a) redirect("/agenda");
  const { data: ja } = await supabase.from("comanda_itens").select("comanda_id, comandas!inner(status)").eq("agendamento_id", ag).eq("comandas.status", "aberta").maybeSingle();
  if (ja) redirect(`/caixa/${ja.comanda_id}`);
  let { data: c } = await supabase.from("comandas").select("id").eq("cliente_id", a.cliente_id).eq("status", "aberta").order("aberta_em", { ascending: false }).limit(1).maybeSingle();
  if (!c) ({ data: c } = await supabase.from("comandas").insert({ cliente_id: a.cliente_id }).select("id").single());
  if (!c) redirect("/agenda");
  // Atendimento com vários serviços: todos entram na comanda (os que ainda não estão em nenhuma comanda aberta).
  const { data: grupo } = await supabase.rpc("do_grupo", { p_ag: a.id });
  const horarios = ((grupo ?? [a]) as { id: string; servico_id: string; variacao_id: string | null; profissional_id: string; status: string; promocao_percentual?: number; promocao_nome?: string | null }[]).filter((g) => g.status !== "cancelado" && g.status !== "faltou");
  const { data: jaLancados } = await supabase.from("comanda_itens").select("agendamento_id, comandas!inner(status)").in("agendamento_id", horarios.map((g) => g.id)).neq("comandas.status", "cancelada");
  const lancados = new Set((jaLancados ?? []).map((x) => x.agendamento_id as string));
  const { data: srvs } = await supabase.from("servicos").select("id, nome, servico_variacoes(id, nome)").in("id", horarios.map((g) => g.servico_id));
  const srvDe = new Map((srvs ?? []).map((x) => [x.id as string, x]));
  const tamanho = (g: { servico_id: string; variacao_id: string | null }) =>
    ((srvDe.get(g.servico_id)?.servico_variacoes ?? []) as { id: string; nome: string }[]).find((v) => v.id === g.variacao_id)?.nome;
  // Preço: o do tamanho, senão o do profissional, senão o do catálogo.
  // Promoção do horário (dia fixo ou última hora) entra como desconto no item.
  const novos = await Promise.all(horarios.filter((g) => !lancados.has(g.id)).map(async (g) => {
    const preco = Number((await supabase.rpc("preco_de", { p_servico: g.servico_id, p_prof: g.profissional_id, p_variacao: g.variacao_id })).data ?? 0);
    const pct = g.promocao_percentual ?? 0;
    const nome = `${(srvDe.get(g.servico_id)?.nome as string) ?? "Serviço"}${tamanho(g) ? ` (${tamanho(g)})` : ""}`;
    return {
      comanda_id: c!.id, tipo: "servico", servico_id: g.servico_id, agendamento_id: g.id, profissional_id: g.profissional_id,
      descricao: (pct > 0 ? `${nome} · ${g.promocao_nome ?? "promoção"} -${pct}%` : nome).slice(0, 160),
      preco_centavos: preco, desconto_centavos: pct > 0 ? Math.round(preco * pct / 100) : 0,
    };
  }));
  if (novos.length) await supabase.from("comanda_itens").insert(novos);
  // Sinal pago (ou crédito de sinal) da cliente já entra como pagamento, uma vez só.
  if (pode(membro, "caixa")) await supabase.rpc("usar_credito_sinal", { p_comanda: c.id });
  atualizar(c.id);
  redirect(`/caixa/${c.id}`);
}

export async function adicionarItem(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const comanda = String(f.get("comanda_id")), tipo = String(f.get("tipo"));
  const prof = String(f.get("profissional_id") ?? "") || null;
  const qtd = Math.max(1, Math.min(999, Math.floor(Number(f.get("quantidade")) || 1)));
  const lidoDesconto = valorOpcional(f, "desconto"), lidoPreco = valorOpcional(f, "preco");
  if ("erro" in lidoDesconto) return { erro: `Desconto: ${lidoDesconto.erro}` };
  if ("erro" in lidoPreco) return { erro: `Preço: ${lidoPreco.erro}` };
  const desconto = lidoDesconto.valor ?? 0, precoDigitado = lidoPreco.valor;
  let linha: Record<string, unknown>;
  if (tipo === "servico") {
    const { data: s } = await supabase.from("servicos").select("id, nome, preco_centavos").eq("id", String(f.get("servico_id"))).maybeSingle();
    if (!s || !prof) return { erro: "Escolha o serviço e quem fez." };
    if (!s.preco_centavos && !String(f.get("preco") ?? "").trim() && !(await supabase.rpc("preco_de", { p_servico: s.id, p_prof: prof, p_variacao: null })).data) return { erro: `${s.nome} está sem preço no catálogo. Digite o preço aqui (ou cadastre em Catálogos).` };
    const assistente = String(f.get("assistente_id") ?? "") || null;
    if (assistente === prof) return { erro: "O assistente precisa ser outra pessoa, não quem fez o serviço. Se ninguém ajudou, deixe \"Ninguém\"." };
    const precoProf = Number((await supabase.rpc("preco_de", { p_servico: s.id, p_prof: prof, p_variacao: null })).data ?? s.preco_centavos);
    const preco = precoDigitado ?? precoProf;
    if (desconto > preco) return { erro: `O desconto (${reais(desconto)}) é maior que o preço (${reais(preco)}).` };
    linha = { tipo, servico_id: s.id, descricao: s.nome, profissional_id: prof, assistente_id: String(f.get("assistente_id") ?? "") || null, preco_centavos: preco, desconto_centavos: desconto };
  } else if (tipo === "produto") {
    const { data: p } = await supabase.from("produtos").select("id, nome, preco_centavos").eq("id", String(f.get("produto_id"))).maybeSingle();
    if (!p) return { erro: "Escolha o produto." };
    linha = { tipo, produto_id: p.id, descricao: p.nome, profissional_id: prof, quantidade: qtd, preco_centavos: precoDigitado ?? p.preco_centavos, desconto_centavos: desconto };
    if (desconto > (precoDigitado ?? p.preco_centavos) * qtd) return { erro: "O desconto é maior que o valor do produto." };
  } else if (tipo === "pacote") {
    const { data: pk } = await supabase.from("pacotes").select("id, nome, preco_centavos").eq("id", String(f.get("pacote_id"))).eq("ativo", true).maybeSingle();
    if (!pk) return { erro: "Escolha o pacote." };
    linha = { tipo, pacote_id: pk.id, descricao: pk.nome, profissional_id: prof, preco_centavos: pk.preco_centavos, desconto_centavos: desconto };
  } else if (tipo === "vale_presente") {
    const v = precoDigitado, para = String(f.get("para") ?? "").trim().slice(0, 80);
    if (!v || !para) return { erro: "Informe o valor e para quem é o presente." };
    linha = { tipo, descricao: `Vale-presente para ${para}`, preco_centavos: v, presente_para: para, presente_mensagem: String(f.get("mensagem") ?? "").trim().slice(0, 200) || null };
  } else if (tipo === "gorjeta") {
    const v = precoDigitado;
    if (!v || !prof) return { erro: "Informe o valor e para quem é a gorjeta." };
    linha = { tipo, descricao: "Gorjeta", profissional_id: prof, preco_centavos: v };
  } else return { erro: "Tipo inválido." };
  const { error } = await supabase.from("comanda_itens").insert({ comanda_id: comanda, ...linha });
  if (error) return { erro: traduzir(error.message) ?? "Não foi possível adicionar. Confira o desconto e os dados." };
  atualizar(comanda);
  return { ok: "Adicionado." };
}

export async function removerItem(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("comanda_itens").delete().eq("id", String(f.get("id")));
  atualizar(String(f.get("comanda_id")));
}

export async function salvarComanda(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("comanda_id"));
  const lido = valorOpcional(f, "desconto");
  if ("erro" in lido) return { erro: `Desconto: ${lido.erro}` };
  const desconto = lido.valor ?? 0;
  // O desconto geral vale sobre serviços, produtos, pacotes e vales (gorjeta é do profissional, não entra).
  const { data: itens } = await supabase.from("comanda_itens").select("tipo, preco_centavos, quantidade, desconto_centavos").eq("comanda_id", id);
  const base = (itens ?? []).filter((i) => i.tipo !== "gorjeta").reduce((s, i) => s + i.preco_centavos * i.quantidade - i.desconto_centavos, 0);
  if (desconto > base) return { erro: base > 0 ? `O desconto geral pode ser no máximo ${reais(base)} (o valor dos serviços e produtos, sem a gorjeta).` : "Adicione os serviços ou produtos antes de dar desconto." };
  const { error } = await supabase.from("comandas").update({ desconto_centavos: desconto, cliente_id: String(f.get("cliente_id") ?? "") || null }).eq("id", id);
  if (error) return { erro: traduzir(error.message) ?? "Não foi possível salvar." };
  atualizar(id);
  return { ok: "Salvo." };
}

export async function adicionarPagamento(_: Estado, f: FormData): Promise<Estado> {
  const m = await exigirCaixa();
  if (!m) return { erro: SEM_CAIXA };
  const { supabase } = m;
  const comanda = String(f.get("comanda_id")), forma = String(f.get("forma"));
  const valor = lerReais(String(f.get("valor") ?? "")), restante = Number(f.get("restante")) || 0;
  const parcelas = forma === "credito" ? Math.max(1, Math.min(24, Math.floor(Number(f.get("parcelas")) || 1))) : 1;
  if (!(FORMAS_DIGITADAS as readonly string[]).includes(forma) || !valor) return { erro: "Escolha a forma e o valor." };
  // Dinheiro a mais vira troco: registra só o que falta e avisa quanto devolver.
  const registrado = forma === "dinheiro" && restante > 0 && valor > restante ? restante : valor;
  const { error } = await supabase.from("comanda_pagamentos").insert({ comanda_id: comanda, forma, valor_centavos: registrado, parcelas });
  if (error) return { erro: traduzir(error.message) ?? "Não foi possível registrar o pagamento." };
  atualizar(comanda);
  return { ok: registrado < valor ? `Troco: R$ ${((valor - registrado) / 100).toFixed(2).replace(".", ",")}` : "Pagamento registrado." };
}

export async function removerPagamento(f: FormData) {
  const m = await exigirCaixa();
  if (!m) return;
  const { supabase } = m;
  await supabase.from("comanda_pagamentos").delete().eq("id", String(f.get("id")));
  atualizar(String(f.get("comanda_id")));
}

export async function fecharComanda(_: Estado, f: FormData): Promise<Estado> {
  const m = await exigirCaixa();
  if (!m) return { erro: SEM_CAIXA };
  const { supabase } = m;
  const id = String(f.get("comanda_id"));
  const { error } = await supabase.rpc("fechar_comanda", { p_comanda: id });
  if (error) return { erro: traduzir(error.message) ?? "Não foi possível fechar a comanda." };
  atualizar(id);
  return { ok: "Comanda fechada." };
}

export async function cancelarComanda(f: FormData) {
  const { supabase } = await exigirMembro();
  const id = String(f.get("comanda_id"));
  await supabase.from("comandas").update({ status: "cancelada" }).eq("id", id);
  atualizar(id);
  redirect("/caixa");
}

/** Na própria comanda: abre o caixa do dia (com o troco informado) e já fecha a comanda. */
export async function abrirCaixaEFechar(_: Estado, f: FormData): Promise<Estado> {
  const m = await exigirCaixa();
  if (!m) return { erro: SEM_CAIXA };
  const { supabase } = m;
  const id = String(f.get("comanda_id"));
  const troco = lerReais(String(f.get("troco") ?? "0")) ?? 0;
  const { error: e1 } = await supabase.from("caixas").insert({ troco_inicial_centavos: troco });
  if (e1 && e1.code !== "23505") return { erro: "Só administrador ou recepção abrem o caixa." };
  const { error } = await supabase.rpc("fechar_comanda", { p_comanda: id });
  atualizar(id);
  if (error) return { erro: `Caixa aberto, mas a comanda não fechou: ${traduzir(error.message) ?? "confira os itens e os pagamentos."}` };
  return { ok: "Caixa aberto e comanda fechada." };
}

export async function reabrirComanda(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("comanda_id"));
  const { error } = await supabase.rpc("reabrir_comanda", { p_comanda: id });
  if (error) return { erro: traduzir(error.message) ?? "Só o administrador reabre comanda." };
  atualizar(id);
  return { ok: "Comanda reaberta." };
}

export async function usarCredito(f: FormData) {
  const m = await exigirCaixa();
  if (!m) return;
  const { supabase } = m;
  const id = String(f.get("comanda_id"));
  await supabase.rpc("usar_credito_sinal", { p_comanda: id });
  atualizar(id);
}

export async function usarPacote(f: FormData) {
  const m = await exigirCaixa();
  if (!m) return;
  const { supabase } = m;
  const id = String(f.get("comanda_id"));
  await supabase.rpc("usar_pacote", { p_comanda: id });
  atualizar(id);
}

export async function usarCashback(f: FormData) {
  const m = await exigirCaixa();
  if (!m) return;
  const { supabase } = m;
  const id = String(f.get("comanda_id"));
  await supabase.rpc("usar_cashback", { p_comanda: id });
  atualizar(id);
}

export async function usarValePresente(_: Estado, f: FormData): Promise<Estado> {
  const m = await exigirCaixa();
  if (!m) return { erro: SEM_CAIXA };
  const { supabase } = m;
  const id = String(f.get("comanda_id")), codigo = String(f.get("codigo") ?? "").replace(/[^A-Za-z0-9]/g, "");
  if (codigo.length !== 8) return { erro: "O código tem 8 letras e números." };
  const { data, error } = await supabase.rpc("usar_vale_presente", { p_comanda: id, p_codigo: codigo });
  if (error) return { erro: traduzir(error.message) ?? "Não foi possível usar o vale." };
  atualizar(id);
  return Number(data) > 0 ? { ok: `Vale usado: ${reais(Number(data))}.` } : { erro: "Não há nada a pagar com o vale." };
}
