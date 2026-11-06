import { redirect } from "next/navigation";
import { pode } from "@/lib/permissoes";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { DIAS_CURTOS, descreverPromocao, mapaOcupacao, type Jornada, type Promocao } from "@/lib/promocoes";
import { AbasDivulgar } from "./abas";
import { todasAsLinhas } from "@/lib/paginar";
import { alternarPromocao, apagarPromocao, criarPromocao } from "./actions";

export const metadata = { title: "Horários vazios e promoções" };

const SEMANAS = 8;

/** Mapa de calor das últimas 8 semanas e as promoções para encher os horários fracos. */
export default async function Divulgar({ searchParams }: { searchParams: Promise<{ dia?: string; hora?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "divulgar")) redirect("/hoje");
  const q = await searchParams;
  const agora = new Date();
  const desde = new Date(agora.getTime() - SEMANAS * 7 * 86_400_000).toISOString();
  const [ags, { data: profs }, { data: promos }, { data: srvs }] = await Promise.all([
    todasAsLinhas<{ inicio: string; fim: string; profissional_id: string }>((de, ate) => supabase.from("agendamentos").select("inicio, fim, profissional_id")
      .gte("inicio", desde).lt("inicio", agora.toISOString()).in("status", ["agendado", "confirmado", "em_atendimento", "concluido"]).order("id").range(de, ate)),
    supabase.from("membros").select("user_id, dias_semana, entrada, saida, almoco_inicio, almoco_fim").eq("ativo", true).in("papel", ["admin", "profissional"]),
    supabase.from("promocoes").select("*").order("criado_em", { ascending: false }),
    supabase.from("servicos").select("id, nome").eq("ativo", true).eq("avulso", false).order("nome"),
  ]);
  const jornadas = new Map<string, Jornada>((profs ?? []).map((p) => [p.user_id as string, {
    dias: (p.dias_semana as number[] | null) ?? salao.dias_semana,
    abre: ((p.entrada as string | null) ?? salao.abre).slice(0, 5),
    fecha: ((p.saida as string | null) ?? salao.fecha).slice(0, 5),
    almoco: p.almoco_inicio ? { inicio: (p.almoco_inicio as string).slice(0, 5), fim: (p.almoco_fim as string).slice(0, 5) } : null,
  }]));
  const mapa = mapaOcupacao(ags, jornadas, salao.fuso, SEMANAS);
  const lista = (promos ?? []) as Promocao[];
  const nomeSrv = new Map((srvs ?? []).map((s) => [s.id as string, s.nome as string]));
  const hh = (h: number) => `${String(h).padStart(2, "0")}:00`;
  const sugDia = Number(q.dia), sugHora = Number(q.hora);
  const sugerida = Number.isInteger(sugDia) && sugDia >= 1 && sugDia <= 7 && Number.isInteger(sugHora) && sugHora >= 0 && sugHora < 24;
  const poucosDados = ags.length < 20;
  return (
    <div className="stack-lg">
      <AbasDivulgar atual="/divulgar" />
      <section className="card stack">
        <div className="row between"><h2>Quando a agenda fica vazia</h2><span className="cap muted">últimas {SEMANAS} semanas</span></div>
        <p className="sm sec">Quanto mais forte a cor, mais cheio aquele horário costuma ficar. Os horários claros são os melhores para uma promoção.</p>
        {mapa.horas.length === 0 ? <p className="sec">Cadastre os horários da equipe para ver o mapa.</p> : (
          <div className="scroll">
            <div className="mapa" role="table" aria-label="Ocupação por dia e hora">
              <div role="row" className="mapa-linha"><span role="columnheader" />{[1, 2, 3, 4, 5, 6, 7].map((d) => <span key={d} role="columnheader" className="mapa-dia">{DIAS_CURTOS[d]}</span>)}</div>
              {mapa.horas.map((h) => (
                <div key={h} role="row" className="mapa-linha">
                  <span role="rowheader" className="mapa-hora">{hh(h)}</span>
                  {mapa.celulas.filter((c) => c.hora === h).map((c) => (
                    <span key={c.dia} role="cell" className={`mapa-c${c.ocupacao === null ? " fechado" : c.ocupacao >= 0.55 ? " forte" : ""}`} style={c.ocupacao === null ? undefined : { ["--o" as string]: String(Math.round(c.ocupacao * 100)) }}
                      title={c.ocupacao === null ? `${DIAS_CURTOS[c.dia]} ${hh(h)}: fechado` : `${DIAS_CURTOS[c.dia]} ${hh(h)}: ${Math.round(c.ocupacao * 100)}% ocupado`}>
                      {c.ocupacao === null ? "" : `${Math.round(c.ocupacao * 100)}%`}
                    </span>
                  ))}
                </div>
              ))}
            </div>
          </div>
        )}
        {poucosDados && <p className="cap muted">Ainda há poucos atendimentos registrados: o mapa fica mais certo com o tempo.</p>}
        {!poucosDados && mapa.vazios.length > 0 && (
          <div className="stack">
            <h3>Horários mais vazios</h3>
            <div className="row" style={{ gap: 8 }}>{mapa.vazios.map((c) => (
              <a key={`${c.dia}-${c.hora}`} className="btn ghost sm" href={`/divulgar?dia=${c.dia}&hora=${c.hora}#nova`}>{DIAS_CURTOS[c.dia]} {hh(c.hora)} · {Math.round(c.ocupacao! * 100)}% · criar promoção</a>
            ))}</div>
          </div>
        )}
      </section>

      <section className="card stack">
        <h2>Promoções</h2>
        {lista.length === 0 ? <p className="sm sec">Nenhuma promoção ainda.</p> : (
          <div className="list">{lista.map((p) => (
            <div key={p.id} className="item">
              <span><span className="t">{p.nome}</span> <span className={`bd ${p.ativa ? "ok" : "mu"}`}>{p.ativa ? "valendo" : "pausada"}</span>
                <span className="sm sec" style={{ display: "block" }}>{descreverPromocao(p)}{p.servico_ids ? ` · ${p.servico_ids.map((id) => nomeSrv.get(id) ?? "serviço").join(", ")}` : " · todos os serviços"}{p.valida_ate ? ` · até ${p.valida_ate.split("-").reverse().join("/")}` : ""}</span></span>
              <div className="row" style={{ gap: 6 }}>
                <form action={alternarPromocao}><input type="hidden" name="id" value={p.id} /><input type="hidden" name="ativa" value={p.ativa ? "0" : "1"} /><button className="btn ghost sm" type="submit">{p.ativa ? "Pausar" : "Ligar"}</button></form>
                <form action={apagarPromocao}><input type="hidden" name="id" value={p.id} /><button className="btn ghost sm" type="submit">Apagar</button></form>
              </div>
            </div>
          ))}</div>
        )}
      </section>

      <section className="card stack" id="nova">
        <h2>Nova promoção</h2>
        <AcaoForm action={criarPromocao}>
          <fieldset className="pub-pergunta"><legend>Tipo</legend>
            <label><input type="radio" name="tipo" value="horario" defaultChecked /> Dia e horário fixos (ex.: terça de manhã)</label>
            <label><input type="radio" name="tipo" value="ultima_hora" /> Última hora (horários que sobraram para hoje)</label>
          </fieldset>
          <div className="grid2">
            <div className="field"><label htmlFor="pn">Nome (aparece para a cliente)</label><input id="pn" name="nome" maxLength={60} placeholder="Ex.: Terça da escova" defaultValue={sugerida ? `${DIAS_CURTOS[sugDia]} com desconto` : ""} /></div>
            <div className="field"><label htmlFor="pp">Desconto (%)</label><input id="pp" name="percentual" type="number" min={5} max={70} defaultValue={20} required /></div>
          </div>
          <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Dias (no tipo dia e horário)</span>
            <div className="row">{[1, 2, 3, 4, 5, 6, 7].map((d) => (
              <label key={d} className="chip" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
                <input type="checkbox" name="dias" value={d} defaultChecked={sugerida ? d === sugDia : false} />{DIAS_CURTOS[d]}
              </label>))}</div></div>
          <div className="grid2">
            <div className="field"><label htmlFor="phi">Das (opcional)</label><input id="phi" name="hora_inicio" type="time" defaultValue={sugerida ? hh(sugHora) : ""} /></div>
            <div className="field"><label htmlFor="phf">Até (opcional)</label><input id="phf" name="hora_fim" type="time" defaultValue={sugerida ? hh(Math.min(23, sugHora + 2)) : ""} /></div>
            <div className="field"><label htmlFor="pha">Última hora: horários que começam em até</label>
              <select id="pha" name="horas_antes" defaultValue="3">{[1, 2, 3, 4, 6, 12, 24].map((h) => <option key={h} value={h}>{h} hora{h > 1 ? "s" : ""}</option>)}</select></div>
            <div className="field"><label htmlFor="pva">Vale até (opcional)</label><input id="pva" name="valida_ate" type="date" /></div>
          </div>
          <details className="stack">
            <summary className="sm" style={{ cursor: "pointer" }}>Só para alguns serviços (sem marcar nada, vale para todos)</summary>
            <div className="row" style={{ marginTop: 8 }}>{(srvs ?? []).map((s) => (
              <label key={s.id} className="chip" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}><input type="checkbox" name="servicos" value={s.id} />{s.nome}</label>
            ))}</div>
          </details>
          <p className="cap muted" style={{ margin: 0 }}>A promoção aparece no link de agendamento com o preço já com desconto, e o desconto entra sozinho na comanda de quem marcar nesse horário.</p>
          <div><Enviar>Criar promoção</Enviar></div>
        </AcaoForm>
      </section>
    </div>
  );
}
