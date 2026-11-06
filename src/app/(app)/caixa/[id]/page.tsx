import Link from "next/link";
import { GerarLink } from "@/components/gerar-link";
import { adicionarSugestao, cancelarCobranca, cobrarPeloCelular, cobrarTaxa, confirmarCobranca } from "./extras-actions";
import { perdoarTaxa } from "@/app/(app)/clientes/[id]/area-actions";
import { dataCurta } from "@/lib/format";
import { atualizarNota, cancelarNota, emitirNota } from "./nota-actions";
import { QuemFez } from "./quem-fez";
import { BuscaCliente } from "@/components/busca-cliente";
import { notFound } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { pode } from "@/lib/permissoes";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { FORMAS, FORMAS_DIGITADAS, campoReais, reais, type Forma } from "@/lib/dinheiro";
import { dataLocal, somarDias } from "@/lib/slots";
import {
  usarCashback, usarCredito, usarPacote, usarValePresente, adicionarItem, adicionarPagamento, cancelarComanda, abrirCaixaEFechar, fecharComanda, reabrirComanda, removerItem, removerPagamento, salvarComanda,
} from "../actions";

export const metadata = { title: "Comanda" };

type Item = { id: string; tipo: "servico" | "produto" | "gorjeta" | "pacote" | "vale_presente" | "taxa"; descricao: string; servico_id: string | null; produto_id: string | null; profissional_id: string | null; assistente_id: string | null; quantidade: number; preco_centavos: number; desconto_centavos: number };
type Pag = { id: string; forma: Forma; valor_centavos: number; parcelas: number };

