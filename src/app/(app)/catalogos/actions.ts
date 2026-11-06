"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { fasesDoFormulario } from "@/lib/fases";
import { lerReais } from "@/lib/dinheiro";
import type { Estado } from "@/components/acao-form";

function lerServico(f: FormData) {
  const nome = String(f.get("nome") ?? "").trim();
  const n = (k: string) => Number(f.get(k) || 0);
  return { nome, fases: fasesDoFormulario(n("antes"), n("pausa"), n("depois")), preco: lerReais(String(f.get("preco") ?? "")) ?? 0, custo: lerReais(String(f.get("custo") ?? "")) ?? 0,
    sinal: Math.max(0, Math.min(100, Math.round(Number(f.get("sinal") || 0)))), online: f.get("online") === "on",
    retorno: (() => { const n = Number(f.get("retorno") || 0); return Number.isInteger(n) && n >= 7 && n <= 365 ? n : null; })(),
    intervalo: [0, 5, 10, 15, 20, 30].includes(Number(f.get("intervalo"))) ? Number(f.get("intervalo")) : 0,
    cor: /^#[0-9a-fA-F]{6}$/.test(String(f.get("cor") ?? "")) ? String(f.get("cor")) : null };
}

const ERRO_FASES = "Confira os tempos: total entre 10 e 480 minutos, cada parte com pelo menos 5. Com pausa, informe o trabalho antes e depois dela.";

export async function criarServico(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const { nome, fases, preco, custo, sinal, online, retorno, intervalo, cor } = lerServico(f);
  if (nome.length < 2) return { erro: "Informe o nome do serviço." };
  if (!fases) return { erro: ERRO_FASES };
  const { error } = await supabase.from("servicos").insert({ nome, fases, duracao_min: fases.reduce((s, e) => s + e.min, 0), preco_centavos: preco, custo_produto_centavos: custo, sinal_percentual: sinal, online, retorno_dias: retorno, intervalo_min: intervalo, cor });
  if (error) return { erro: "Só o administrador pode alterar os serviços." };
  revalidatePath("/catalogos");
  return { ok: "Serviço adicionado." };
}

export async function editarServico(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? "");
  const { nome, fases, preco, custo, sinal, online, retorno, intervalo, cor } = lerServico(f);
  if (nome.length < 2) return { erro: "Informe o nome do serviço." };
  if (!fases) return { erro: ERRO_FASES };
  const { data, error } = await supabase.from("servicos").update({ nome, fases, preco_centavos: preco, custo_produto_centavos: custo, sinal_percentual: sinal, online, retorno_dias: retorno, intervalo_min: intervalo, cor }).eq("id", id).select("id");
  if (error || !data?.length) return { erro: "Só o administrador pode alterar os serviços." };
  revalidatePath("/catalogos");
  return { ok: "Serviço salvo. Horários já marcados continuam com os tempos antigos." };
}

export async function alternarServico(f: FormData) {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? ""), ativo = String(f.get("ativo")) === "true";
  await supabase.from("servicos").update({ ativo: !ativo }).eq("id", id);
  revalidatePath("/catalogos");
}

export async function salvarProduto(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? ""), nome = String(f.get("nome") ?? "").trim();
  const tipo = ["revenda", "uso", "ambos"].includes(String(f.get("tipo"))) ? String(f.get("tipo")) : "revenda";
  const unidade = ["un", "g", "ml"].includes(String(f.get("unidade"))) ? String(f.get("unidade")) : "un";
  const preco = lerReais(String(f.get("preco") ?? "")) ?? 0;
  const conteudo = Number(String(f.get("conteudo") ?? "1").replace(",", "."));
  const minimo = Number(String(f.get("minimo") || "0").replace(",", "."));
  if (nome.length < 2) return { erro: "Informe o nome do produto." };
  if (tipo !== "uso" && preco <= 0) return { erro: "Produto de revenda precisa de preço de venda." };
  if (!(conteudo > 0) || !(minimo >= 0)) return { erro: "Confira o conteúdo da embalagem e o mínimo." };
  const dados = { nome, tipo, unidade, preco_centavos: preco, conteudo: unidade === "un" ? 1 : conteudo, custo_centavos: lerReais(String(f.get("custo") ?? "")) ?? 0, estoque_minimo: minimo };
  const q = id ? supabase.from("produtos").update(dados).eq("id", id).select("id") : supabase.from("produtos").insert(dados).select("id");
  const { data, error } = await q;
  if (error || !data?.length) return { erro: "Só o administrador altera os produtos." };
  revalidatePath("/catalogos"); revalidatePath("/estoque");
  return { ok: id ? "Produto salvo." : "Produto adicionado. A entrada de mercadoria fica em Estoque." };
}

