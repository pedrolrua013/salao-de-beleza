import Link from "next/link";
import { notFound } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { hora, dataLonga, telefone } from "@/lib/format";
import { dataLocal } from "@/lib/slots";
import { alternarRobo } from "../actions";
import { Avatar } from "../inbox";
import { MarcarLida } from "./marcar-lida";
import { Compositor } from "./compositor";
import { RolarFim } from "./rolar-fim";

export const metadata = { title: "Conversa" };

const ROBO = <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="8" width="16" height="11" rx="3" /><path d="M12 4v4M9 13h.01M15 13h.01M9 16h6" /></svg>;
const PESSOA = <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4 3.5-7 8-7s8 3 8 7" /></svg>;

/** As opções que o robô ofereceu ficam salvas na última linha, entre colchetes. Mostramos como etiquetas. */
function separar(corpo: string) {
  const linhas = corpo.split("\n");
  const ultima = linhas[linhas.length - 1];
  if (linhas.length > 1 && /^\[.+\]$/.test(ultima)) return { texto: linhas.slice(0, -1).join("\n"), opcoes: ultima.slice(1, -1).split(" | ") };
  return { texto: corpo, opcoes: [] as string[] };
}

export default async function Conversa({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  const { supabase, salao } = await exigirMembro();
  const { data: c } = await supabase.from("conversas")
    .select("id, nome_contato, telefone, bot_ativo, nao_lidas, ultima_entrada_em, cliente_id, clientes(nome)").eq("id", id).maybeSingle();
  if (!c) notFound();
  const { data: msgs } = await supabase.from("mensagens").select("id, direcao, autor, corpo, erro, criado_em").eq("conversa_id", id).order("criado_em", { ascending: true }).limit(300);
  const pac = (c.clientes as unknown as { nome: string } | null)?.nome;
  const nome = pac ?? c.nome_contato ?? telefone(c.telefone);
  const restante = c.ultima_entrada_em ? 24 * 3600_000 - (Date.now() - Date.parse(c.ultima_entrada_em)) : 0;
  const aberta = restante > 0;
  const horas = Math.max(1, Math.ceil(restante / 3600_000));
  let diaAnterior = "";
  return (
    <div className="conv">
      <MarcarLida id={c.id} quando={c.nao_lidas} />
      <header className="conv-topo">
        <Link href="/conversas" className="conv-voltar" aria-label="Voltar para as conversas"><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></svg></Link>
        <Avatar nome={nome} grande />
        <div className="conv-quem">
          <h2>{nome}</h2>
          <p className="sm sec">{telefone(c.telefone)} · {c.cliente_id ? <Link href={`/clientes/${c.cliente_id}`}>Ver cliente</Link> : "Ainda não é cliente"}</p>
        </div>
        <form action={alternarRobo} className="conv-modo">
          <input type="hidden" name="id" value={c.id} /><input type="hidden" name="ativar" value={String(!c.bot_ativo)} />
          <span className={`bd ${c.bot_ativo ? "br" : "wt"}`}><svg viewBox="0 0 24 24" aria-hidden="true">{c.bot_ativo ? ROBO.props.children : PESSOA.props.children}</svg>{c.bot_ativo ? "Robô atendendo" : "Com a equipe"}</span>
          <button className="btn sec sm" type="submit">{c.bot_ativo ? "Assumir" : "Devolver ao robô"}</button>
        </form>
      </header>

      <RolarFim total={(msgs ?? []).length}>
        {(msgs ?? []).length === 0 && <p className="sm sec" style={{ textAlign: "center" }}>Sem mensagens.</p>}
        {(msgs ?? []).map((m) => {
          const dia = dataLocal(new Date(m.criado_em), salao.fuso);
          const sep = dia !== diaAnterior ? (diaAnterior = dia) : null;
          const { texto, opcoes } = separar(m.corpo);
          const tipo = m.autor === "cliente" ? "cliente" : m.autor === "robo" ? "robo" : "equipe";
          return (
            <div key={m.id} className="msg-bloco">
              {sep && <p className="chat-dia"><span>{dataLonga(sep)}</span></p>}
              <div className={`bolha ${tipo}`}>
                <p className="bolha-autor">
                  {tipo === "robo" && <svg viewBox="0 0 24 24" aria-hidden="true">{ROBO.props.children}</svg>}
                  {tipo === "equipe" && <svg viewBox="0 0 24 24" aria-hidden="true">{PESSOA.props.children}</svg>}
                  {tipo === "cliente" ? nome.split(" ")[0] : tipo === "robo" ? "Robô" : "Equipe"}
                </p>
                <p className="bolha-txt">{texto}</p>
                {opcoes.length > 0 && <p className="bolha-ops"><span className="sr">Opções oferecidas: </span>{opcoes.map((o) => <span key={o}>{o}</span>)}</p>}
                {m.erro && <p className="bolha-erro">Não entregue: {m.erro}</p>}
                <span className="bolha-hora">{hora(m.criado_em, salao.fuso)}</span>
              </div>
            </div>
          );
        })}
      </RolarFim>

      <Compositor id={c.id} aberta={aberta} horas={horas} />
    </div>
  );
}
