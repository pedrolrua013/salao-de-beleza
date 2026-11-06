import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { descreverFases, temPausa } from "@/lib/fases";
import { reais } from "@/lib/dinheiro";
import type { Servico } from "@/lib/types";
import { alternarPacote, alternarPacoteOnline, alternarProduto, alternarServico, criarPacote, criarServico, editarServico, salvarProduto } from "./actions";
import { CamposServico } from "./campos-servico";
import { ExtrasServico, Recursos, type PrecoProf, type Recurso, type Variacao } from "./extras-servico";
import { CamposProduto, type ProdutoCampos } from "./campos-produto";
import Link from "next/link";

export const metadata = { title: "Catálogos" };

export default async function Catalogos() {
  const { supabase, membro } = await exigirMembro();
  const [{ data: s }, { data: pr }, { data: pcs }, { data: vars }, { data: sps }, { data: recs }, { data: srecs }, { data: profs }] = await Promise.all([
    supabase.from("servicos").select("*").eq("avulso", false).order("nome"),
    supabase.from("produtos").select("*").order("nome"),
    supabase.from("pacotes").select("id, nome, tipo, preco_centavos, validade_dias, ativo, online, pacote_itens(servico_id, quantidade)").order("nome"),
    supabase.from("servico_variacoes").select("id, servico_id, nome, preco_centavos, fases, ordem").order("ordem").order("nome"),
    supabase.from("servico_profissional").select("servico_id, profissional_id, preco_centavos, fases"),
    supabase.from("recursos").select("id, nome, quantidade").order("nome"),
    supabase.from("servico_recursos").select("servico_id, recurso_id"),
    supabase.from("membros").select("user_id, nome").in("papel", ["admin", "profissional"]).eq("ativo", true).order("nome"),
  ]);
  const extras = { variacoes: (vars ?? []) as Variacao[], precos: (sps ?? []) as PrecoProf[], recursos: (recs ?? []) as Recurso[], usos: (srecs ?? []) as { servico_id: string; recurso_id: string }[], profs: (profs ?? []).map((p) => ({ id: p.user_id as string, nome: p.nome as string })) , opcoesServicos: [] as { id: string; nome: string }[], opcoesProdutos: [] as { id: string; nome: string }[] };
  const pacotes = (pcs ?? []) as { id: string; nome: string; tipo: string; preco_centavos: number; validade_dias: number; ativo: boolean; pacote_itens: { servico_id: string; quantidade: number }[] }[];
  const servicos = (s ?? []) as (Servico & { preco_centavos: number; custo_produto_centavos: number; sinal_percentual: number; online: boolean; retorno_dias: number | null; cor: string | null; intervalo_min: number })[];
  const produtos = (pr ?? []) as (ProdutoCampos & { id: string; ativo: boolean; estoque: number })[];
  const admin = membro.papel === "admin";
  return (
    <div className="stack-lg">
      <h1>Catálogos</h1>
      <section className="card stack">
        <h2>Serviços</h2>
        {servicos.some((x) => x.ativo && !x.preco_centavos) && (
          <p className="aviso-preco" role="status">⚠ {servicos.filter((x) => x.ativo && !x.preco_centavos).length === 1 ? "1 serviço está" : `${servicos.filter((x) => x.ativo && !x.preco_centavos).length} serviços estão`} sem preço: {servicos.filter((x) => x.ativo && !x.preco_centavos).map((x) => x.nome).join(", ")}. Toque em Editar e coloque o valor (sem preço ele entra na comanda por R$ 0,00 e não aparece com valor no link).</p>
        )}
        <p className="sm sec" id="srv-ajuda">Em química, informe a <strong>pausa</strong>: o tempo em que o produto age e a cliente espera. Durante a pausa o profissional fica livre, e a agenda aceita outra cliente nesse intervalo.</p>
        <div className="list">
          {servicos.map((x) => (
            <div key={x.id} className="item srv-item">
              <span className="t" style={{ opacity: x.ativo ? 1 : 0.5 }}>{x.cor && <span className="srv-bola" style={{ background: x.cor }} aria-hidden="true" />}{x.nome} <span className="sm sec">· {descreverFases(x.fases)}{x.preco_centavos ? ` · ${reais(x.preco_centavos)}` : ""}</span>{!x.preco_centavos && x.ativo && <span className="bd no srv-bd">sem preço</span>}{temPausa(x.fases) && <span className="bd br srv-bd">com pausa</span>}{x.sinal_percentual > 0 && <span className="bd wt srv-bd">sinal {x.sinal_percentual}%</span>}{!x.online && <span className="bd mu srv-bd">fora do link</span>}{x.retorno_dias && <span className="bd mu srv-bd">volta em {x.retorno_dias} dias</span>}{extras.variacoes.some((v) => v.servico_id === x.id) && <span className="bd br srv-bd">{extras.variacoes.filter((v) => v.servico_id === x.id).length} tamanhos</span>}{x.intervalo_min > 0 && <span className="bd mu srv-bd">+{x.intervalo_min} min de limpeza</span>}</span>
              <div className="row">
                {!x.ativo && <span className="bd mu">Inativo</span>}
                {admin && (
                  <form action={alternarServico}>
                    <input type="hidden" name="id" value={x.id} /><input type="hidden" name="ativo" value={String(x.ativo)} />
                    <button className="btn sec sm" type="submit">{x.ativo ? "Desativar" : "Ativar"}</button>
                  </form>
                )}
              </div>
              {admin && (
                  <details className="srv-editar">
                    <summary className="btn sec sm">Editar serviço</summary>
                    <AcaoForm action={editarServico}>
                      <input type="hidden" name="id" value={x.id} />
                      <CamposServico id={`e-${x.id}`} nome={x.nome} fases={x.fases} preco={x.preco_centavos} custo={x.custo_produto_centavos} sinal={x.sinal_percentual} online={x.online} retorno={x.retorno_dias} cor={x.cor} intervalo={x.intervalo_min} />
                      <div><Enviar>Salvar</Enviar></div>
                    </AcaoForm>
                    <ExtrasServico servicoId={x.id} {...extras} opcoesServicos={servicos.filter((o) => o.ativo).map((o) => ({ id: o.id, nome: o.nome }))}
                      opcoesProdutos={produtos.filter((o) => o.ativo && o.tipo !== "uso").map((o) => ({ id: o.id, nome: o.nome }))}
                      sugeridos={{ servicos: (x as { complementos?: string[] }).complementos ?? [], produtos: (x as { produtos_sugeridos?: string[] }).produtos_sugeridos ?? [] }} />
                  </details>
                )}
            </div>
          ))}
        </div>
        {admin ? (
          <AcaoForm action={criarServico}>
            <h3>Novo serviço</h3>
            <CamposServico id="novo" />
            <div><Enviar>Adicionar</Enviar></div>
          </AcaoForm>
        ) : <p className="sm muted">Só o administrador altera os serviços.</p>}
      </section>
      <Recursos recursos={extras.recursos} admin={admin} />
      <section className="card stack" id="produtos">
        <div className="row between"><h2>Produtos</h2><Link className="btn ghost sm" href="/estoque">Ver estoque</Link></div>
        <p className="sm sec">Revenda aparece na comanda em Vender produto. Uso interno (tinta, oxidante, máscara) sai do estoque sozinho pelo consumo de cada serviço, definido em Estoque.</p>
        {produtos.length === 0 ? <p className="sm muted">Nenhum produto cadastrado.</p> : (
          <div className="list">
            {produtos.map((x) => (
              <div key={x.id} className="item srv-item">
                <span className="t" style={{ opacity: x.ativo ? 1 : 0.5 }}>{x.nome} <span className="sm sec">· {x.tipo === "uso" ? "uso interno" : reais(x.preco_centavos)} · estoque {Number(x.estoque).toLocaleString("pt-BR")} {x.unidade}</span></span>
                <div className="row">
                  {!x.ativo && <span className="bd mu">Inativo</span>}
                  {admin && (
                    <form action={alternarProduto}>
                      <input type="hidden" name="id" value={x.id} /><input type="hidden" name="ativo" value={String(x.ativo)} />
                      <button className="btn sec sm" type="submit">{x.ativo ? "Desativar" : "Ativar"}</button>
                    </form>
                  )}
                </div>
                {admin && (
                  <details className="srv-editar">
                    <summary className="btn sec sm">Editar produto</summary>
                    <AcaoForm action={salvarProduto}>
                      <input type="hidden" name="id" value={x.id} />
                      <CamposProduto id={`p-${x.id}`} p={x} />
                      <div><Enviar>Salvar</Enviar></div>
                    </AcaoForm>
                  </details>
                )}
              </div>
            ))}
          </div>
        )}
        {admin && (
          <AcaoForm action={salvarProduto}>
            <h3>Novo produto</h3>
            <CamposProduto id="novo-p" />
            <div><Enviar>Adicionar</Enviar></div>
          </AcaoForm>
        )}
      </section>
      <section className="card stack" id="pacotes">
        <h2>Pacotes e clube</h2>
        <p className="sm sec">Pacote: a cliente paga antes por várias sessões (ex.: 10 escovas) e usa quando quiser, dentro da validade. Clube: o mesmo, por 30 dias, renovado todo mês. A sessão usada entra na comanda pelo valor proporcional e a comissão sai normalmente.</p>
        {pacotes.length > 0 && (
          <div className="list">
            {pacotes.map((x) => {
              const tabela = x.pacote_itens.reduce((t, i) => t + (servicos.find((sv) => sv.id === i.servico_id)?.preco_centavos ?? 0) * i.quantidade, 0);
              return (
                <div key={x.id} className="item">
                  <span><span className="t" style={{ opacity: x.ativo ? 1 : 0.5 }}>{x.nome}</span> <span className="sm sec">· {x.tipo === "clube" ? "clube" : "pacote"} · {reais(x.preco_centavos)} · {x.pacote_itens.map((i) => `${i.quantidade}× ${servicos.find((sv) => sv.id === i.servico_id)?.nome ?? ""}`).join(", ")} · vale {x.validade_dias} dias{tabela > x.preco_centavos ? ` · economia de ${reais(tabela - x.preco_centavos)}` : ""}</span></span>
                  {admin && <form action={alternarPacote}><input type="hidden" name="id" value={x.id} /><input type="hidden" name="ativo" value={String(x.ativo)} /><button className="btn sec sm" type="submit">{x.ativo ? "Desativar" : "Ativar"}</button></form>}
                  {admin && x.ativo && <form action={alternarPacoteOnline}><input type="hidden" name="id" value={x.id} /><input type="hidden" name="online" value={(x as { online?: boolean }).online ? "0" : "1"} /><button className="btn ghost sm" type="submit">{(x as { online?: boolean }).online ? "Tirar da venda pelo link" : "Vender pelo link"}</button></form>}
                </div>
              );
            })}
          </div>
        )}
        {admin && (
          <AcaoForm action={criarPacote}>
            <h3>Novo pacote ou clube</h3>
            <div className="grid2">
              <div className="field"><label htmlFor="pk-n">Nome</label><input id="pk-n" name="nome" required maxLength={120} placeholder="Ex.: 10 escovas, Clube escova ilimitada" /></div>
              <div className="field"><label htmlFor="pk-t">Tipo</label><select id="pk-t" name="tipo" defaultValue="pacote"><option value="pacote">Pacote</option><option value="clube">Clube (mensal)</option></select></div>
              <div className="field"><label htmlFor="pk-p">Preço (R$)</label><input id="pk-p" name="preco" inputMode="decimal" required /></div>
              <div className="field"><label htmlFor="pk-v">Validade (dias)</label><input id="pk-v" name="validade" type="number" min={7} max={730} placeholder="180 no pacote, 30 no clube" /></div>
            </div>
            {[0, 1, 2, 3].map((i) => (
              <div className="row" key={i}>
                <div className="field" style={{ flex: 1, minWidth: 200 }}><label htmlFor={`pk-s${i}`}>Serviço {i + 1}</label><select id={`pk-s${i}`} name={`servico_${i}`} defaultValue=""><option value="">—</option>{servicos.filter((x) => x.ativo).map((x) => <option key={x.id} value={x.id}>{x.nome}</option>)}</select></div>
                <div className="field" style={{ width: 110 }}><label htmlFor={`pk-q${i}`}>Sessões</label><input id={`pk-q${i}`} name={`qtd_${i}`} type="number" min={1} max={100} /></div>
              </div>
            ))}
            <div><Enviar>Criar</Enviar></div>
          </AcaoForm>
        )}
      </section>
    </div>
  );
}