export async function alternarProduto(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("produtos").update({ ativo: String(f.get("ativo")) !== "true" }).eq("id", String(f.get("id") ?? ""));
  revalidatePath("/catalogos");
}

export async function criarPacote(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador cria pacotes." };
  const nome = String(f.get("nome") ?? "").trim(), tipo = String(f.get("tipo")) === "clube" ? "clube" : "pacote";
  const preco = lerReais(String(f.get("preco") ?? ""));
  const validade = Number(f.get("validade") || (tipo === "clube" ? 30 : 180));
  const itens = [0, 1, 2, 3].map((i) => ({ servico_id: String(f.get(`servico_${i}`) ?? ""), quantidade: Number(f.get(`qtd_${i}`) || 0) }))
    .filter((x) => x.servico_id && Number.isInteger(x.quantidade) && x.quantidade > 0);
  if (nome.length < 2 || !preco) return { erro: "Informe o nome e o preço." };
  if (itens.length === 0) return { erro: "Escolha pelo menos um serviço com a quantidade." };
  if (new Set(itens.map((x) => x.servico_id)).size !== itens.length) return { erro: "Cada serviço só uma vez por pacote." };
  if (!Number.isInteger(validade) || validade < 7 || validade > 730) return { erro: "Validade entre 7 e 730 dias." };
  const { data, error } = await supabase.from("pacotes").insert({ nome, tipo, preco_centavos: preco, validade_dias: validade }).select("id").single();
  if (error || !data) return { erro: "Não foi possível criar o pacote." };
  const { error: e2 } = await supabase.from("pacote_itens").insert(itens.map((x) => ({ ...x, pacote_id: data.id })));
  if (e2) { await supabase.from("pacotes").delete().eq("id", data.id); return { erro: "Não foi possível salvar os serviços do pacote." }; }
  revalidatePath("/catalogos");
  return { ok: tipo === "clube" ? "Clube criado. Venda e renove pela comanda todo mês." : "Pacote criado. Venda pela comanda." };
}

export async function alternarPacote(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("pacotes").update({ ativo: String(f.get("ativo")) !== "true" }).eq("id", String(f.get("id") ?? ""));
  revalidatePath("/catalogos");
}

// ───────────── tamanhos, preço por profissional e recursos ─────────────

const fasesLinha = (f: FormData) => { const n = (k: string) => Number(f.get(k) || 0); return fasesDoFormulario(n("antes"), n("pausa"), n("depois")); };

/** Tamanho do cabelo (ou outra variação): nome, preço e tempos próprios. */
export async function adicionarVariacao(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const nome = String(f.get("nome") ?? "").trim().slice(0, 40), fases = fasesLinha(f), preco = lerReais(String(f.get("preco") ?? "")) ?? 0;
  if (!nome) return { erro: "Dê um nome, por exemplo Curto, Médio ou Longo." };
  if (!fases) return { erro: ERRO_FASES };
  const { error } = await supabase.from("servico_variacoes").insert({ servico_id: String(f.get("servico_id")), nome, preco_centavos: preco, fases, ordem: Number(f.get("ordem") || 0) });
  if (error) return { erro: error.code === "23505" ? "Já existe um tamanho com esse nome." : "Só o administrador altera os serviços." };
  revalidatePath("/catalogos");
  return { ok: `Tamanho ${nome} adicionado.` };
}

