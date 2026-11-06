import Link from "next/link";
import { MetasDoMes } from "@/components/metas";
import { exigirMembro } from "@/lib/auth";
import { carregarDia } from "@/lib/agenda";
import { dataLocal, somarDias } from "@/lib/slots";
import { dataLonga, hora, telefone } from "@/lib/format";
import { Linha } from "@/components/linha-agenda";
import { Brilho, Tesoura, Vazio } from "@/components/ilustracoes";
import { primeirosPassos } from "@/lib/primeiros-passos";
import { marcarAvisosLidos } from "./actions";

export const metadata = { title: "Hoje" };

function saudacao(tz: string) {
  const h = Number(new Intl.DateTimeFormat("pt-BR", { timeZone: tz, hour: "2-digit", hourCycle: "h23" }).format(new Date()));
  return h < 12 ? "Bom dia" : h < 18 ? "Boa tarde" : "Boa noite";
}

/** Número que sobe até o valor (só CSS). O texto real fica para leitores de tela. */
function Num({ n }: { n: number }) {
  return (
    <>
      <span className="sr">{n}</span>
      <span className="contador" aria-hidden="true" style={{ ["--alvo" as string]: n }} />
    </>
  );
}

export default async function Hoje() {
  const { supabase, membro, salao } = await exigirMembro();
  const agora = new Date();
  const hoje = dataLocal(agora, salao.fuso);
  const amanha = somarDias(hoje, 1);
  const [dia, diaSeguinte, inicio, { data: avisos }] = await Promise.all([
    carregarDia(supabase, salao, hoje), carregarDia(supabase, salao, amanha),
    membro.papel === "admin" ? primeirosPassos(supabase, salao.id) : Promise.resolve(null),
    supabase.from("avisos_equipe").select("id, tipo, dados, criado_em").is("lido_em", null).order("criado_em", { ascending: false }).limit(20),
  ]);
  const quando = (iso: string) => new Intl.DateTimeFormat("pt-BR", { timeZone: salao.fuso, weekday: "short", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(iso)).replace(",", "");
  const AVISO = { novo: ["Novo horário", "ok"], mudou: ["Horário remarcado", "wt"], cancelou: ["Horário cancelado", "no"] } as const;
  // Quem ainda não confirmou, de hoje (a partir de agora) e de amanhã: é a lista de ligações da recepção.
  const semConfirmar = [
    ...dia.filter((a) => Date.parse(a.fim) > agora.getTime()).map((a) => ({ a, quando: "Hoje" })),
    ...diaSeguinte.map((a) => ({ a, quando: "Amanhã" })),
  ].filter(({ a }) => a.status === "agendado");
  const ativos = dia.filter((a) => a.status !== "cancelado" && a.status !== "faltou");
  const confirmados = ativos.filter((a) => a.status === "confirmado").length;
  const aguardando = ativos.filter((a) => a.status === "agendado").length;
  const concluidos = ativos.filter((a) => a.status === "concluido").length;
  const pct = ativos.length ? Math.round((concluidos / ativos.length) * 100) : 0;
  const proximo = ativos.find((a) => (a.status === "agendado" || a.status === "confirmado") && Date.parse(a.fim) > agora.getTime());
  const emAtendimento = ativos.find((a) => a.status === "em_atendimento");
  const primeiroNome = membro.nome.replace(/^(dra?\.?|dr)\s+/i, "").split(" ")[0];
  return (
    <div className="stack-lg">
      <section className="hero">
        <Tesoura className="hero-tesoura" />
        <Brilho className="hero-b b1" /><Brilho className="hero-b b2" /><Brilho className="hero-b b3" />
        <div className="hero-txt">
          <p className="hero-data">{dataLonga(hoje)}</p>
          <h1>{saudacao(salao.fuso)}, {primeiroNome}!</h1>
          <p className="hero-sub">
            {ativos.length === 0 ? "Nenhum cliente marcado para hoje."
              : emAtendimento ? `${emAtendimento.cliente} está em atendimento agora.`
              : proximo ? `Próximo cliente: ${proximo.cliente}, às ${hora(proximo.inicio, salao.fuso)}.`
              : ativos.some((a) => a.status === "agendado" || a.status === "confirmado")
                ? `${ativos.filter((a) => a.status === "agendado" || a.status === "confirmado").length === 1 ? "Um horário já passou e" : "Alguns horários já passaram e"} ainda não ${ativos.filter((a) => a.status === "agendado" || a.status === "confirmado").length === 1 ? "foi fechado" : "foram fechados"}: conclua, abra a comanda ou marque a falta.`
                : "Todos os clientes de hoje já foram atendidos. Bom trabalho!"}
          </p>
          {ativos.length > 0 && (
            <div className="prog" role="img" aria-label={`${concluidos} de ${ativos.length} atendimentos concluídos`}>
              <div className="prog-barra"><i style={{ width: `${pct}%` }} /></div>
              <span>{concluidos} de {ativos.length} concluídos</span>
            </div>
          )}
          <Link className="btn hero-btn" href={`/agenda?data=${hoje}`}>Novo agendamento</Link>
        </div>
      </section>

      <MetasDoMes supabase={supabase} hoje={hoje} nomes={new Map([[membro.user_id, membro.nome]])} />

      {(avisos ?? []).length > 0 && (
        <section className="card stack avisos-eq" aria-labelledby="av-t">
          <div className="row between"><h2 id="av-t">Mudanças na sua agenda</h2>
            <form action={marcarAvisosLidos}><button className="btn ghost sm" type="submit">Marcar como vistos</button></form></div>
          <div className="list">{(avisos ?? []).filter((a, i, todos) => {
            const lote = (a.dados as { lote?: string }).lote;
            return !lote || todos.findIndex((x) => x.tipo === a.tipo && (x.dados as { lote?: string }).lote === lote) === i;
          }).map((a) => {
            const d = a.dados as { cliente?: string; servico?: string; inicio?: string; inicio_antigo?: string; lote?: string };
            const [rot, tom] = AVISO[a.tipo as keyof typeof AVISO] ?? ["Aviso", "mu"];
            return (
              <div key={a.id} className="item">
                <span><span className={`bd ${tom}`}>{rot}</span> <span className="t">{d.cliente ?? "Cliente"}</span> <span className="sm sec">· {d.servico ?? ""}{d.inicio ? ` · ${a.tipo === "mudou" && d.inicio_antigo ? `de ${quando(d.inicio_antigo)} para ` : ""}${quando(d.inicio)}` : ""}</span></span>
              </div>
            );
          })}</div>
        </section>
      )}

      {membro.papel === "admin" && !salao.guia_concluido_em && (
        <section className="card pp-card guia-convite-hoje" aria-labelledby="gc-t">
          <div><h2 id="gc-t">Vamos deixar seu salão pronto</h2>
            <p className="sc-sub" style={{ margin: 0 }}>Horário, serviços com preço, equipe, clientes e o link de agendamento. Leva poucos minutos.</p></div>
          <Link className="btn" href="/guia">Continuar configuração</Link>
        </section>
      )}

      {inicio?.mostrar && salao.guia_concluido_em && (
        <section className="card pp-card" aria-labelledby="pp-t">
          <div className="sc-cab"><h2 id="pp-t">Primeiros passos</h2><span className="sc-n">{inicio.passos.filter((p) => p.feito).length} de {inicio.passos.length}</span></div>
          <p className="sc-sub">Em poucos minutos o salão está pronta. <Link href="/ajuda">Precisa de ajuda?</Link></p>
          <ol className="pp-lista">
            {inicio.passos.map((p) => (
              <li key={p.id} className={p.feito ? "pp-item feito" : "pp-item"}>
                <span className="pp-marca" aria-hidden="true">{p.feito ? "✓" : ""}</span>
                <div className="pp-txt">
                  <strong>{p.titulo}{p.opcional && <span className="pp-op"> · opcional</span>}{p.feito && <span className="sr"> (feito)</span>}</strong>
                  {!p.feito && <p>{p.texto}</p>}
                </div>
                {!p.feito && <Link className="btn sec sm" href={p.href}>{p.acao}</Link>}
              </li>
            ))}
          </ol>
        </section>
      )}

      <div className="stats">
        <div className="card stat"><span className="stat-ic ic-brand"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="8" r="3.500" /><path d="M2.500 20c0-3.600 2.900-6 6.500-6s6.500 2.400 6.500 6M16 4.500a3.500 3.500 0 0 1 0 7M18 14.300c2 .7 3.500 2.500 3.500 5.700" /></svg></span>
          <div><p className="cap muted">Clientes hoje</p><p className="stat-n"><Num n={ativos.length} /></p></div></div>
        <div className="card stat"><span className="stat-ic ic-ok"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12l5 5L20 7" /></svg></span>
          <div><p className="cap muted">Confirmados</p><p className="stat-n"><Num n={confirmados} /></p></div></div>
        <div className="card stat"><span className="stat-ic ic-wt"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg></span>
          <div><p className="cap muted">Sem confirmar</p><p className="stat-n"><Num n={aguardando} /></p></div></div>
      </div>

      {semConfirmar.length > 0 && (
        <section className="card sc-card">
          <div className="sc-cab"><h2>Ainda sem confirmação</h2><span className="sc-n">{semConfirmar.length}</span></div>
          <p className="sc-sub">Clientes de hoje e de amanhã que ainda não confirmaram. Vale uma ligação.</p>
          <div className="sc-lista">
            {semConfirmar.map(({ a, quando }) => (
              <div className="sc-item" key={a.id}>
                <div className="sc-quando"><strong>{hora(a.inicio, salao.fuso)}</strong><span>{quando}</span></div>
                <div className="sc-quem">
                  <Link href={`/clientes/${a.cliente_id}`}>{a.cliente}</Link>
                  <p className="cap muted" style={{ margin: 0 }}>{a.servico} · {a.profissional}</p>
                  {a.lembrete && <p className={`ag-lem ${a.lembrete.tom}`}>{a.lembrete.texto}</p>}
                </div>
                {a.telefone ? <a className="btn sec sm" aria-label={`Ligar para ${a.cliente}`} href={`tel:+55${a.telefone.replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "")}`}>Ligar · {telefone(a.telefone)}</a> : <span className="cap muted">Sem telefone</span>}
              </div>
            ))}
          </div>
        </section>
      )}

      <section className="card">
        <h2 style={{ marginBottom: 8 }}>Agenda do dia</h2>
        {dia.length === 0 ? (
          <Vazio tipo="agenda">Nenhum horário marcado para hoje. <Link href={`/agenda?data=${hoje}`}>Agendar um cliente</Link></Vazio>
        ) : (
          <div className="ag-lista">{dia.map((a) => <Linha key={a.id} a={a} tz={salao.fuso} papel={membro.papel} usuarioId={membro.user_id} />)}</div>
        )}
      </section>
    </div>
  );
}
