import type { SupabaseClient } from "@supabase/supabase-js";
import { clienteAdmin } from "@/lib/supabase/admin";

export type Passo = { id: string; titulo: string; texto: string; href: string; acao: string; feito: boolean; opcional?: boolean };

/**
 * Checklist de quem acabou de criar o salão. Some sozinho quando o essencial está feito
 * (primeiro cliente e primeiro agendamento): equipe e WhatsApp são opcionais, pois há salão de uma pessoa só.
 */
export async function primeirosPassos(supabase: SupabaseClient, salaoId: string): Promise<{ passos: Passo[]; mostrar: boolean }> {
  const contar = async (tabela: string) => {
    const { count } = await supabase.from(tabela).select("*", { count: "exact", head: true });
    return count ?? 0;
  };
  const db = clienteAdmin();
  const [clientes, agendamentos, membros, conta, comPreco] = await Promise.all([
    contar("clientes"),
    contar("agendamentos"),
    contar("membros"),
    db ? db.from("whatsapp_contas").select("salao_id").eq("salao_id", salaoId).maybeSingle().then((r) => r.data) : Promise.resolve(null),
    supabase.from("servicos").select("*", { count: "exact", head: true }).gt("preco_centavos", 0).then((r) => r.count ?? 0),
  ]);
  const passos: Passo[] = [
    { id: "precos", titulo: "Coloque preço e pausa nos serviços", texto: "O preço vai para a comanda e para o link. Em química, informe a pausa para a agenda aceitar encaixe.", href: "/catalogos", acao: "Abrir catálogo", feito: comPreco > 0, opcional: true },
    { id: "cliente", titulo: "Cadastre o primeiro cliente", texto: "Nome e telefone bastam. Tem uma planilha? Importe todas de uma vez.", href: "/clientes/importar", acao: "Importar ou cadastrar", feito: clientes > 0 },
    { id: "agendamento", titulo: "Faça o primeiro agendamento", texto: "Escolha cliente, serviço, profissional e um horário livre.", href: "/agenda", acao: "Abrir a agenda", feito: agendamentos > 0 },
    { id: "equipe", titulo: "Convide a equipe", texto: "Cada pessoa com o seu login e o papel certo. Pode pular se você trabalha sozinho(a).", href: "/equipe", acao: "Convidar", feito: membros > 1, opcional: true },
    { id: "link", titulo: "Divulgue o link de agendamento", texto: "Cole o link do salão na bio do Instagram: a cliente marca sozinha, sem app e sem senha.", href: "/configuracoes#online", acao: "Ver o link", feito: false, opcional: true },
    { id: "whatsapp", titulo: "Conecte o WhatsApp", texto: "Liga o robô de agendamento e os lembretes automáticos.", href: "/whatsapp", acao: "Conectar", feito: !!conta, opcional: true },
  ];
  const essencialFeito = passos.filter((p) => !p.opcional).every((p) => p.feito);
  return { passos, mostrar: !essencialFeito };
}
