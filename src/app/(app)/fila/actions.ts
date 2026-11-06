"use server";
import { revalidatePath } from "next/cache";
import { exigirMembro } from "@/lib/auth";
import type { Estado } from "@/components/acao-form";

const UUID = /^[0-9a-f-]{36}$/;
const atualizar = () => { revalidatePath("/fila"); revalidatePath("/agenda"); revalidatePath("/hoje"); };

/** Quem chegou sem hora entra na fila (com ou sem cadastro). */
export async function entrarNaFila(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const cliente = String(f.get("cliente_id") ?? ""), nomeDigitado = String(f.get("nome") ?? "").trim().slice(0, 120);
  let nome = nomeDigitado;
  if (UUID.test(cliente)) {
    const { data } = await supabase.from("clientes").select("nome").eq("id", cliente).maybeSingle();
    nome = (data?.nome as string) ?? nomeDigitado;
  }
  if (nome.length < 2) return { erro: "Escolha a cliente ou escreva o nome de quem chegou." };
  const servico = String(f.get("servico_id") ?? ""), pref = String(f.get("profissional") ?? "");
  const { error } = await supabase.from("fila_atendimento").insert({
    nome, cliente_id: UUID.test(cliente) ? cliente : null, servico_id: UUID.test(servico) ? servico : null, profissional_preferido: UUID.test(pref) ? pref : null,
  });
  if (error) return { erro: "Não foi possível pôr na fila." };
  atualizar();
  return { ok: `${nome} entrou na fila.` };
}

/** Chama da fila: marca o atendimento agora com o profissional e começa. Sem cadastro, cria a cliente só com o nome. */
export async function chamarDaFila(_: Estado, f: FormData): Promise<Estado> {
  const { supabase } = await exigirMembro();
  const id = String(f.get("id") ?? ""), prof = String(f.get("profissional") ?? "");
  if (!UUID.test(id) || !UUID.test(prof)) return { erro: "Escolha quem vai atender." };
  const { data: item } = await supabase.from("fila_atendimento").select("id, nome, cliente_id, servico_id, estado").eq("id", id).maybeSingle();
  if (!item || item.estado !== "aguardando") return { erro: "Essa pessoa já foi chamada." };
  if (!item.servico_id) return { erro: "Escolha o serviço antes de chamar." };
  let cliente = item.cliente_id as string | null;
  if (!cliente) {
    const { data: nova } = await supabase.from("clientes").insert({ nome: item.nome }).select("id").single();
    cliente = nova?.id ?? null;
  }
  if (!cliente) return { erro: "Não foi possível cadastrar a cliente." };
  const agora = new Date(); agora.setSeconds(0, 0);
  const { data: ag, error } = await supabase.from("agendamentos").insert({ cliente_id: cliente, servico_id: item.servico_id, profissional_id: prof, inicio: agora.toISOString(), status: "em_atendimento" }).select("id").single();
  if (error || !ag) return { erro: error?.code === "23P01" ? "Esse profissional está ocupado agora. Chame com outra pessoa." : error?.message.includes("sem_permissao_agenda") ? "Você só pode chamar para a sua própria agenda." : "Não foi possível começar o atendimento." };
  await supabase.from("fila_atendimento").update({ estado: "atendendo", agendamento_id: ag.id }).eq("id", id);
  atualizar();
  return { ok: `${item.nome} está sendo atendida.` };
}

export async function sairDaFila(f: FormData) {
  const { supabase } = await exigirMembro();
  await supabase.from("fila_atendimento").update({ estado: "saiu" }).eq("id", String(f.get("id") ?? ""));
  atualizar();
}
