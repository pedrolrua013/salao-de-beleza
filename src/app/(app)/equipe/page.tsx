import { redirect } from "next/navigation";
import { reais } from "@/lib/dinheiro";
import { dataLocal } from "@/lib/slots";
import { PERMISSOES, pode, type Permissao } from "@/lib/permissoes";
import { CampoTelefone } from "@/components/campo-telefone";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import type { Jornada } from "@/lib/types";
import { alternarAtivo, convidar, salvarJornada, salvarPermissoes, salvarMeta, apagarMeta } from "./actions";

export const metadata = { title: "Equipe" };
const ROTULO = { admin: "Administrador", profissional: "Profissional", recepcao: "Recepção" } as const;
const DIAS = [[1, "Seg"], [2, "Ter"], [3, "Qua"], [4, "Qui"], [5, "Sex"], [6, "Sáb"], [7, "Dom"]] as const;
const h5 = (t: string | null) => (t ? t.slice(0, 5) : "");

type Linha = Jornada & { user_id: string; nome: string; papel: keyof typeof ROTULO; ativo: boolean; telefone: string | null; avisos_whatsapp: boolean; permissoes: Record<string, unknown> | null };

export default async function Equipe() {
  const { supabase, membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/hoje");
  const mesAtual = dataLocal(new Date(), salao.fuso).slice(0, 7);
  const { data: metas } = await supabase.from("metas").select("id, membro_id, mes, tipo, valor").gte("mes", `${mesAtual}-01`).order("mes").order("tipo");
  const { data } = await supabase.from("membros").select("user_id, nome, papel, ativo, dias_semana, entrada, saida, almoco_inicio, almoco_fim, telefone, avisos_whatsapp, permissoes").order("nome");
  const resumo = (m: Linha) => {
    const dias = m.dias_semana ?? salao.dias_semana;
    const txt = DIAS.filter(([n]) => dias.includes(n)).map(([, t]) => t).join(", ");
    const horas = `${h5(m.entrada ?? salao.abre)}–${h5(m.saida ?? salao.fecha)}`;
    return `${txt} · ${horas}${m.almoco_inicio ? ` · almoço ${h5(m.almoco_inicio)}–${h5(m.almoco_fim)}` : ""}`;
  };
  return (
    <div className="stack-lg">
      <h1>Equipe</h1>
      <section className="card stack">
        <div className="list">
          {((data ?? []) as Linha[]).map((m) => (
            <div key={m.user_id} className="item eq-item">
              <span>
                <span className="t" style={{ opacity: m.ativo ? 1 : 0.5 }}>{m.nome}</span> <span className="sm sec">· {ROTULO[m.papel]}</span>
                {m.papel !== "recepcao" && <span className="cap muted eq-jornada">{resumo(m)}</span>}
              </span>
              <div className="row">
                {!m.ativo && <span className="bd mu">Inativo</span>}
                {m.user_id !== membro.user_id && (
                  <form action={alternarAtivo}>
                    <input type="hidden" name="id" value={m.user_id} /><input type="hidden" name="ativo" value={String(m.ativo)} />
                    <button className="btn sec sm" type="submit">{m.ativo ? "Desativar" : "Reativar"}</button>
                  </form>
                )}
              </div>
              {m.papel !== "admin" && (
                <details className="srv-editar">
                  <summary className="btn sec sm">Permissões</summary>
                  <AcaoForm action={salvarPermissoes}>
                    <input type="hidden" name="id" value={m.user_id} />
                    <div className="stack" style={{ gap: 6 }}>{(Object.keys(PERMISSOES) as Permissao[]).map((k) => (
                      <label key={k} className="chip" style={{ display: "flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}>
                        <input type="checkbox" name="perm" value={k} defaultChecked={pode({ papel: m.papel, permissoes: m.permissoes }, k)} />{PERMISSOES[k]}
                      </label>))}</div>
                    <p className="cap muted" style={{ margin: 0 }}>O administrador sempre pode tudo. O sistema confere de novo no banco: quem não tem a permissão não consegue nem por fora da tela.</p>
                    <div><Enviar>Salvar permissões</Enviar></div>
                  </AcaoForm>
                </details>
              )}
              {m.papel !== "recepcao" && (
                  <details className="srv-editar">
                    <summary className="btn sec sm">Jornada</summary>
                    <AcaoForm action={salvarJornada}>
                      <input type="hidden" name="id" value={m.user_id} />
                      <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Dias de trabalho</span>
                        <div className="row">{DIAS.map(([n, t]) => (
                          <label key={n} className="chip" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
                            <input type="checkbox" name="dias" value={n} defaultChecked={(m.dias_semana ?? salao.dias_semana).includes(n)} />{t}
                          </label>))}</div></div>
                      <div className="grid2">
                        <div className="field"><label htmlFor={`en-${m.user_id}`}>Entrada</label><input id={`en-${m.user_id}`} name="entrada" type="time" defaultValue={h5(m.entrada)} placeholder={h5(salao.abre)} /></div>
                        <div className="field"><label htmlFor={`sa-${m.user_id}`}>Saída</label><input id={`sa-${m.user_id}`} name="saida" type="time" defaultValue={h5(m.saida)} /></div>
                        <div className="field"><label htmlFor={`ai-${m.user_id}`}>Almoço, início</label><input id={`ai-${m.user_id}`} name="almoco_inicio" type="time" defaultValue={h5(m.almoco_inicio)} /></div>
                        <div className="field"><label htmlFor={`af-${m.user_id}`}>Almoço, fim</label><input id={`af-${m.user_id}`} name="almoco_fim" type="time" defaultValue={h5(m.almoco_fim)} /></div>
                        <div className="field"><label htmlFor={`tl-${m.user_id}`}>Celular (WhatsApp)</label><CampoTelefone id={`tl-${m.user_id}`} name="telefone" defaultValue={m.telefone} /></div>
                      </div>
                      <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}>
                        <input type="checkbox" name="avisos_whatsapp" defaultChecked={m.avisos_whatsapp} />Avisar no WhatsApp quando entrar, mudar ou cancelar horário na agenda dele
                      </label>
                      <p className="cap muted" style={{ margin: 0 }}>Entrada e saída em branco seguem o horário do salão ({h5(salao.abre)}–{h5(salao.fecha)}). No almoço a pausa de uma química pode continuar correndo.</p>
                      <div><Enviar>Salvar jornada</Enviar></div>
                    </AcaoForm>
                  </details>
                )}
            </div>
          ))}
        </div>
      </section>
      <section className="card stack" id="metas">
        <h2>Metas do mês</h2>
        <p className="sm sec">Cada profissional vê a própria meta (e a do salão) na tela Hoje, com o ritmo do mês.</p>
        {(metas ?? []).length > 0 && (
          <div className="list">{(metas ?? []).map((m) => (
            <div key={m.id} className="item">
              <span><span className="t">{({ faturamento: "Faturamento", produtos: "Venda de produtos", atendimentos: "Atendimentos" } as Record<string, string>)[m.tipo]}</span>
                <span className="sm sec"> · {m.membro_id ? ((data ?? []) as Linha[]).find((x) => x.user_id === m.membro_id)?.nome ?? "Profissional" : "Salão"} · {String(m.mes).slice(5, 7)}/{String(m.mes).slice(0, 4)} · {m.tipo === "atendimentos" ? m.valor : reais(m.valor)}</span></span>
              <form action={apagarMeta}><input type="hidden" name="id" value={m.id} /><button className="btn ghost sm" type="submit">Apagar</button></form>
            </div>
          ))}</div>
        )}
        <AcaoForm action={salvarMeta}>
          <div className="grid2">
            <div className="field"><label htmlFor="mq">De quem</label><select id="mq" name="membro_id" defaultValue=""><option value="">Salão (todos)</option>{((data ?? []) as Linha[]).filter((x) => x.ativo && x.papel !== "recepcao").map((x) => <option key={x.user_id} value={x.user_id}>{x.nome}</option>)}</select></div>
            <div className="field"><label htmlFor="mt">Meta de</label><select id="mt" name="tipo" defaultValue="faturamento"><option value="faturamento">Faturamento (R$)</option><option value="produtos">Venda de produtos (R$)</option><option value="atendimentos">Atendimentos (quantidade)</option></select></div>
            <div className="field"><label htmlFor="mv">Valor</label><input id="mv" name="valor" inputMode="decimal" required placeholder="Ex.: 15000" /></div>
            <div className="field"><label htmlFor="mm">Mês</label><input id="mm" name="mes" type="month" defaultValue={mesAtual} required /></div>
          </div>
          <div><Enviar>Salvar meta</Enviar></div>
        </AcaoForm>
      </section>

      <section className="card stack">
        <h2>Convidar pessoa</h2>
        <p className="sm sec">A pessoa recebe um e-mail para criar a senha.</p>
        <AcaoForm action={convidar}>
          <div className="grid2">
            <div className="field"><label htmlFor="nome">Nome</label><input id="nome" name="nome" required minLength={2} maxLength={120} /></div>
            <div className="field"><label htmlFor="email">E-mail</label><input id="email" name="email" type="email" required /></div>
            <div className="field"><label htmlFor="papel">Papel</label>
              <select id="papel" name="papel" defaultValue="recepcao"><option value="recepcao">Recepção</option><option value="profissional">Profissional</option><option value="admin">Administrador</option></select></div>
          </div>
          <div><Enviar>Enviar convite</Enviar></div>
        </AcaoForm>
      </section>
    </div>
  );
}
