"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { clienteAdmin } from "@/lib/supabase/admin";
import { cancelarNfse, consultarNfse, emitirNfse, faltaConfigurar, montarNfse, simulandoNfse, type ConfigFiscal } from "@/lib/nfse";
import { cpfValido } from "@/lib/termos";
import type { Estado } from "@/components/acao-form";

/** Só quem cuida do caixa emite; a nota é gravada pelo servidor (o navegador não escreve notas). */
async function preparar(comandaId: string) {
  const m = await exigirMembro();
  if (m.membro.papel === "profissional") return { erro: "Só o administrador ou a recepção emitem nota." } as const;
  const db = clienteAdmin();
  if (!db) return { erro: "Servidor sem chave de serviço." } as const;
  const { data: cfg } = await db.from("fiscal_salao").select("*").eq("salao_id", m.salao.id).maybeSingle();
  return { ...m, db, cfg: cfg as (ConfigFiscal & { ativo: boolean }) | null, comandaId };
}

export async function emitirNota(_: Estado, f: FormData): Promise<Estado> {
  const p = await preparar(String(f.get("comanda_id") ?? ""));
  if ("erro" in p) return { erro: p.erro };
  const { supabase, db, cfg, salao, user } = p;
  const simulando = simulandoNfse();
  if (!cfg?.ativo && !simulando) return { erro: "A nota fiscal está desligada. Ligue em Salão → Nota fiscal." };
  const falta = faltaConfigurar(cfg).filter((x) => !(simulando && x === "token do emissor"));
  if (falta.length) return { erro: `Falta configurar: ${falta.join(", ")}.` };
  // Lido com o login de quem pediu: só comanda do próprio salão.
  const { data: c } = await supabase.from("comandas").select("id, numero, status, desconto_centavos, clientes(nome, email), comanda_itens(tipo, descricao, preco_centavos, quantidade, desconto_centavos)").eq("id", p.comandaId).maybeSingle();
  if (!c || c.status !== "fechada") return { erro: "A nota é emitida depois de fechar a comanda." };
  const itens = (c.comanda_itens ?? []) as { tipo: string; descricao: string; preco_centavos: number; quantidade: number; desconto_centavos: number }[];
  const servicos = itens.filter((i) => i.tipo === "servico");
  const valorServicos = servicos.reduce((s, i) => s + i.preco_centavos * i.quantidade - i.desconto_centavos, 0);
  const valorTudo = itens.filter((i) => i.tipo !== "gorjeta").reduce((s, i) => s + i.preco_centavos * i.quantidade - i.desconto_centavos, 0);
  // O desconto da comanda é dividido na proporção dos serviços (produto tem nota própria, de mercadoria).
  const valor = valorServicos - (valorTudo > 0 ? Math.round(c.desconto_centavos * valorServicos / valorTudo) : 0);
  if (valor <= 0) return { erro: "Esta comanda não tem serviço para nota (produto e gorjeta não entram na nota de serviço)." };
  const doc = String(f.get("documento") ?? "").replace(/\D/g, "");
  if (doc && !(doc.length === 14 || (doc.length === 11 && cpfValido(doc)))) return { erro: "CPF ou CNPJ inválido. Confira ou deixe em branco." };
  const cliente = c.clientes as unknown as { nome: string; email: string | null } | null;
  const nome = String(f.get("nome") ?? "").trim().slice(0, 120) || cliente?.nome || null;
  const ref = `blz-${salao.id.slice(0, 8)}-${c.numero}-${Date.now().toString(36)}`;
  const { data: nota, error } = await db.from("notas_fiscais").insert({
    salao_id: salao.id, comanda_id: c.id, ref, ambiente: simulando ? "simulacao" : cfg!.ambiente, valor_centavos: valor,
    tomador_nome: nome, tomador_documento: doc || null, emitida_por: user.id,
  }).select("id").single();
  if (error || !nota) return { erro: error?.code === "23505" ? "Esta comanda já tem nota emitida ou em emissão." : "Não foi possível registrar a nota." };
  const corpo = montarNfse(cfg!, valor, `${servicos.map((i) => i.descricao).join("; ")}. Comanda #${c.numero}.`, { nome, documento: doc || null, email: cliente?.email ?? null });
  const r = await emitirNfse(cfg!, ref, corpo).catch(() => ({ status: "erro" as const, mensagem: "Sem resposta do emissor. Tente de novo em alguns minutos." }));
  await db.from("notas_fiscais").update({ ...r, atualizado_em: new Date().toISOString() }).eq("id", nota.id);
  revalidatePath(`/caixa/${c.id}`);
  if (r.status === "erro") return { erro: `A nota não foi aceita: ${r.mensagem ?? "erro no emissor"}` };
  return { ok: r.status === "autorizada" ? "Nota autorizada." : "Nota enviada. A prefeitura costuma responder em alguns segundos: toque em Atualizar." };
}

export async function atualizarNota(f: FormData) {
  const p = await preparar(String(f.get("comanda_id") ?? ""));
  if ("erro" in p || !p.cfg) return;
  const { data: n } = await p.db.from("notas_fiscais").select("id, ref, status, ambiente").eq("comanda_id", p.comandaId).eq("salao_id", p.salao.id).eq("status", "processando").maybeSingle();
  if (!n || n.ambiente === "simulacao") return;
  const r = await consultarNfse(p.cfg, n.ref).catch(() => null);
  if (r && r.status !== "processando") await p.db.from("notas_fiscais").update({ ...r, atualizado_em: new Date().toISOString() }).eq("id", n.id);
  revalidatePath(`/caixa/${p.comandaId}`);
}

export async function cancelarNota(_: Estado, f: FormData): Promise<Estado> {
  const p = await preparar(String(f.get("comanda_id") ?? ""));
  if ("erro" in p) return { erro: p.erro };
  if (p.membro.papel !== "admin") return { erro: "Só o administrador cancela nota." };
  const justificativa = String(f.get("justificativa") ?? "").trim();
  if (justificativa.length < 15 || justificativa.length > 255) return { erro: "Explique o motivo do cancelamento (de 15 a 255 caracteres)." };
  const { data: n } = await p.db.from("notas_fiscais").select("id, ref, ambiente").eq("comanda_id", p.comandaId).eq("salao_id", p.salao.id).eq("status", "autorizada").maybeSingle();
  if (!n) return { erro: "Não há nota autorizada nesta comanda." };
  const r = n.ambiente === "simulacao" ? { ok: true } : p.cfg ? await cancelarNfse(p.cfg, n.ref, justificativa) : { ok: false, mensagem: "Configuração fiscal não encontrada." };
  if (!r.ok) return { erro: r.mensagem ?? "Não foi possível cancelar." };
  await p.db.from("notas_fiscais").update({ status: "cancelada", mensagem: justificativa, atualizado_em: new Date().toISOString() }).eq("id", n.id);
  revalidatePath(`/caixa/${p.comandaId}`);
  return { ok: "Nota cancelada." };
}
