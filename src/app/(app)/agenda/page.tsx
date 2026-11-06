import Link from "next/link";
import { CampoData } from "@/components/campo-data";
import { Vazio } from "@/components/ilustracoes";
import { exigirMembro } from "@/lib/auth";
import { carregarBloqueios, carregarDia, carregarProfissionais } from "@/lib/agenda";
import { descreverFases, type Fase } from "@/lib/fases";
import { dataLocal, somarDias } from "@/lib/slots";
import { dataLonga } from "@/lib/format";
import { Linha } from "@/components/linha-agenda";
import { GradeAgenda } from "@/components/grade-agenda";
import { ArrastarAgenda } from "@/components/arrastar-agenda";
import { AcaoForm, Enviar } from "@/components/acao-form";
import type { Bloqueio } from "@/lib/types";
import { criarBloqueio } from "./actions";
import { FormAgendamento } from "./form-agendamento";
import { ListaEspera } from "./lista-espera";

export const metadata = { title: "Agenda" };

export default async function Agenda({ searchParams }: { searchParams: Promise<{ data?: string; modo?: string; cliente?: string }> }) {
  const { data: q, modo, cliente: clientePadrao = "" } = await searchParams;
  const { supabase, membro, salao } = await exigirMembro();
  const agora = new Date();
  const hoje = dataLocal(agora, salao.fuso);
  const data = q && /^\d{4}-\d{2}-\d{2}$/.test(q) ? q : hoje;
  const lista = modo === "lista";
  const [dia, profs, bloqueios, { data: clienteInicial }, { data: servicos }] = await Promise.all([
    carregarDia(supabase, salao, data),
    carregarProfissionais(supabase, salao, data),
    carregarBloqueios(supabase, salao, data),
    clientePadrao ? supabase.from("clientes").select("id, nome, telefone").eq("id", clientePadrao).maybeSingle() : Promise.resolve({ data: null }),
    supabase.from("servicos").select("id, nome, fases, servico_variacoes(id, nome, preco_centavos, fases, ordem)").eq("ativo", true).order("nome"),
  ]);
  const ehProf = membro.papel === "profissional";
  // O profissional vê a própria coluna primeiro.
  const colunas = ehProf ? [...profs.filter((p) => p.id === membro.user_id), ...profs.filter((p) => p.id !== membro.user_id)] : profs;
  const podeRemover = (b: Bloqueio) => !ehProf || b.profissional_id === membro.user_id;
  const link = (d: string, m = modo) => `/agenda?data=${d}${m === "lista" ? "&modo=lista" : ""}`;
  const profPadrao = ehProf ? membro.user_id : profs.length === 1 ? profs[0].id : "";
  return (
    <div className="stack-lg">
      <div className="row between">
        <h1>Agenda</h1>
        <div className="date-nav">
          <Link className="btn sec sm" href={link(somarDias(data, -1))} aria-label="Dia anterior">←</Link>
          <Link className="btn sec sm" href={link(hoje)}>Hoje</Link>
          <Link className="btn sec sm" href={link(somarDias(data, 1))} aria-label="Próximo dia">→</Link>
        </div>
      </div>
      <div className="row between">
        <p className="sec" style={{ fontWeight: 500 }}>{dataLonga(data)}</p>
        <div className="seg" role="group" aria-label="Modo de ver">
          <Link href={link(data, "grade")} aria-current={!lista ? "page" : undefined}>Colunas</Link>
          <Link href={link(data, "lista")} aria-current={lista ? "page" : undefined}>Lista</Link>
        </div>
      </div>
      {!lista && profs.length > 0 && (
        <section className="card grade-card">
          <ArrastarAgenda data={data}>
            <GradeAgenda data={data} dia={dia} profs={colunas} bloqueios={bloqueios} tz={salao.fuso} abre={salao.abre.slice(0, 5)} fecha={salao.fecha.slice(0, 5)}
              agora={data === hoje ? agora : null} podeRemover={podeRemover} />
          </ArrastarAgenda>
          <p className="cap muted grade-leg"><span className="leg trab" aria-hidden="true" /> trabalho <span className="leg pausa" aria-hidden="true" /> pausa (profissional livre para encaixe) <span className="leg bloq" aria-hidden="true" /> bloqueio ou almoço</p>
        </section>
      )}
      <section className="card">
        {!lista && <h2 style={{ marginBottom: 12 }}>Horários do dia</h2>}
        {dia.length === 0 ? <Vazio tipo="agenda">Sem horários marcados neste dia.</Vazio>
          : <div className="ag-lista">{dia.map((a) => <Linha key={a.id} a={a} tz={salao.fuso} papel={membro.papel} usuarioId={membro.user_id} />)}</div>}
      </section>
      <section className="card stack" id="novo">
        <h2>Novo agendamento</h2>
        <FormAgendamento data={data} profPadrao={profPadrao} clienteInicial={clienteInicial ?? null}
          servicos={(servicos ?? []).map((s) => ({ id: s.id, nome: s.nome, descricao: descreverFases(s.fases as Fase[]),
            variacoes: ((s.servico_variacoes ?? []) as { id: string; nome: string; preco_centavos: number; fases: Fase[]; ordem: number }[])
              .sort((a, b) => a.ordem - b.ordem).map((v) => ({ id: v.id, nome: v.nome, descricao: descreverFases(v.fases) })) }))}
          profs={profs.map((p) => ({ id: p.id, nome: p.nome }))} />
      </section>
      <ListaEspera supabase={supabase} data={data}
        servicos={(servicos ?? []).map((s) => ({ id: s.id, nome: s.nome }))} profs={profs.map((p) => ({ id: p.id, nome: p.nome }))} />
      <section className="card stack">
        <h2>Bloquear horário</h2>
        <p className="sm sec">Folga, férias, curso ou compromisso. Ninguém consegue marcar nesse período, nem o robô do WhatsApp. O almoço e os dias de trabalho de cada um ficam em Equipe.</p>
        <AcaoForm action={criarBloqueio}>
          <div className="grid2">
            {!ehProf && (
              <div className="field"><label htmlFor="b-prof">Profissional</label>
                <select id="b-prof" name="profissional_id" required defaultValue={profPadrao}>
                  <option value="" disabled>Escolha</option>
                  {profs.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
                </select></div>
            )}
            <div className="field"><label htmlFor="b-motivo">Motivo (opcional)</label><input id="b-motivo" name="motivo" maxLength={120} placeholder="Férias, curso, médico…" /></div>
            <div className="field"><label htmlFor="b-de">De</label><div className="row" style={{ gap: 8, flexWrap: "nowrap" }}><CampoData id="b-de" name="de_data" defaultValue={data} required /><input name="de_hora" type="time" defaultValue={salao.abre.slice(0, 5)} required aria-label="Hora de início" /></div></div>
            <div className="field"><label htmlFor="b-ate">Até</label><div className="row" style={{ gap: 8, flexWrap: "nowrap" }}><CampoData id="b-ate" name="ate_data" defaultValue={data} required /><input name="ate_hora" type="time" defaultValue={salao.fecha.slice(0, 5)} required aria-label="Hora de fim" /></div></div>
          </div>
          <div><Enviar className="btn sec">Bloquear</Enviar></div>
        </AcaoForm>
      </section>
    </div>
  );
}