export default async function Comanda({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, membro, salao } = await exigirMembro();
  const { data: c } = await supabase.from("comandas").select("id, numero, status, cliente_id, desconto_centavos, caixa_id, clientes(nome)").eq("id", id).maybeSingle();
  if (!c) notFound();
  const [{ data: its }, { data: pgs }, { data: srvs }, { data: prods }, { data: profs }, { data: caixa }] = await Promise.all([
    supabase.from("comanda_itens").select("*").eq("comanda_id", id).order("criado_em"),
    supabase.from("comanda_pagamentos").select("*").eq("comanda_id", id).order("criado_em"),
    supabase.from("servicos").select("id, nome, preco_centavos").eq("ativo", true).order("nome"),
    supabase.from("produtos").select("id, nome, preco_centavos").eq("ativo", true).neq("tipo", "uso").order("nome"),
    supabase.from("membros").select("user_id, nome, papel").eq("ativo", true).order("nome"),
    supabase.from("caixas").select("id").is("fechado_em", null).maybeSingle(),
  ]);
  const itens = (its ?? []) as Item[], pags = (pgs ?? []) as Pag[];
  const nomeCliente = (c.clientes as unknown as { nome: string } | null)?.nome;
  const { data: creditos } = c.cliente_id && c.status === "aberta"
    ? await supabase.from("sinais").select("valor_centavos, agendamentos!inner(cliente_id)").eq("agendamentos.cliente_id", c.cliente_id).in("status", ["pago", "credito"])
    : { data: [] };
  const credito = (creditos ?? []).reduce((s, x) => s + (x.valor_centavos as number), 0);
  const [{ data: pacotesVenda }, { data: saldos }, { data: cashback }] = await Promise.all([
    supabase.from("pacotes").select("id, nome, preco_centavos").eq("ativo", true).order("nome"),
    c.cliente_id && c.status === "aberta"
      ? supabase.from("pacote_saldos").select("servico_id, total, usado, pacotes_cliente!inner(cliente_id, estado, expira_em)").eq("pacotes_cliente.cliente_id", c.cliente_id).eq("pacotes_cliente.estado", "ativo").gt("pacotes_cliente.expira_em", new Date().toISOString())
      : Promise.resolve({ data: [] }),
    c.cliente_id && c.status === "aberta" ? supabase.rpc("saldo_cashback", { p_cliente: c.cliente_id }) : Promise.resolve({ data: 0 }),
  ]);
  const itensDoPacote = new Set((its ?? []).filter((i) => i.tipo === "servico").map((i) => i.servico_id as string));
  const sessoes = (saldos ?? []).filter((x) => x.usado < x.total && itensDoPacote.has(x.servico_id)).reduce((s, x) => s + x.total - x.usado, 0);
  const saldoCashback = Number(cashback ?? 0);
  const nome = new Map((profs ?? []).map((p) => [p.user_id, p.nome as string]));
  const equipe = (profs ?? []).filter((p) => p.papel !== "recepcao");
  const subtotal = itens.reduce((s, i) => s + i.preco_centavos * i.quantidade - i.desconto_centavos, 0);
  const total = subtotal - c.desconto_centavos;
  const pago = pags.reduce((s, p) => s + p.valor_centavos, 0);
  const restante = total - pago;
  const aberta = c.status === "aberta";
  const podeCaixa = pode(membro, "caixa"); // receber pagamento e fechar: recepção, admin ou quem tiver a permissão
  const opcoesProf = (padrao = "") => (
    <>
      <option value="" disabled={!padrao}>{padrao ? "Ninguém" : "Escolha"}</option>
      {equipe.map((p) => <option key={p.user_id} value={p.user_id}>{p.nome}</option>)}
    </>
  );
  const { data: nota } = c.status === "fechada" && membro.papel !== "profissional"
    ? await supabase.from("notas_fiscais").select("status, numero, url_pdf, url_xml, mensagem, ambiente, valor_centavos, criado_em").eq("comanda_id", id).order("criado_em", { ascending: false }).limit(1).maybeSingle()
    : { data: null };
  const temServico = itens.some((i) => i.tipo === "servico");
  const { data: valesDaComanda } = c.status === "fechada" && itens.some((i) => i.tipo === "vale_presente")
    ? await supabase.from("vales_presente").select("id, codigo, para, valor_centavos").eq("comanda_id", id)
    : { data: [] };
  // Extras de comanda aberta: taxa de falta pendente, sugestões do catálogo, Pix pelo celular e fidelidade.
  const servicosDaComanda = itens.filter((i) => i.tipo === "servico" && i.servico_id);
  const [{ data: taxasPend }, { data: sugs }, { data: cobr }, { data: fid }, { data: clienteTel }] = aberta ? await Promise.all([
    c.cliente_id ? supabase.rpc("taxas_pendentes", { p_cliente: c.cliente_id }) : Promise.resolve({ data: [] }),
    servicosDaComanda.length ? supabase.from("servicos").select("complementos, produtos_sugeridos").in("id", servicosDaComanda.map((i) => i.servico_id as string)) : Promise.resolve({ data: [] }),
    membro.papel !== "profissional" ? supabase.from("cobrancas").select("id, valor_centavos, status, modo, criado_em").eq("comanda_id", id).eq("status", "pendente").order("criado_em", { ascending: false }).limit(1).maybeSingle() : Promise.resolve({ data: null }),
    c.cliente_id ? supabase.rpc("fidelidade", { p_cliente: c.cliente_id }) : Promise.resolve({ data: null }),
    c.cliente_id ? supabase.from("clientes").select("telefone").eq("id", c.cliente_id).maybeSingle() : Promise.resolve({ data: null }),
  ]) : [{ data: [] }, { data: [] }, { data: null }, { data: null }, { data: null }];
  const taxasP = (taxasPend ?? []) as { id: string; valor_centavos: number; falta_em: string }[];
  const jaNaComanda = new Set(itens.map((i) => (i.servico_id ?? i.produto_id) as string | null));
  const sugServicos = [...new Set(((sugs ?? []) as { complementos: string[] }[]).flatMap((x) => x.complementos ?? []))].filter((x) => !jaNaComanda.has(x)).map((x) => (srvs ?? []).find((s) => s.id === x)).filter((x): x is NonNullable<typeof x> => !!x).slice(0, 4);
  const sugProdutos = [...new Set(((sugs ?? []) as { produtos_sugeridos: string[] }[]).flatMap((x) => x.produtos_sugeridos ?? []))].filter((x) => !jaNaComanda.has(x)).map((x) => (prods ?? []).find((s) => s.id === x)).filter((x): x is NonNullable<typeof x> => !!x).slice(0, 4);
  const profPrincipal = (servicosDaComanda[0]?.profissional_id as string | undefined) ?? "";
  const cobranca = cobr as { id: string; valor_centavos: number; modo: string; criado_em: string } | null;
  const fidelidade = fid as { pontos: number; nivel: string | null; bonus: number } | null;
  const ROT: Record<string, string> = { servico: "Serviço", produto: "Produto", gorjeta: "Gorjeta", pacote: "Pacote", vale_presente: "Vale-presente", taxa: "Taxa por falta" };
  return (
    <div className="stack-lg">
      <div className="row between">
        <div><p className="cap sec"><Link href="/caixa">Caixa</Link> / Comanda #{c.numero}</p><h1>{(c.clientes as unknown as { nome: string } | null)?.nome ?? "Cliente avulso"}</h1></div>
        <span className={`bd ${aberta ? "wt" : c.status === "fechada" ? "ok" : "no"}`}>{aberta ? "Aberta" : c.status === "fechada" ? "Fechada" : "Cancelada"}</span>
      </div>

      <section className="card stack">
        <h2>Itens</h2>
        {itens.length === 0 ? <p className="sm sec">Nenhum item ainda.</p> : (
          <div className="list">
            {itens.map((i) => (
              <div key={i.id} className="item">
                <span>
                  <span className="t">{i.quantidade > 1 ? `${i.quantidade}× ` : ""}{i.descricao}</span>{" "}
                  <span className="sm sec">· {ROT[i.tipo]}{i.profissional_id ? ` · ${nome.get(i.profissional_id) ?? ""}` : ""}{i.assistente_id ? ` + ${nome.get(i.assistente_id) ?? ""}` : ""}{i.desconto_centavos ? ` · desconto ${reais(i.desconto_centavos)}` : ""}</span>
                </span>
                <div className="row">
                  <strong>{reais(i.preco_centavos * i.quantidade - i.desconto_centavos)}</strong>
                  {aberta && <form action={removerItem}><input type="hidden" name="id" value={i.id} /><input type="hidden" name="comanda_id" value={id} /><button className="btn ghost sm" type="submit" aria-label={`Remover ${i.descricao}`}>Remover</button></form>}
                </div>
              </div>
            ))}
          </div>
        )}
        {aberta && (
          <div className="stack">
            <details className="aj" open={itens.length === 0}><summary>Adicionar serviço</summary>
              <div className="aj-corpo">
                <AcaoForm action={adicionarItem}>
                  <input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="tipo" value="servico" />
                  <div className="grid2">
                    <div className="field"><label htmlFor="is">Serviço</label><select id="is" name="servico_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{(srvs ?? []).map((s) => <option key={s.id} value={s.id}>{s.nome} · {s.preco_centavos ? reais(s.preco_centavos) : "sem preço"}</option>)}</select></div>
                    <QuemFez equipe={equipe.map((p) => ({ id: p.user_id, nome: p.nome }))} padrao={membro.papel === "profissional" ? membro.user_id : ""} />
                    <div className="field"><label htmlFor="ipr">Preço (vazio = do catálogo)</label><input id="ipr" name="preco" inputMode="decimal" /></div>
                    <div className="field"><label htmlFor="id">Desconto (R$)</label><input id="id" name="desconto" inputMode="decimal" /></div>
                  </div>
                  <div><Enviar>Adicionar serviço</Enviar></div>
                </AcaoForm>
              </div>
            </details>
            <details className="aj"><summary>Vender produto</summary>
              <div className="aj-corpo">
                {(prods ?? []).length === 0 ? <p className="sm">Cadastre os produtos em <Link href="/catalogos">Catálogos</Link>.</p> : (
                  <AcaoForm action={adicionarItem}>
                    <input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="tipo" value="produto" />
                    <div className="grid2">
                      <div className="field"><label htmlFor="pp">Produto</label><select id="pp" name="produto_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{(prods ?? []).map((p) => <option key={p.id} value={p.id}>{p.nome} · {reais(p.preco_centavos)}</option>)}</select></div>
                      <div className="field"><label htmlFor="pq">Quantidade</label><input id="pq" name="quantidade" type="number" min={1} max={999} defaultValue={1} /></div>
                      <div className="field"><label htmlFor="pv">Quem vendeu (comissão de venda)</label><select id="pv" name="profissional_id" defaultValue="">{opcoesProf("x")}</select></div>
                      <div className="field"><label htmlFor="pd">Desconto (R$)</label><input id="pd" name="desconto" inputMode="decimal" /></div>
                    </div>
                    <div><Enviar>Adicionar produto</Enviar></div>
                  </AcaoForm>
                )}
              </div>
            </details>
            {(pacotesVenda ?? []).length > 0 && (
              <details className="aj"><summary>Vender pacote ou clube</summary>
                <div className="aj-corpo">
                  <AcaoForm action={adicionarItem} className="row">
                    <input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="tipo" value="pacote" />
                    <div className="field" style={{ flex: 1, minWidth: 200 }}><label htmlFor="pkv">Pacote</label><select id="pkv" name="pacote_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{(pacotesVenda ?? []).map((p) => <option key={p.id} value={p.id}>{p.nome} · {reais(p.preco_centavos)}</option>)}</select></div>
                    <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Adicionar</Enviar></div>
                  </AcaoForm>
                  <p className="cap muted">O saldo de sessões nasce quando a comanda fecha. Precisa de cliente na comanda.</p>
                </div>
              </details>
            )}
            <details className="aj"><summary>Vender vale-presente</summary>
              <div className="aj-corpo">
                <AcaoForm action={adicionarItem}>
                  <input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="tipo" value="vale_presente" />
                  <div className="grid2">
                    <div className="field"><label htmlFor="vpv">Valor (R$)</label><input id="vpv" name="preco" inputMode="decimal" required /></div>
                    <div className="field"><label htmlFor="vpp">Para quem</label><input id="vpp" name="para" required maxLength={80} placeholder="Ex.: Maria, minha mãe" /></div>
                  </div>
                  <div className="field"><label htmlFor="vpm">Mensagem (vai impressa no vale)</label><input id="vpm" name="mensagem" maxLength={200} /></div>
                  <div><Enviar className="btn sec">Adicionar</Enviar></div>
                </AcaoForm>
                <p className="cap muted">O código nasce quando a comanda fecha. O vale para imprimir fica em Caixa &gt; Vales-presente. Vale 1 ano.</p>
              </div>
            </details>
            <details className="aj"><summary>Gorjeta</summary>
              <div className="aj-corpo">
                <AcaoForm action={adicionarItem} className="row">
                  <input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="tipo" value="gorjeta" />
                  <div className="field"><label htmlFor="gp">Para</label><select id="gp" name="profissional_id" required defaultValue="">{opcoesProf()}</select></div>
                  <div className="field" style={{ width: 130 }}><label htmlFor="gv">Valor (R$)</label><input id="gv" name="preco" inputMode="decimal" required /></div>
                  <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Adicionar</Enviar></div>
                </AcaoForm>
                <p className="cap muted">A gorjeta vai inteira para o profissional: não é receita do salão nem entra na comissão.</p>
              </div>
            </details>
          </div>
        )}
      </section>

      <section className="card stack">
        <div className="totais">
          <div><span className="sec">Subtotal</span><span>{reais(subtotal)}</span></div>
          {c.desconto_centavos > 0 && <div><span className="sec">Desconto na comanda</span><span>− {reais(c.desconto_centavos)}</span></div>}
          <div className="tot"><span>Total</span><span>{reais(total)}</span></div>
          <div><span className="sec">Pago</span><span>{reais(pago)}</span></div>
          {total < 0
            ? <div className="falta"><span>O desconto passou do valor da comanda</span><span>diminua o desconto</span></div>
            : <div className={restante === 0 ? "okt" : "falta"}><span>{restante === 0 ? "Tudo pago" : restante > 0 ? "Falta pagar" : "Pago a mais"}</span><span>{restante === 0 ? "✓" : reais(Math.abs(restante))}</span></div>}
        </div>
        {aberta && (
          <AcaoForm action={salvarComanda} className="row">
            <input type="hidden" name="comanda_id" value={id} />
            <div className="field" style={{ minWidth: 200, flex: 1 }}><label htmlFor="cc">Cliente</label><BuscaCliente id="cc" name="cliente_id" avulso inicial={c.cliente_id ? { id: c.cliente_id, nome: nomeCliente ?? "Cliente", telefone: null } : null} /></div>
            <div className="field" style={{ width: 150 }}><label htmlFor="cd">Desconto geral (R$)</label><input id="cd" name="desconto" inputMode="decimal" defaultValue={c.desconto_centavos ? campoReais(c.desconto_centavos) : ""} /></div>
            <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Salvar</Enviar></div>
          </AcaoForm>
        )}
      </section>

      <section className="card stack">
        <h2>Pagamento</h2>
        {pags.length > 0 && (
          <div className="list">
            {pags.map((p) => (
              <div key={p.id} className="item">
                <span className="t">{FORMAS[p.forma]}{p.parcelas > 1 ? ` em ${p.parcelas}x` : ""}</span>
                <div className="row"><strong>{reais(p.valor_centavos)}</strong>
                  {aberta && podeCaixa && <form action={removerPagamento}><input type="hidden" name="id" value={p.id} /><input type="hidden" name="comanda_id" value={id} /><button className="btn ghost sm" type="submit" aria-label={`Remover pagamento em ${FORMAS[p.forma]}`}>Remover</button></form>}
                </div>
              </div>
            ))}
          </div>
        )}
        {aberta && taxasP.map((t) => (
          <div key={t.id} className="rebook">
            <span>Taxa de falta pendente: <strong>{reais(t.valor_centavos)}</strong> (faltou em {dataCurta(t.falta_em, salao.fuso)}).</span>
            <div className="row" style={{ gap: 6 }}>
              <form action={cobrarTaxa}><input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="taxa_id" value={t.id} /><input type="hidden" name="quando" value={dataCurta(t.falta_em, salao.fuso)} /><button className="btn sm" type="submit">Cobrar nesta comanda</button></form>
              {membro.papel !== "profissional" && <form action={perdoarTaxa}><input type="hidden" name="id" value={t.id} /><input type="hidden" name="cliente_id" value={c.cliente_id ?? ""} /><input type="hidden" name="comanda_id" value={id} /><button className="btn ghost sm" type="submit">Perdoar</button></form>}
            </div>
          </div>
        ))}
        {aberta && (sugServicos.length > 0 || sugProdutos.length > 0) && (
          <div className="pub-sugestao">
            <strong>Ofereça junto</strong>
            <div className="row" style={{ gap: 6 }}>
              {sugServicos.map((s) => profPrincipal && <form key={s.id} action={adicionarSugestao}><input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="tipo" value="servico" /><input type="hidden" name="id" value={s.id} /><input type="hidden" name="profissional_id" value={profPrincipal} /><button className="btn sec sm" type="submit">+ {s.nome}</button></form>)}
              {sugProdutos.map((p) => <form key={p.id} action={adicionarSugestao}><input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="tipo" value="produto" /><input type="hidden" name="id" value={p.id} /><input type="hidden" name="profissional_id" value={profPrincipal} /><button className="btn sec sm" type="submit">+ {p.nome} · {reais(p.preco_centavos)}</button></form>)}
            </div>
          </div>
        )}
        {aberta && fidelidade?.nivel && <p className="cap" style={{ margin: 0 }}><span className="bd br">Cliente {fidelidade.nivel}</span> {fidelidade.bonus > 0 ? `ganha ${fidelidade.bonus}% de cashback extra ao fechar` : ""}</p>}
        {aberta && podeCaixa && sessoes > 0 && (
          <form action={usarPacote} className="rebook"><input type="hidden" name="comanda_id" value={id} />
            <span>A cliente tem <strong>{sessoes} {sessoes === 1 ? "sessão" : "sessões"}</strong> de pacote para os serviços desta comanda.</span><button className="btn sm" type="submit">Usar o pacote</button></form>
        )}
        {aberta && podeCaixa && saldoCashback > 0 && restante > 0 && (
          <form action={usarCashback} className="rebook"><input type="hidden" name="comanda_id" value={id} />
            <span>A cliente tem <strong>{reais(saldoCashback)}</strong> de cashback.</span><button className="btn sm" type="submit">Usar o cashback</button></form>
        )}
        {aberta && podeCaixa && restante > 0 && (
          <details className="aj"><summary>Pagar com vale-presente</summary><div className="aj-corpo">
            <AcaoForm action={usarValePresente} className="row"><input type="hidden" name="comanda_id" value={id} />
              <div className="field"><label htmlFor="vpc">Código do vale</label><input id="vpc" name="codigo" required maxLength={10} autoCapitalize="characters" style={{ textTransform: "uppercase", letterSpacing: ".1em" }} /></div>
              <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Usar</Enviar></div>
            </AcaoForm></div></details>
        )}
        {aberta && podeCaixa && credito > 0 && (
          <form action={usarCredito} className="rebook"><input type="hidden" name="comanda_id" value={id} />
            <span>A cliente tem <strong>{reais(credito)}</strong> de sinal pago para usar.</span><button className="btn sm" type="submit">Usar o sinal</button></form>
        )}
        {aberta && podeCaixa && restante > 0 && (
          <AcaoForm action={adicionarPagamento} className="row">
            <input type="hidden" name="comanda_id" value={id} /><input type="hidden" name="restante" value={restante} />
            <div className="field"><label htmlFor="pf">Forma</label><select id="pf" name="forma" defaultValue="pix">{FORMAS_DIGITADAS.map((k) => <option key={k} value={k}>{FORMAS[k]}</option>)}</select></div>
            <div className="field" style={{ width: 140 }}><label htmlFor="pvv">Valor (R$)</label><input id="pvv" name="valor" inputMode="decimal" defaultValue={campoReais(restante)} required /></div>
            <div className="field" style={{ width: 100 }}><label htmlFor="ppa">Parcelas</label><input id="ppa" name="parcelas" type="number" min={1} max={24} defaultValue={1} /></div>
            <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Registrar</Enviar></div>
          </AcaoForm>
        )}
        {aberta && podeCaixa && restante > 0 && <p className="cap muted">Em dinheiro, digite o valor recebido: o troco aparece na hora.</p>}
        {aberta && podeCaixa && restante > 0 && (
          <details className="aj" open={!!cobranca}><summary>Cliente paga pelo celular (Pix)</summary><div className="aj-corpo stack">
            {cobranca && (
              <div className="rebook">
                <span>Link de {reais(cobranca.valor_centavos)} enviado, {cobranca.modo === "mercadopago" ? "confirma sozinho quando ela pagar." : "aguardando o Pix."}</span>
                <div className="row" style={{ gap: 6 }}>
                  {cobranca.modo !== "mercadopago" && <form action={confirmarCobranca}><input type="hidden" name="id" value={cobranca.id} /><input type="hidden" name="comanda_id" value={id} /><button className="btn sm" type="submit">O Pix caiu: confirmar</button></form>}
                  <form action={cancelarCobranca}><input type="hidden" name="id" value={cobranca.id} /><input type="hidden" name="comanda_id" value={id} /><button className="btn ghost sm" type="submit">Cancelar link</button></form>
                </div>
              </div>
            )}
            <GerarLink acao={cobrarPeloCelular} campos={{ comanda_id: id }} rotulo={cobranca ? "Gerar novo link" : `Gerar link de ${reais(restante)}`} telefone={(clienteTel as { telefone: string | null } | null)?.telefone} />
            <p className="cap muted" style={{ margin: 0 }}>A cliente abre o link, vê os itens e paga pelo Pix. Com Mercado Pago, entra sozinho; com Pix na chave, confira no banco e confirme aqui.</p>
          </div></details>
        )}
        {aberta && (
          <div className="row between">
            <form action={cancelarComanda}><input type="hidden" name="comanda_id" value={id} /><button className="btn ghost" type="submit">Cancelar comanda</button></form>
            {!podeCaixa ? <p className="sm sec">O pagamento e o fechamento ficam com a recepção.</p> : caixa ? (
              <AcaoForm action={fecharComanda} className="row"><input type="hidden" name="comanda_id" value={id} /><Enviar>Fechar comanda</Enviar></AcaoForm>
            ) : membro.papel === "profissional" ? <p className="sm sec">O caixa do dia está fechado. Peça para a recepção abrir.</p> : (
              <AcaoForm action={abrirCaixaEFechar} className="row fechar-caixa">
                <input type="hidden" name="comanda_id" value={id} />
                <div className="field" style={{ width: 160 }}><label htmlFor="tr">Troco na gaveta (R$)</label><input id="tr" name="troco" inputMode="decimal" placeholder="0,00" /></div>
                <div style={{ alignSelf: "flex-end" }}><Enviar>Abrir caixa e fechar comanda</Enviar></div>
                <p className="cap muted" style={{ flexBasis: "100%" }}>O caixa do dia ainda não foi aberto. Informe o dinheiro que já tem na gaveta (pode ser 0).</p>
              </AcaoForm>
            )}
          </div>
        )}
        {c.status === "fechada" && c.cliente_id && (
          <div className="rebook">
            <div><strong>Já marcar a próxima visita?</strong><p className="sm sec">Quem sai do salão com o retorno marcado volta muito mais. Sugestão: daqui a 4 semanas.</p></div>
            <Link className="btn" href={`/agenda?data=${somarDias(dataLocal(new Date(), salao.fuso), 28)}&cliente=${c.cliente_id}#novo`}>Agendar retorno</Link>
          </div>
        )}
        {(valesDaComanda ?? []).map((v) => (
          <div key={v.id} className="rebook">
            <span>Vale-presente para <strong>{v.para}</strong> · {reais(v.valor_centavos)} · código <strong>{v.codigo}</strong></span>
            <Link className="btn sm" href={`/caixa/vale/${v.id}`}>Imprimir ou enviar</Link>
          </div>
        ))}
        {c.status === "fechada" && membro.papel !== "profissional" && temServico && (
          <div className="nota-fiscal stack">
            <div className="row between"><strong>Nota fiscal de serviço</strong>
              {nota && <span className={`bd ${nota.status === "autorizada" ? "ok" : nota.status === "processando" ? "wt" : nota.status === "cancelada" ? "mu" : "no"}`}>{({ autorizada: "autorizada", processando: "na prefeitura", erro: "recusada", cancelada: "cancelada" } as Record<string, string>)[nota.status]}{nota.ambiente !== "producao" ? ` · ${nota.ambiente === "simulacao" ? "simulação" : "teste"}` : ""}</span>}</div>
            {nota?.status === "autorizada" && (
              <div className="row" style={{ gap: 8 }}>
                <span className="sm">Nº {nota.numero ?? "—"} · {reais(nota.valor_centavos)}</span>
                {nota.url_pdf && <a className="btn sm" href={nota.url_pdf} target="_blank" rel="noopener">Ver nota (PDF)</a>}
                {nota.url_xml && <a className="btn ghost sm" href={nota.url_xml} target="_blank" rel="noopener">XML</a>}
              </div>
            )}
            {nota?.status === "processando" && <form action={atualizarNota}><input type="hidden" name="comanda_id" value={id} /><button className="btn ghost sm" type="submit">Atualizar situação</button></form>}
            {nota?.status === "erro" && <p className="err">{nota.mensagem ?? "A prefeitura recusou a nota."}</p>}
            {(!nota || nota.status === "erro" || nota.status === "cancelada") && (
              <AcaoForm action={emitirNota} className="row nota-form">
                <input type="hidden" name="comanda_id" value={id} />
                <input name="documento" inputMode="numeric" maxLength={18} placeholder="CPF ou CNPJ (opcional)" aria-label="CPF ou CNPJ de quem recebe a nota" />
                <input name="nome" maxLength={120} placeholder={nomeCliente ?? "Nome (opcional)"} aria-label="Nome de quem recebe a nota" />
                <Enviar className="btn sm">{nota ? "Emitir de novo" : "Emitir nota"}</Enviar>
              </AcaoForm>
            )}
            {nota?.status === "autorizada" && membro.papel === "admin" && (
              <details><summary className="cap" style={{ cursor: "pointer" }}>Cancelar a nota</summary>
                <AcaoForm action={cancelarNota} className="row nota-form">
                  <input type="hidden" name="comanda_id" value={id} />
                  <input name="justificativa" minLength={15} maxLength={255} required placeholder="Motivo (ex.: valor lançado errado na comanda)" aria-label="Motivo do cancelamento" />
                  <Enviar className="btn ghost sm">Cancelar nota</Enviar>
                </AcaoForm>
              </details>
            )}
          </div>
        )}
        {c.status === "fechada" && membro.papel === "admin" && (
          <AcaoForm action={reabrirComanda} className="row"><input type="hidden" name="comanda_id" value={id} /><Enviar className="btn ghost sm">Reabrir comanda (só enquanto o caixa estiver aberto)</Enviar></AcaoForm>
        )}
      </section>
    </div>
  );
}
