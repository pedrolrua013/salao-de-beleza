"use server";
import { revalidatePath } from "next/cache";
import { pode } from "@/lib/permissoes";
import { exigirMembro } from "@/lib/auth";
import type { Estado } from "@/components/acao-form";

const UUID = /^[0-9a-f-]{36}$/;
const HORA = /^\d{2}:\d{2}$/;

/** Promoções, campanhas e página do salão: administrador ou quem tem a permissão "divulgar". */
async function exigirAdmin() {
  const m = await exigirMembro();
  if (!pode(m.membro, "divulgar")) throw new Error("sem permissão para divulgar");
  return m;
}

// ───────────── promoções ─────────────

export async function criarPromocao(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirAdmin();
  const tipo = f.get("tipo") === "ultima_hora" ? "ultima_hora" : "horario";
  const percentual = Number(f.get("percentual"));
  if (!Number.isInteger(percentual) || percentual < 5 || percentual > 70) return { erro: "O desconto vai de 5% a 70%." };
  const dias = f.getAll("dias").map(Number).filter((d) => Number.isInteger(d) && d >= 1 && d <= 7);
  const ini = String(f.get("hora_inicio") ?? ""), fim = String(f.get("hora_fim") ?? "");
  if (tipo === "horario" && dias.length === 0) return { erro: "Escolha pelo menos um dia." };
  if (HORA.test(ini) && HORA.test(fim) && fim <= ini) return { erro: "A hora final precisa ser depois da inicial." };
  const servicos = f.getAll("servicos").map(String).filter((x) => UUID.test(x)).slice(0, 50);
  const horasAntes = Number(f.get("horas_antes"));
  const validaAte = String(f.get("valida_ate") ?? "");
  const nome = String(f.get("nome") ?? "").trim().slice(0, 60);
  const { error } = await supabase.from("promocoes").insert({
    nome: nome.length >= 2 ? nome : tipo === "ultima_hora" ? "Última hora" : `${percentual}% off`,
    tipo, percentual,
    dias_semana: tipo === "ultima_hora" ? [1, 2, 3, 4, 5, 6, 7] : [...new Set(dias)],
    hora_inicio: tipo === "horario" && HORA.test(ini) ? ini : null,
    hora_fim: tipo === "horario" && HORA.test(fim) ? fim : null,
    horas_antes: tipo === "ultima_hora" ? (Number.isInteger(horasAntes) && horasAntes >= 1 && horasAntes <= 72 ? horasAntes : 3) : null,
    servico_ids: servicos.length ? servicos : null,
    valida_ate: /^\d{4}-\d{2}-\d{2}$/.test(validaAte) ? validaAte : null,
  });
  if (error) return { erro: "Não foi possível criar a promoção." };
  revalidatePath("/divulgar");
  return { ok: "Promoção criada. Ela já aparece no link de agendamento e o desconto entra na comanda." };
}

export async function alternarPromocao(f: FormData) {
  const { supabase } = await exigirAdmin();
  await supabase.from("promocoes").update({ ativa: f.get("ativa") === "1" }).eq("id", String(f.get("id")));
  revalidatePath("/divulgar");
}

export async function apagarPromocao(f: FormData) {
  const { supabase } = await exigirAdmin();
  await supabase.from("promocoes").delete().eq("id", String(f.get("id")));
  revalidatePath("/divulgar");
}

// ───────────── etiquetas e campanhas ─────────────

/** "Noiva, loira " → "noiva" e "loira": minúsculas, sem espaços nas pontas, até 10. */
function lerEtiquetas(v: FormDataEntryValue | null): string[] {
  return [...new Set(String(v ?? "").split(",").map((x) => x.trim().toLowerCase().replace(/\s+/g, " ").slice(0, 30)).filter(Boolean))].slice(0, 10);
}

export async function criarCampanha(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirAdmin();
  const nome = String(f.get("nome") ?? "").trim().slice(0, 60);
  const mensagem = String(f.get("mensagem") ?? "").replace(/\s+/g, " ").trim();
  if (nome.length < 2) return { erro: "Dê um nome para a campanha (só você vê)." };
  if (mensagem.length < 10 || mensagem.length > 500) return { erro: "A mensagem precisa ter de 10 a 500 caracteres." };
  const sumidas = Number(f.get("sumidas_dias"));
  const { error } = await supabase.from("campanhas").insert({
    nome, mensagem, etiquetas: f.getAll("etiquetas").map(String).filter(Boolean).slice(0, 10),
    sumidas_dias: Number.isInteger(sumidas) && sumidas >= 30 && sumidas <= 730 ? sumidas : null,
  });
  if (error) return { erro: "Não foi possível salvar a campanha." };
  revalidatePath("/divulgar/campanhas");
  return { ok: "Campanha salva. Confira o público e toque em Enviar." };
}