export async function removerVariacao(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("servico_variacoes").delete().eq("id", String(f.get("id") ?? ""));
  revalidatePath("/catalogos");
}

/** Preço e tempo de um profissional (ex.: a sênior cobra mais e é mais rápida). Vazio = segue o serviço. */
export async function salvarPrecoProfissional(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const preco = lerReais(String(f.get("preco") ?? "")), temTempo = !!String(f.get("antes") ?? "").trim();
  const fases = temTempo ? fasesLinha(f) : null;
  if (temTempo && !fases) return { erro: ERRO_FASES };
  if (preco === null && !fases) return { erro: "Informe o preço, o tempo ou os dois." };
  const { error } = await supabase.from("servico_profissional").upsert({ servico_id: String(f.get("servico_id")), profissional_id: String(f.get("profissional_id")), preco_centavos: preco, fases }, { onConflict: "servico_id,profissional_id" });
  if (error) return { erro: "Só o administrador altera os serviços." };
  revalidatePath("/catalogos");
  return { ok: "Preço do profissional salvo." };
}

export async function removerPrecoProfissional(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("servico_profissional").delete().eq("servico_id", String(f.get("servico_id") ?? "")).eq("profissional_id", String(f.get("profissional_id") ?? ""));
  revalidatePath("/catalogos");
}

export async function criarRecurso(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const nome = String(f.get("nome") ?? "").trim().slice(0, 60), qtd = Math.max(1, Math.min(50, Math.floor(Number(f.get("quantidade")) || 1)));
  if (nome.length < 2) return { erro: "Dê um nome, por exemplo Lavatório." };
  const { error } = await supabase.from("recursos").insert({ nome, quantidade: qtd });
  if (error) return { erro: "Só o administrador cadastra recursos." };
  revalidatePath("/catalogos");
  return { ok: `${nome} cadastrado.` };
}

export async function removerRecurso(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("recursos").delete().eq("id", String(f.get("id") ?? ""));
  revalidatePath("/catalogos");
}

/** Quais recursos o serviço usa (ex.: lavatório na coloração). */
export async function salvarRecursosServico(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const servico = String(f.get("servico_id")), escolhidos = f.getAll("recurso").map(String);
  const { error } = await supabase.from("servico_recursos").delete().eq("servico_id", servico);
  if (error) return { erro: "Só o administrador altera os serviços." };
  if (escolhidos.length) {
    const { error: e2 } = await supabase.from("servico_recursos").insert(escolhidos.map((r) => ({ servico_id: servico, recurso_id: r })));
    if (e2) return { erro: "Não foi possível salvar os recursos." };
  }
  revalidatePath("/catalogos");
  return { ok: "Recursos salvos." };
}

/** O que oferecer junto com o serviço (no link e na comanda). */
export async function salvarComplementos(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return { erro: "Só o administrador altera os serviços." };
  const ids = (k: string) => [...new Set(f.getAll(k).map(String).filter((x) => /^[0-9a-f-]{36}$/.test(x)))];
  const servicos = ids("complemento"), produtos = ids("produto");
  if (servicos.length > 5 || produtos.length > 5) return { erro: "Escolha até 5 serviços e 5 produtos." };
  const { error } = await supabase.from("servicos").update({ complementos: servicos, produtos_sugeridos: produtos }).eq("id", String(f.get("servico_id")));
  if (error) return { erro: "Não foi possível salvar as sugestões." };
  revalidatePath("/catalogos");
  return { ok: "Sugestões salvas." };
}

export async function alternarPacoteOnline(f: FormData) {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") return;
  await supabase.from("pacotes").update({ online: f.get("online") === "1" }).eq("id", String(f.get("id")));
  revalidatePath("/catalogos");
}
