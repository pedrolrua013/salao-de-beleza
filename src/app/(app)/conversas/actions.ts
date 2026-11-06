"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import { clienteAdmin } from "@/lib/supabase/admin";
import { enviarERegistrar } from "@/lib/whatsapp/processar";
import type { Estado } from "@/components/acao-form";

export async function enviarMensagem(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? "");
  const texto = String(f.get("texto") ?? "").trim();
  if (!texto) return { erro: "Escreva a mensagem." };
  if (texto.length > 4000) return { erro: "Mensagem longa demais (máximo 4000 caracteres)." };
  // A leitura passa pela RLS: só enxerga conversa da próprio salão.
  const { data: c } = await supabase.from("conversas").select("id, salao_id, wa_id, ultima_entrada_em").eq("id", id).maybeSingle();
  if (!c) return { erro: "Conversa não encontrada." };
  const db = clienteAdmin();
  if (!db) return { erro: "Servidor sem chave de serviço configurada." };
  const { data: conta } = await db.from("whatsapp_contas").select("phone_number_id, token").eq("salao_id", c.salao_id).maybeSingle();
  if (!conta) return { erro: "O WhatsApp deste salão ainda não foi conectado." };
  const r = await enviarERegistrar(db, conta, c.salao_id, c.id, c.wa_id, { tipo: "texto", corpo: texto }, "equipe");
  if (!r.ok) {
    return { erro: r.janelaFechada
      ? "Já passaram mais de 24 horas desde a última mensagem do cliente. Pelas regras do WhatsApp, só dá para escrever primeiro com um modelo de mensagem aprovado."
      : "Não foi possível enviar agora. Tente de novo em instantes." };
  }
  // Quem respondeu foi uma pessoa: o robô fica quieto até alguém devolver a conversa.
  await db.from("conversas").update({ bot_ativo: false, ultima_msg_em: new Date().toISOString() }).eq("id", c.id);
  revalidatePath(`/conversas/${c.id}`);
  return { ok: "Enviada." };
}

export async function alternarRobo(f: FormData) {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? "");
  const ativar = f.get("ativar") === "true";
  await supabase.from("conversas").update({ bot_ativo: ativar }).eq("id", id);
  revalidatePath(`/conversas/${id}`); revalidatePath("/conversas");
}

export async function marcarLida(id: string) {
  const { supabase } = await exigirMembro();
  await supabase.from("conversas").update({ nao_lidas: 0 }).eq("id", id);
  revalidatePath("/conversas", "layout");
}
