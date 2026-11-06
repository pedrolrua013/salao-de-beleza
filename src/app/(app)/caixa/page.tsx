import Link from "next/link";
import { cancelarCobranca, confirmarCobranca } from "./[id]/extras-actions";
import { BuscaCliente } from "@/components/busca-cliente";
import { Vazio } from "@/components/ilustracoes";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { FORMAS, reais, type Forma } from "@/lib/dinheiro";
import { abrirCaixa, fecharCaixa, movimentarCaixa, novaComanda } from "./actions";
import { ValesAtivos } from "./vales";

export const metadata = { title: "Caixa" };

type Resumo = { formas: Partial<Record<Forma, number>>; comandas: number; receita: number; gorjetas: number; troco_inicial: number; sangrias: number; suprimentos: number; dinheiro_esperado: number };
const quando = (iso: string, tz: string) => new Intl.DateTimeFormat("pt-BR", { timeZone: tz, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(iso)).replace(",", "");

export default async function Caixa({ searchParams }: { searchParams: Promise<{ cliente?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  const { cliente } = await searchParams;
  const { data: clienteInicial } = /^[0-9a-f-]{36}$/.test(cliente ?? "") ? await supabase.from("clientes").select("id, nome, telefone").eq("id", cliente!).maybeSingle() : { data: null };
  const pode = membro.papel !== "profissional";
  const [{ data: aberto }, { data: abertas }, { data: historico }, { data: equipe }] = await Promise.all([
    supabase.from("caixas").select("id, aberto_em, troco_inicial_centavos").is("fechado_em", null).maybeSingle(),
    supabase.from("comandas").select("id, numero, aberta_em, observacao, clientes(nome), comanda_itens(preco_centavos, quantidade, desconto_centavos), desconto_centavos").eq("status", "aberta").order("aberta_em"),
    supabase.from("caixas").select("id, aberto_em, fechado_em, contado, esperado").not("fechado_em", "is", null).order("fechado_em", { ascending: false }).limit(8),
    supabase.from("membros").select("user_id, nome").neq("papel", "recepcao").eq("ativo", true).order("nome"),
  ]);
  const { data: cobs } = pode ? await supabase.from("cobrancas").select("id, tipo, comanda_id, valor_centavos, nome, presente_para, modo, criado_em, clientes(nome)").eq("status", "pendente").gt("expira_em", new Date().toISOString()).order("criado_em", { ascending: false }).limit(20) : { data: [] };
  const resumo = aberto ? ((await supabase.rpc("resumo_caixa", { p_caixa: aberto.id })).data as Resumo | null) : null;
  const totalDe = (c: { desconto_centavos: number; comanda_itens: { preco_centavos: number; quantidade: number; desconto_centavos: number }[] }) =>
    c.comanda_itens.reduce((s, i) => s + i.preco_centavos * i.quantidade - i.desconto_centavos, 0) - c.desconto_centavos;
  return (
    <div className="stack-lg">
      <div className="row between">
        <h1>Caixa</h1>
        <form action={novaComanda} className="row" style={{ gap: 8 }}>
          <div style={{ width: 300, maxWidth: "100%" }}><BuscaCliente name="cliente_id" avulso ariaLabel="Cliente da nova comanda" inicial={clienteInicial} /></div>
          <button className="btn" type="submit">Nova comanda</button>
        </form>
      </div>
      {(cobs ?? []).length > 0 && (
        <section className="card stack">
          <h2>Pix pelo link esperando confirmação</h2>
          <div className="list">{(cobs ?? []).map((b) => (
            <div key={b.id} className="item">
              <span><span className="t">{b.tipo === "vale" ? `Vale-presente para ${b.presente_para}` : b.tipo === "pacote" ? "Pacote pelo link" : "Comanda"}</span>
                <span className="sm sec"> · {(b.clientes as unknown as { nome: string } | null)?.nome ?? b.nome ?? "Cliente"} · {reais(b.valor_centavos)}{b.modo === "mercadopago" ? " · confirma sozinho pelo Mercado Pago" : ""}</span></span>
              <div className="row" style={{ gap: 6 }}>
                {b.comanda_id && <Link className="btn ghost sm" href={`/caixa/${b.comanda_id}`}>Abrir comanda</Link>}
                {b.modo !== "mercadopago" && <form action={confirmarCobranca}><input type="hidden" name="id" value={b.id} /><input type="hidden" name="comanda_id" value={b.comanda_id ?? ""} /><button className="btn sm" type="submit">O Pix caiu: confirmar</button></form>}
                <form action={cancelarCobranca}><input type="hidden" name="id" value={b.id} /><button className="btn ghost sm" type="submit">Cancelar</button></form>
              </div>
            </div>
          ))}</div>
          <p className="cap muted" style={{ margin: 0 }}>Vale e pacote comprados pelo link viram uma comanda aberta “Venda pelo link” depois de confirmados: feche-a no caixa para liberar o vale ou o pacote.</p>
        </section>
      )}

      <section className="card stack">
        <h2>Comandas abertas</h2>
        {(abertas ?? []).length === 0 ? <Vazio tipo="agenda">Nenhuma comanda aberta. Na agenda, toque em Comanda no horário da cliente.</Vazio> : (
          <div className="list">
            {(abertas ?? []).map((c) => (
              <Link key={c.id} href={`/caixa/${c.id}`} className="item" style={{ textDecoration: "none", color: "var(--ink)" }}>
                <span><span className="t">#{c.numero} · {(c.clientes as unknown as { nome: string } | null)?.nome ?? "Cliente avulso"}</span> <span className="sm sec">· desde {quando(c.aberta_em, salao.fuso)}</span>{c.observacao === "Venda pelo link" && <span className="bd br">Venda pelo link: feche para liberar</span>}</span>
                <strong>{reais(totalDe(c as never))}</strong>
              </Link>
            ))}
          </div>
        )}
      </section>

      {!aberto ? (
        <section className="card stack">
          <h2>Caixa fechado</h2>
          {pode ? (
            <AcaoForm action={abrirCaixa} className="row">
              <div className="field" style={{ minWidth: 180 }}><label htmlFor="troco">Troco na gaveta (R$)</label><input id="troco" name="troco" inputMode="decimal" placeholder="0,00" /></div>
              <div style={{ alignSelf: "flex-end" }}><Enviar>Abrir caixa</Enviar></div>
            </AcaoForm>
          ) : <p className="sm sec">Peça à recepção para abrir o caixa. Você pode lançar itens nas comandas mesmo assim.</p>}
        </section>
      ) : (
        <section className="card stack">
          <div className="row between"><h2>Caixa aberto</h2><span className="sm sec">desde {quando(aberto.aberto_em, salao.fuso)}</span></div>
          {resumo && (
            <div className="kpis">
              <div className="kpi"><span className="cap sec">Receita do salão</span><strong>{reais(resumo.receita)}</strong><span className="cap muted">{resumo.comandas} comandas</span></div>
              <div className="kpi"><span className="cap sec">Dinheiro na gaveta</span><strong>{reais(resumo.dinheiro_esperado)}</strong><span className="cap muted">troco {reais(resumo.troco_inicial)} · retiradas {reais(resumo.sangrias)}</span></div>
              <div className="kpi"><span className="cap sec">Gorjetas</span><strong>{reais(resumo.gorjetas)}</strong><span className="cap muted">vão para os profissionais</span></div>
              {(Object.keys(FORMAS) as Forma[]).filter((k) => k !== "dinheiro" && resumo.formas[k]).map((k) => (
                <div className="kpi" key={k}><span className="cap sec">{FORMAS[k]}</span><strong>{reais(resumo.formas[k]!)}</strong></div>
              ))}
            </div>
          )}
          {pode && (
            <>
              <details className="aj"><summary>Retirada, vale ou entrada de troco</summary>
                <div className="aj-corpo">
                  <AcaoForm action={movimentarCaixa} className="row">
                    <input type="hidden" name="caixa_id" value={aberto.id} />
                    <div className="field"><label htmlFor="mt">Tipo</label><select id="mt" name="tipo"><option value="sangria">Retirada (sangria)</option><option value="suprimento">Entrada de troco</option><option value="vale">Vale para profissional</option></select></div>
                    <div className="field"><label htmlFor="mpf">Profissional (só para vale)</label><select id="mpf" name="profissional_id" defaultValue=""><option value="">—</option>{(equipe ?? []).map((m) => <option key={m.user_id} value={m.user_id}>{m.nome}</option>)}</select></div>
                    <div className="field" style={{ width: 130 }}><label htmlFor="mv">Valor (R$)</label><input id="mv" name="valor" inputMode="decimal" required /></div>
                    <div className="field" style={{ flex: 1, minWidth: 160 }}><label htmlFor="mm">Motivo</label><input id="mm" name="motivo" maxLength={200} /></div>
                    <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Registrar</Enviar></div>
                  </AcaoForm>
                </div>
              </details>
              <details className="aj"><summary>Fechar o caixa</summary>
                <div className="aj-corpo stack">
                  <p className="sm">Conte o que entrou em cada forma e informe abaixo. O sistema compara com o esperado e guarda a diferença. Comandas ainda abertas passam para o próximo caixa.</p>
                  <AcaoForm action={fecharCaixa}>
                    <input type="hidden" name="caixa_id" value={aberto.id} />
                    <div className="grid2">
                      {(["dinheiro", "pix", "debito", "credito"] as Forma[]).map((k) => (
                        <div className="field" key={k}><label htmlFor={`c_${k}`}>{FORMAS[k]} contado <span className="muted">(esperado {reais(k === "dinheiro" ? resumo?.dinheiro_esperado ?? 0 : resumo?.formas[k] ?? 0)})</span></label><input id={`c_${k}`} name={`c_${k}`} inputMode="decimal" /></div>
                      ))}
                    </div>
                    <div className="field"><label htmlFor="obs">Observação</label><input id="obs" name="obs" maxLength={500} /></div>
                    <div><Enviar>Fechar caixa</Enviar></div>
                  </AcaoForm>
                </div>
              </details>
            </>
          )}
        </section>
      )}

      <ValesAtivos supabase={supabase} fuso={salao.fuso} />

      {(historico ?? []).length > 0 && (
        <section className="card stack">
          <h2>Caixas anteriores</h2>
          <div className="list">
            {(historico ?? []).map((h) => {
              const esp = (h.esperado ?? {}) as Resumo, cont = (h.contado ?? {}) as Partial<Record<Forma, number>>;
              const dif = cont.dinheiro !== undefined ? cont.dinheiro - (esp.dinheiro_esperado ?? 0) : null;
              return (
                <div key={h.id} className="item">
                  <span><span className="t">{quando(h.aberto_em, salao.fuso)} → {quando(h.fechado_em!, salao.fuso)}</span> <span className="sm sec">· receita {reais(esp.receita ?? 0)}</span></span>
                  {dif !== null && <span className={`bd ${dif === 0 ? "ok" : "no"}`}>{dif === 0 ? "Dinheiro conferido" : `Diferença ${reais(dif)}`}</span>}
                </div>
              );
            })}
          </div>
        </section>
      )}
    </div>
  );
}
