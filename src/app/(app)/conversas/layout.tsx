import { exigirMembro } from "@/lib/auth";
import { Atualizar } from "@/components/atualizar";
import { telefone } from "@/lib/format";
import { Inbox, type ItemInbox } from "./inbox";

function quando(iso: string, tz: string) {
  const d = new Date(iso);
  const f = (o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat("pt-BR", { timeZone: tz, ...o }).format(d);
  const dia = (x: Date) => new Intl.DateTimeFormat("pt-BR", { timeZone: tz }).format(x);
  const agora = new Date();
  if (dia(d) === dia(agora)) return f({ hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  if (dia(d) === dia(new Date(agora.getTime() - 86_400_000))) return "ontem";
  return f({ day: "2-digit", month: "2-digit" });
}

export default async function ConversasLayout({ children }: { children: React.ReactNode }) {
  const { supabase, salao } = await exigirMembro();
  const { data: conversas } = await supabase.from("conversas")
    .select("id, nome_contato, telefone, bot_ativo, nao_lidas, ultima_msg_em, clientes(nome)")
    .order("ultima_msg_em", { ascending: false }).limit(100);
  const ids = (conversas ?? []).map((c) => c.id);
  const ultimas = new Map<string, string>();
  if (ids.length) {
    const { data: ms } = await supabase.from("mensagens").select("conversa_id, corpo, criado_em").in("conversa_id", ids).order("criado_em", { ascending: false }).limit(300);
    for (const m of ms ?? []) if (!ultimas.has(m.conversa_id)) ultimas.set(m.conversa_id, m.corpo.split("\n")[0]);
  }
  const itens: ItemInbox[] = (conversas ?? []).map((c) => {
    const pac = (c.clientes as unknown as { nome: string } | null)?.nome;
    return {
      id: c.id, nome: pac ?? c.nome_contato ?? telefone(c.telefone), sub: telefone(c.telefone),
      previa: ultimas.get(c.id) ?? "", quando: quando(c.ultima_msg_em, salao.fuso),
      naoLidas: c.nao_lidas, botAtivo: c.bot_ativo, cliente: !!pac,
    };
  });
  return (
    <>
      <Atualizar segundos={8} />
      <Inbox itens={itens}>{children}</Inbox>
    </>
  );
}
