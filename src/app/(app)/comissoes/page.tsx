import Link from "next/link";
import { pode } from "@/lib/permissoes";
import { CampoData } from "@/components/campo-data";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { reais } from "@/lib/dinheiro";
import { dataLocal } from "@/lib/slots";
import { dataBR } from "@/lib/format";
import { lancarVale, pagar, removerRegra, removerVale, salvarExcecao, salvarPadrao, salvarTaxas, salvarVinculo } from "./actions";

export const metadata = { title: "Comissões" };

const VINC = { socio: "Sócio (sem comissão)", clt: "CLT", parceiro: "Salão-parceiro (Lei 13.352)", autonomo: "Autônomo" } as const;
type Regra = { id: string; tipo: "servico" | "produto"; profissional_id: string | null; servico_id: string | null; percentual: number; assistente_percentual: number };
type M = { user_id: string; nome: string; papel: string; ativo: boolean; vinculo: keyof typeof VINC; documento: string | null; contrato_inicio: string | null; contrato_fim: string | null; contrato_homologado_em: string | null };

export default async function Comissoes({ searchParams }: { searchParams: Promise<{ de?: string; ate?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "comissoes")) redirect(membro.papel === "profissional" ? "/extrato" : "/hoje");
  const admin = membro.papel === "admin";
  const hoje = dataLocal(new Date(), salao.fuso);
  const q = await searchParams;
  const de = q.de && /^\d{4}-\d{2}-\d{2}$/.test(q.de) ? q.de : `${hoje.slice(0, 8)}01`;
  const ate = q.ate && /^\d{4}-\d{2}-\d{2}$/.test(q.ate) ? q.ate : hoje;
  const [{ data: rs }, { data: ms }, { data: srvs }, { data: pend }, { data: vs }, { data: fs }] = await Promise.all([
    supabase.from("regras_comissao").select("*"),
    supabase.from("membros").select("user_id, nome, papel, ativo, vinculo, documento, contrato_inicio, contrato_fim, contrato_homologado_em").order("nome"),
    supabase.from("servicos").select("id, nome").eq("avulso", false).order("nome"),
    admin ? supabase.from("comissoes").select("profissional_id, papel, valor_centavos").is("fechamento_id", null).gte("competencia", de).lte("competencia", ate) : Promise.resolve({ data: [] }),
    supabase.from("vales").select("id, profissional_id, valor_centavos, data, motivo").is("fechamento_id", null).order("data", { ascending: false }),
    admin ? supabase.from("fechamentos_comissao").select("*").order("pago_em", { ascending: false }).limit(12) : Promise.resolve({ data: [] }),
  ]);
  const regras = (rs ?? []) as Regra[];
  const membros = (ms ?? []) as M[];
  const equipe = membros.filter((m) => m.papel !== "recepcao" && m.ativo);
  const nome = new Map(membros.map((m) => [m.user_id, m.nome]));
  const nomeSrv = new Map((srvs ?? []).map((s) => [s.id, s.nome as string]));
  const padrao = (t: "servico" | "produto") => regras.find((r) => r.tipo === t && !r.profissional_id && !r.servico_id);
  const excecoes = regras.filter((r) => r.profissional_id || r.servico_id);
  const vales = (vs ?? []) as { id: string; profissional_id: string; valor_centavos: number; data: string; motivo: string | null }[];
  const aPagar = equipe.map((m) => {
    const minhas = (pend ?? []).filter((c) => c.profissional_id === m.user_id);
    const com = minhas.filter((c) => c.papel !== "gorjeta").reduce((s, c) => s + c.valor_centavos, 0);
    const gor = minhas.filter((c) => c.papel === "gorjeta").reduce((s, c) => s + c.valor_centavos, 0);
    const val = vales.filter((v) => v.profissional_id === m.user_id && v.data <= ate).reduce((s, v) => s + v.valor_centavos, 0);
    return { m, com, gor, val, total: com + gor - val };
  }).filter((x) => x.com || x.gor || x.val);
  const alertas = equipe.filter((m) => m.vinculo === "parceiro").flatMap((m) => {
    const a: string[] = [];
    if (!m.documento) a.push(`${m.nome}: falta o CNPJ do profissional-parceiro.`);
    if (!m.contrato_inicio) a.push(`${m.nome}: cadastre a data do contrato de parceria.`);
    else if (!m.contrato_homologado_em) a.push(`${m.nome}: contrato sem homologação no sindicato registrada.`);
    if (m.contrato_fim && m.contrato_fim < hoje) a.push(`${m.nome}: contrato venceu em ${dataBR(m.contrato_fim)}.`);
    else if (m.contrato_fim && m.contrato_fim <= dataLocal(new Date(Date.now() + 30 * 86_400_000), salao.fuso)) a.push(`${m.nome}: contrato vence em ${dataBR(m.contrato_fim)}.`);
    return a;
  });
  const s = salao;

  return (
    <div className="stack-lg">
      <div className="row between"><h1>Comissões</h1>{admin && <Link className="btn sec" href={`/comissoes/parceria?de=${de}&ate=${ate}`}>Relatório Salão Parceiro</Link>}</div>
      {admin && alertas.length > 0 && (
        <div className="aviso" role="status"><strong>Salão-parceiro: pendências que podem virar vínculo trabalhista</strong><ul>{alertas.map((a) => <li key={a}>{a}</li>)}</ul></div>
      )}

      {admin && (
        <section className="card stack">
          <div className="row between">
            <h2>A pagar</h2>
            <form className="row" style={{ gap: 8 }}>
              <CampoData name="de" defaultValue={de} ariaLabel="De" required /><CampoData name="ate" defaultValue={ate} ariaLabel="Até" required />
              <button className="btn sec sm" type="submit">Ver período</button>
            </form>
          </div>
          {aPagar.length === 0 ? <p className="sm sec">Nada pendente nesse período.</p> : (
            <div className="list">
              {aPagar.map(({ m, com, gor, val, total }) => (
                <div key={m.user_id} className="item srv-item">
                  <span><Link className="t" href={`/extrato?prof=${m.user_id}&de=${de}&ate=${ate}`}>{m.nome}</Link> <span className="sm sec">· comissões {reais(com)} · gorjetas {reais(gor)}{val ? ` · vales −${reais(val)}` : ""}</span></span>
                  <AcaoForm action={pagar} className="row">
                    <input type="hidden" name="profissional_id" value={m.user_id} /><input type="hidden" name="de" value={de} /><input type="hidden" name="ate" value={ate} />
                    <strong>{reais(total)}</strong>
                    <select name="forma" aria-label={`Forma de pagamento para ${m.nome}`} defaultValue="Pix"><option>Pix</option><option>Dinheiro</option><option>Transferência</option></select>
                    <Enviar className="btn sm">Registrar pagamento</Enviar>
                  </AcaoForm>
                </div>
              ))}
            </div>
          )}
          <p className="cap muted">Registrar o pagamento fecha as comissões e os vales do período: ninguém mais altera esses valores, e a comprovação fica no relatório.</p>
        </section>
      )}

      <section className="card stack">
        <h2>Vales (adiantamentos)</h2>
        <AcaoForm action={lancarVale} className="row">
          <div className="field"><label htmlFor="vp">Profissional</label><select id="vp" name="profissional_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{equipe.map((m) => <option key={m.user_id} value={m.user_id}>{m.nome}</option>)}</select></div>
          <div className="field" style={{ width: 130 }}><label htmlFor="vv">Valor (R$)</label><input id="vv" name="valor" inputMode="decimal" required /></div>
          <div className="field" style={{ flex: 1, minWidth: 160 }}><label htmlFor="vm">Motivo</label><input id="vm" name="motivo" maxLength={200} /></div>
          <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Lançar vale</Enviar></div>
        </AcaoForm>
        {vales.length > 0 && (
          <div className="list">
            {vales.map((v) => (
              <div key={v.id} className="item">
                <span><span className="t">{nome.get(v.profissional_id)}</span> <span className="sm sec">· {dataBR(v.data)}{v.motivo ? ` · ${v.motivo}` : ""}</span></span>
                <div className="row"><strong>{reais(v.valor_centavos)}</strong>{admin && <form action={removerVale}><input type="hidden" name="id" value={v.id} /><button className="btn ghost sm" type="submit">Remover</button></form>}</div>
              </div>
            ))}
          </div>
        )}
      </section>

      {admin && (
        <>
          <section className="card stack">
            <h2>Regras de comissão</h2>
            <AcaoForm action={salvarPadrao} className="row">
              <div className="field" style={{ width: 150 }}><label htmlFor="ps">Serviços (%)</label><input id="ps" name="servico" inputMode="decimal" defaultValue={padrao("servico")?.percentual ?? 0} /></div>
              <div className="field" style={{ width: 170 }}><label htmlFor="pa">Assistente (% do serviço)</label><input id="pa" name="assistente" inputMode="decimal" defaultValue={padrao("servico")?.assistente_percentual ?? 0} /></div>
              <div className="field" style={{ width: 150 }}><label htmlFor="pp">Venda de produto (%)</label><input id="pp" name="produto" inputMode="decimal" defaultValue={padrao("produto")?.percentual ?? 0} /></div>
              <div style={{ alignSelf: "flex-end" }}><Enviar>Salvar padrão</Enviar></div>
            </AcaoForm>
            <h3>Exceções</h3>
            <p className="sm sec">A regra mais específica vence: profissional + serviço, depois só profissional, depois só serviço, depois o padrão.</p>
            {excecoes.length > 0 && (
              <div className="list">
                {excecoes.map((r) => (
                  <div key={r.id} className="item">
                    <span><span className="t">{r.profissional_id ? nome.get(r.profissional_id) : "Todos"} · {r.tipo === "produto" ? "produtos" : r.servico_id ? nomeSrv.get(r.servico_id) : "todos os serviços"}</span> <span className="sm sec">· {r.percentual}%{r.assistente_percentual ? ` · assistente ${r.assistente_percentual}%` : ""}</span></span>
                    <form action={removerRegra}><input type="hidden" name="id" value={r.id} /><button className="btn ghost sm" type="submit">Remover</button></form>
                  </div>
                ))}
              </div>
            )}
            <AcaoForm action={salvarExcecao}>
              <div className="grid2">
                <div className="field"><label htmlFor="et">Tipo</label><select id="et" name="tipo" defaultValue="servico"><option value="servico">Serviço</option><option value="produto">Venda de produto</option></select></div>
                <div className="field"><label htmlFor="epr">Profissional</label><select id="epr" name="profissional_id" defaultValue=""><option value="">Todos</option>{equipe.map((m) => <option key={m.user_id} value={m.user_id}>{m.nome}</option>)}</select></div>
                <div className="field"><label htmlFor="es">Serviço</label><select id="es" name="servico_id" defaultValue=""><option value="">Todos</option>{(srvs ?? []).map((x) => <option key={x.id} value={x.id}>{x.nome}</option>)}</select></div>
                <div className="field"><label htmlFor="ep">Comissão (%)</label><input id="ep" name="percentual" inputMode="decimal" required /></div>
                <div className="field"><label htmlFor="ea">Assistente (%)</label><input id="ea" name="assistente" inputMode="decimal" /></div>
              </div>
              <div><Enviar className="btn sec">Adicionar exceção</Enviar></div>
            </AcaoForm>
          </section>

          <section className="card stack">
            <h2>Taxas e base de cálculo</h2>
            <AcaoForm action={salvarTaxas}>
              <div className="grid2">
                <div className="field"><label htmlFor="td">Taxa do débito (%)</label><input id="td" name="taxa_debito" inputMode="decimal" defaultValue={s.taxa_debito} /></div>
                <div className="field"><label htmlFor="tc">Taxa do crédito à vista (%)</label><input id="tc" name="taxa_credito" inputMode="decimal" defaultValue={s.taxa_credito} /></div>
                <div className="field"><label htmlFor="tcp">Taxa do crédito parcelado (%)</label><input id="tcp" name="taxa_credito_parcelado" inputMode="decimal" defaultValue={s.taxa_credito_parcelado} /></div>
                <div className="field"><label htmlFor="tp">Taxa do Pix (%)</label><input id="tp" name="taxa_pix" inputMode="decimal" defaultValue={s.taxa_pix} /></div>
              </div>
              <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="desconta_taxa" defaultChecked={s.comissao_desconta_taxa} />Descontar a taxa do cartão antes de calcular a comissão</label>
              <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="desconta_custo" defaultChecked={s.comissao_desconta_custo} />Descontar o custo de produto do serviço (definido em Catálogos)</label>
              <p className="cap muted">Para profissional CLT o sistema nunca desconta taxa nem produto, como mandam as convenções coletivas. Para parceiro e autônomo, só se estiver no contrato.</p>
              <div><Enviar>Salvar taxas</Enviar></div>
            </AcaoForm>
          </section>

          <section className="card stack">
            <h2>Vínculo de cada profissional</h2>
            <div className="list">
              {membros.filter((m) => m.papel !== "recepcao").map((m) => (
                <div key={m.user_id} className="item eq-item">
                  <span><span className="t">{m.nome}</span> <span className="sm sec">· {VINC[m.vinculo]}</span></span>
                  <details className="srv-editar">
                    <summary className="btn sec sm">Editar vínculo</summary>
                    <AcaoForm action={salvarVinculo}>
                      <input type="hidden" name="id" value={m.user_id} />
                      <div className="grid2">
                        <div className="field"><label htmlFor={`vi-${m.user_id}`}>Vínculo</label><select id={`vi-${m.user_id}`} name="vinculo" defaultValue={m.vinculo}>{Object.entries(VINC).map(([k, t]) => <option key={k} value={k}>{t}</option>)}</select></div>
                        <div className="field"><label htmlFor={`do-${m.user_id}`}>CPF ou CNPJ</label><input id={`do-${m.user_id}`} name="documento" defaultValue={m.documento ?? ""} inputMode="numeric" /></div>
                        <div className="field"><label htmlFor={`ci-${m.user_id}`}>Contrato desde</label><CampoData id={`ci-${m.user_id}`} name="contrato_inicio" defaultValue={m.contrato_inicio} /></div>
                        <div className="field"><label htmlFor={`cf-${m.user_id}`}>Contrato até</label><CampoData id={`cf-${m.user_id}`} name="contrato_fim" defaultValue={m.contrato_fim} /></div>
                        <div className="field"><label htmlFor={`ch-${m.user_id}`}>Homologado no sindicato em</label><CampoData id={`ch-${m.user_id}`} name="contrato_homologado_em" defaultValue={m.contrato_homologado_em} /></div>
                      </div>
                      <div><Enviar>Salvar vínculo</Enviar></div>
                    </AcaoForm>
                  </details>
                </div>
              ))}
            </div>
            <p className="cap muted">No salão-parceiro o contrato precisa ser escrito, com duas testemunhas e homologado no sindicato. Sem isso, a relação pode ser considerada emprego. Confirme os detalhes com seu contador.</p>
          </section>

          {(fs ?? []).length > 0 && (
            <section className="card stack">
              <h2>Pagamentos registrados</h2>
              <div className="list">
                {(fs ?? []).map((x) => (
                  <div key={x.id} className="item">
                    <span><span className="t">{nome.get(x.profissional_id)}</span> <span className="sm sec">· {dataBR(x.periodo_inicio)} a {dataBR(x.periodo_fim)} · {x.forma}</span></span>
                    <strong>{reais(x.pago_centavos)}</strong>
                  </div>
                ))}
              </div>
            </section>
          )}
        </>
      )}
    </div>
  );
}