export async function dispararCampanha(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirAdmin();
  const { data, error } = await supabase.rpc("disparar_campanha", { p_id: String(f.get("id")) });
  if (error) {
    if (error.message.includes("uma_campanha_por_dia")) return { erro: "Já saiu uma campanha nas últimas 24 horas. Para proteger o número do salão de bloqueio, envie amanhã." };
    if (error.message.includes("campanha_ja_disparada")) return { erro: "Essa campanha já foi enviada." };
    return { erro: "Não foi possível enviar a campanha." };
  }
  revalidatePath("/divulgar/campanhas");
  return { ok: Number(data) > 0 ? `Enviando para ${data} clientes. As mensagens saem aos poucos, nos próximos minutos.` : "Ninguém nesse público pode receber mensagem agora." };
}

export async function apagarCampanha(f: FormData) {
  const { supabase } = await exigirAdmin();
  await supabase.from("campanhas").delete().eq("id", String(f.get("id")));
  revalidatePath("/divulgar/campanhas");
}

/** Etiquetas da cliente (na ficha dela). */
export async function salvarEtiquetas(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("cliente_id") ?? "");
  const { error } = await supabase.from("clientes").update({ etiquetas: lerEtiquetas(f.get("etiquetas")) }).eq("id", id);
  if (error) return { erro: "Não foi possível salvar as etiquetas." };
  revalidatePath(`/clientes/${id}`);
  return { ok: "Etiquetas salvas." };
}

// ───────────── vitrine ─────────────

export async function salvarVitrine(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao } = await exigirAdmin();
  const insta = String(f.get("instagram") ?? "").trim().replace(/^@/, "").replace(/^https?:\/\/(www\.)?instagram\.com\//, "").replace(/\/.*$/, "");
  if (insta && !/^[A-Za-z0-9._]{1,30}$/.test(insta)) return { erro: "Instagram inválido. Use só o usuário, como @studiobela." };
  const { error } = await supabase.from("saloes").update({
    descricao: String(f.get("descricao") ?? "").trim().slice(0, 600) || null,
    instagram: insta || null,
    vitrine_ativa: f.get("vitrine_ativa") === "on",
  }).eq("id", salao.id);
  if (error) return { erro: "Não foi possível salvar." };
  revalidatePath("/divulgar/vitrine");
  return { ok: "Página do salão atualizada." };
}

export async function enviarFotoVitrine(_: Estado, f: FormData): Promise<Estado> {
  const { supabase, salao, membro } = await exigirMembro();
  if (!pode(membro, "divulgar")) return { erro: "Sem permissão para mexer na página do salão." };
  const arquivo = f.get("foto");
  if (!(arquivo instanceof File) || arquivo.size === 0) return { erro: "Escolha uma foto." };
  if (arquivo.size > 5 * 1024 * 1024) return { erro: "A foto pode ter no máximo 5 MB." };
  if (!/^image\/(jpeg|png|webp)$/.test(arquivo.type)) return { erro: "Use uma foto JPG, PNG ou WEBP." };
  const caminho = `${salao.id}/vitrine/${Date.now()}.${arquivo.type.split("/")[1].replace("jpeg", "jpg")}`;
  const up = await supabase.storage.from("fotos").upload(caminho, arquivo, { contentType: arquivo.type });
  if (up.error) return { erro: "Não foi possível enviar a foto." };
  const { error } = await supabase.from("vitrine_fotos").insert({ caminho, legenda: String(f.get("legenda") ?? "").trim().slice(0, 80) || null });
  if (error) {
    await supabase.storage.from("fotos").remove([caminho]);
    return { erro: error.message.includes("vitrine_cheia") ? "A vitrine já tem 40 fotos. Tire alguma antes." : "Não foi possível salvar a foto." };
  }
  revalidatePath("/divulgar/vitrine");
  return { ok: "Foto na vitrine." };
}

export async function apagarFotoVitrine(f: FormData) {
  const { supabase } = await exigirMembro();
  const { data } = await supabase.from("vitrine_fotos").delete().eq("id", String(f.get("id"))).select("caminho, foto_cliente_id").maybeSingle();
  // Foto que veio da ficha da cliente continua na ficha; só a enviada direto para a vitrine é apagada do armazenamento.
  if (data?.caminho && !data.foto_cliente_id) await supabase.storage.from("fotos").remove([data.caminho]);
  revalidatePath("/divulgar/vitrine");
}

/** Da ficha da cliente para a vitrine (precisa da autorização de uso de imagem). */
export async function publicarFotoCliente(f: FormData) {
  const { supabase } = await exigirMembro();
  const cliente = String(f.get("cliente_id") ?? "");
  await supabase.rpc("publicar_foto_cliente", { p_foto: String(f.get("foto_id")), p_legenda: String(f.get("legenda") ?? "") });
  revalidatePath(`/clientes/${cliente}`); revalidatePath("/divulgar/vitrine");
}
