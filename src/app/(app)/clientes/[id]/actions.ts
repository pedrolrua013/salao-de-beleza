"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import type { Estado } from "@/components/acao-form";

const LINHAS = 6;
const DATA = /^\d{4}-\d{2}-\d{2}$/;
const num = (v: FormDataEntryValue | null, max: number) => { const n = Number(String(v ?? "").replace(",", ".")); return Number.isFinite(n) && n > 0 && n <= max ? Math.round(n * 10) / 10 : undefined; };

/** Ficha técnica: até 6 linhas de fórmula (zona, produto/tom, gramas, volume e gramas do oxidante). */
export async function salvarFicha(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const cliente = String(f.get("cliente_id"));
  const formula = Array.from({ length: LINHAS }, (_, i) => ({
    zona: String(f.get(`zona_${i}`) ?? "").trim().slice(0, 60) || undefined,
    produto: String(f.get(`produto_${i}`) ?? "").trim().slice(0, 120),
    gramas: num(f.get(`gramas_${i}`), 1000),
    oxidante: num(f.get(`ox_${i}`), 40),
    oxidante_gramas: num(f.get(`oxg_${i}`), 1000),
  })).filter((l) => l.produto);
  const servico = String(f.get("servico") ?? "").trim();
  if (servico.length < 2) return { erro: "Informe o serviço (ex.: Coloração, Mechas, Progressiva)." };
  const pausa = Number(f.get("pausa_min") || 0);
  const data = String(f.get("data") ?? "");
  const { error } = await supabase.from("fichas_tecnicas").insert({
    cliente_id: cliente, servico, formula,
    data: DATA.test(data) ? data : undefined,
    tecnica: String(f.get("tecnica") ?? "").trim().slice(0, 200) || null,
    pausa_min: Number.isInteger(pausa) && pausa > 0 && pausa <= 240 ? pausa : null,
    resultado: String(f.get("resultado") ?? "").trim().slice(0, 1000) || null,
    observacoes: String(f.get("observacoes") ?? "").trim().slice(0, 2000) || null,
  });
  if (error) return { erro: "Não foi possível salvar a ficha." };
  revalidatePath(`/clientes/${cliente}`);
  return { ok: "Ficha salva." };
}

export async function registrarTeste(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const cliente = String(f.get("cliente_id"));
  const tipo = String(f.get("tipo")), resultado = String(f.get("resultado")), produto = String(f.get("produto") ?? "").trim();
  if (produto.length < 2) return { erro: "Informe o produto testado." };
  const { error } = await supabase.from("testes_cliente").insert({ cliente_id: cliente, tipo, resultado, produto, observacoes: String(f.get("observacoes") ?? "").trim().slice(0, 500) || null });
  if (error) return { erro: "Não foi possível registrar o teste." };
  revalidatePath(`/clientes/${cliente}`);
  return { ok: "Teste registrado com data. Ele fica guardado como prova e não pode ser alterado." };
}

export async function enviarFoto(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao } = await exigirMembro();
  const cliente = String(f.get("cliente_id") ?? ""), momento = String(f.get("momento") ?? "depois");
  // Os dois entram no caminho do arquivo: só formatos conhecidos.
  if (!/^[0-9a-f-]{36}$/.test(cliente) || !["antes", "depois", "referencia"].includes(momento)) return { erro: "Foto inválida." };
  const arquivo = f.get("foto");
  if (!(arquivo instanceof File) || arquivo.size === 0) return { erro: "Escolha uma foto." };
  if (arquivo.size > 5 * 1024 * 1024) return { erro: "A foto pode ter no máximo 5 MB." };
  if (!/^image\/(jpeg|png|webp|heic)$/.test(arquivo.type)) return { erro: "Use uma foto JPG, PNG, WEBP ou HEIC." };
  const ext = arquivo.type.split("/")[1].replace("jpeg", "jpg");
  const caminho = `${salao.id}/${cliente}/${Date.now()}-${momento}.${ext}`;
  const up = await supabase.storage.from("fotos").upload(caminho, arquivo, { contentType: arquivo.type });
  if (up.error) return { erro: "Não foi possível enviar a foto. Confira se o armazenamento de fotos está ligado no Supabase." };
  const { error } = await supabase.from("fotos_cliente").insert({ cliente_id: cliente, momento, caminho, ficha_id: String(f.get("ficha_id") ?? "") || null });
  if (error) { await supabase.storage.from("fotos").remove([caminho]); return { erro: "Não foi possível salvar a foto." }; }
  revalidatePath(`/clientes/${cliente}`);
  return { ok: "Foto guardada." };
}

export async function apagarFoto(f: FormData) {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id")), cliente = String(f.get("cliente_id"));
  const { data } = await supabase.from("fotos_cliente").delete().eq("id", id).select("caminho").maybeSingle();
  if (data?.caminho) await supabase.storage.from("fotos").remove([data.caminho]);
  revalidatePath(`/clientes/${cliente}`);
}

export async function aceiteImagem(f: FormData) {
  const { supabase } = await exigirMembro();
  const cliente = String(f.get("cliente_id"));
  await supabase.rpc("registrar_aceite_imagem", { p_cliente: cliente, p_aceita: f.get("aceita") === "1" });
  revalidatePath(`/clientes/${cliente}`);
}

export async function unirCadastros(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const manter = String(f.get("cliente_id")), remover = String(f.get("remover") ?? "");
  if (!remover || remover === manter) return { erro: "Escolha o outro cadastro da mesma pessoa." };
  if (f.get("confirmo") !== "on") return { erro: "Confirme que é a mesma pessoa." };
  const { error } = await supabase.rpc("unir_clientes", { p_manter: manter, p_remover: remover });
  if (error) return { erro: "Só administrador ou recepção unem cadastros." };
  revalidatePath("/clientes");
  redirect(`/clientes/${manter}`);
}

export async function linkFicha(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const cliente = String(f.get("cliente_id") ?? ""), slug = String(f.get("slug") ?? "");
  const { data, error } = await supabase.rpc("criar_link_ficha", { p_cliente: cliente });
  if (error || !data) return { erro: "Não foi possível gerar o link." };
  revalidatePath(`/clientes/${cliente}`);
  return { ok: `Envie para a cliente (vale 7 dias): ${process.env.NEXT_PUBLIC_SITE_URL ?? ""}/s/${slug}/ficha/${data}` };
}

/** Liga ou desliga VIP, "sempre paga sinal" ou bloqueio da cliente. */
export async function marcarCliente(f: FormData) {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? ""), campo = String(f.get("campo") ?? ""), valor = f.get("valor") === "1";
  if (!["vip", "sempre_sinal", "bloqueada"].includes(campo)) return;
  await supabase.from("clientes").update({ [campo]: valor }).eq("id", id);
  revalidatePath(`/clientes/${id}`); revalidatePath("/agenda");
}
