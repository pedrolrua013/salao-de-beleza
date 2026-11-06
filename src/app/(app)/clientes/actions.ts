"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { soDigitos } from "@/lib/format";
import { voltaSegura } from "@/lib/volta";
import { UFS } from "@/lib/cep";
import type { Estado } from "@/components/acao-form";

const TIPOS = ["liso", "ondulado", "cacheado", "crespo"];
const ORIGENS = ["indicacao", "instagram", "google", "whatsapp", "passante", "facebook", "tiktok", "outro"];

const texto = (f: FormData, k: string, max: number) => String(f.get(k) ?? "").trim().replace(/\s+/g, " ").slice(0, max) || null;

function ler(f: FormData) {
  const tel = soDigitos(String(f.get("telefone") ?? ""));
  const cep = soDigitos(String(f.get("cep") ?? ""));
  const uf = String(f.get("uf") ?? "").toUpperCase();
  return {
    nome: String(f.get("nome") ?? "").trim(),
    telefone: tel || null,
    email: String(f.get("email") ?? "").trim() || null,
    nascimento: String(f.get("nascimento") ?? "") || null,
    observacoes: String(f.get("observacoes") ?? "").trim() || null,
    alergias: String(f.get("alergias") ?? "").trim().slice(0, 500) || null,
    preferencias: String(f.get("preferencias") ?? "").trim().slice(0, 1000) || null,
    tipo_cabelo: TIPOS.includes(String(f.get("tipo_cabelo"))) ? String(f.get("tipo_cabelo")) : null,
    origem: ORIGENS.includes(String(f.get("origem"))) ? String(f.get("origem")) : null,
    cep: cep.length === 8 ? cep : null,
    logradouro: texto(f, "logradouro", 200), numero: texto(f, "numero", 20), complemento: texto(f, "complemento", 100),
    bairro: texto(f, "bairro", 100), cidade: texto(f, "cidade", 100), uf: UFS.includes(uf) ? uf : null,
    indicado_por: /^[0-9a-f-]{36}$/.test(String(f.get("indicado_por") ?? "")) && f.get("indicado_por") !== f.get("id") ? String(f.get("indicado_por")) : null,
  };
}
function validar(d: ReturnType<typeof ler>): string | null {
  if (d.nome.length < 2) return "Informe o nome do cliente.";
  if (d.telefone && !/^[0-9]{10,13}$/.test(d.telefone)) return "Telefone inválido. Use DDD e número.";
  return null;
}

export async function criarCliente(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const d = ler(f);
  const e = validar(d);
  if (e) return { erro: e };
  if (d.telefone) {
    const { data: ja } = await supabase.from("clientes").select("nome").eq("telefone", d.telefone).limit(1).maybeSingle();
    if (ja) return { erro: `Esse telefone já está no cadastro de ${ja.nome}. Busque por ele em vez de cadastrar de novo.` };
  }
  const { data, error } = await supabase.from("clientes").insert(d).select("id").single();
  if (error || !data) return { erro: "Não foi possível salvar o cliente." };
  if (f.get("aceite_whatsapp") === "on" && d.telefone) await supabase.rpc("registrar_aceite_contato", { p_cliente: data.id });
  revalidatePath("/clientes");
  const voltar = voltaSegura(f.get("voltar"));
  if (voltar) {
    const u = new URL(voltar, "http://x");
    u.searchParams.set("cliente", data.id);
    redirect(`${u.pathname}${u.search}`);
  }
  redirect(`/clientes/${data.id}`);
}

export async function editarCliente(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? "");
  const d = ler(f);
  const e = validar(d);
  if (e) return { erro: e };
  const { error } = await supabase.from("clientes").update(d).eq("id", id);
  if (error) return { erro: "Não foi possível salvar as alterações." };
  if (f.get("aceite_whatsapp") === "on" && d.telefone) await supabase.rpc("registrar_aceite_contato", { p_cliente: id });
  revalidatePath(`/clientes/${id}`); revalidatePath("/clientes");
  return { ok: "Dados salvos." };
}
