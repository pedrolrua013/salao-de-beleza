import { AcaoForm, Enviar } from "@/components/acao-form";
import { descreverFases, type Fase } from "@/lib/fases";
import { reais } from "@/lib/dinheiro";
import { adicionarVariacao, criarRecurso, removerPrecoProfissional, removerRecurso, removerVariacao, salvarComplementos, salvarPrecoProfissional, salvarRecursosServico } from "./actions";

export type Variacao = { id: string; servico_id: string; nome: string; preco_centavos: number; fases: Fase[]; ordem: number };
export type PrecoProf = { servico_id: string; profissional_id: string; preco_centavos: number | null; fases: Fase[] | null };
export type Recurso = { id: string; nome: string; quantidade: number };

function Tempos({ id, obrigatorio }: { id: string; obrigatorio: boolean }) {
  return (
    <>
      <div className="field"><label htmlFor={`${id}-a`}>Trabalho (min)</label><input id={`${id}-a`} name="antes" type="number" min={5} max={480} step={5} required={obrigatorio} placeholder={obrigatorio ? "" : "igual"} /></div>
      <div className="field"><label htmlFor={`${id}-p`}>Pausa (min)</label><input id={`${id}-p`} name="pausa" type="number" min={0} max={480} step={5} placeholder="0" /></div>
      <div className="field"><label htmlFor={`${id}-d`}>Finalização (min)</label><input id={`${id}-d`} name="depois" type="number" min={0} max={480} step={5} placeholder="0" /></div>
    </>
  );
}

/** Tamanhos, preço por profissional e recursos de um serviço (dentro de "Editar serviço"). */
export function ExtrasServico({ servicoId, variacoes, precos, recursos, usos, profs, opcoesServicos, opcoesProdutos, sugeridos }: {
  servicoId: string; variacoes: Variacao[]; precos: PrecoProf[]; recursos: Recurso[]; usos: { servico_id: string; recurso_id: string }[]; profs: { id: string; nome: string }[];
  opcoesServicos: { id: string; nome: string }[]; opcoesProdutos: { id: string; nome: string }[]; sugeridos: { servicos: string[]; produtos: string[] };
}) {
  const meus = variacoes.filter((v) => v.servico_id === servicoId);
  const meusPrecos = precos.filter((p) => p.servico_id === servicoId);
  const nomeProf = new Map(profs.map((p) => [p.id, p.nome]));
  return (
    <div className="srv-extras">
      <details className="aj"><summary>Tamanhos do cabelo {meus.length ? `(${meus.length})` : ""}</summary><div className="aj-corpo stack">
        <p className="cap muted">Ex.: Escova Curto, Médio e Longo, cada um com preço e tempo. Com tamanhos, a cliente escolhe o dela no link e no WhatsApp.</p>
        {meus.map((v) => (
          <div key={v.id} className="item"><span><strong>{v.nome}</strong> <span className="sm sec">· {reais(v.preco_centavos)} · {descreverFases(v.fases)}</span></span>
            <form action={removerVariacao}><input type="hidden" name="id" value={v.id} /><button className="btn ghost sm" type="submit">Remover</button></form></div>
        ))}
        <AcaoForm action={adicionarVariacao}>
          <input type="hidden" name="servico_id" value={servicoId} /><input type="hidden" name="ordem" value={meus.length} />
          <div className="srv-campos">
            <div className="field"><label htmlFor={`v-${servicoId}-n`}>Tamanho</label><input id={`v-${servicoId}-n`} name="nome" required maxLength={40} placeholder="Ex.: Longo" /></div>
            <div className="field"><label htmlFor={`v-${servicoId}-pr`}>Preço (R$)</label><input id={`v-${servicoId}-pr`} name="preco" inputMode="decimal" placeholder="0,00" /></div>
            <Tempos id={`v-${servicoId}`} obrigatorio />
          </div>
          <div><Enviar className="btn sec sm">Adicionar tamanho</Enviar></div>
        </AcaoForm>
      </div></details>

      <details className="aj"><summary>Preço e tempo por profissional {meusPrecos.length ? `(${meusPrecos.length})` : ""}</summary><div className="aj-corpo stack">
        <p className="cap muted">Ex.: com a sênior o corte custa mais. Deixe o tempo vazio para usar o do serviço. Em serviços com tamanhos, vale o preço do tamanho.</p>
        {meusPrecos.map((p) => (
          <div key={p.profissional_id} className="item"><span><strong>{nomeProf.get(p.profissional_id) ?? "Profissional"}</strong> <span className="sm sec">· {p.preco_centavos !== null ? reais(p.preco_centavos) : "preço do serviço"}{p.fases ? ` · ${descreverFases(p.fases)}` : ""}</span></span>
            <form action={removerPrecoProfissional}><input type="hidden" name="servico_id" value={servicoId} /><input type="hidden" name="profissional_id" value={p.profissional_id} /><button className="btn ghost sm" type="submit">Remover</button></form></div>
        ))}
        <AcaoForm action={salvarPrecoProfissional}>
          <input type="hidden" name="servico_id" value={servicoId} />
          <div className="srv-campos">
            <div className="field"><label htmlFor={`pp-${servicoId}-p`}>Profissional</label><select id={`pp-${servicoId}-p`} name="profissional_id" required defaultValue=""><option value="" disabled>Escolha</option>{profs.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}</select></div>
            <div className="field"><label htmlFor={`pp-${servicoId}-pr`}>Preço (R$)</label><input id={`pp-${servicoId}-pr`} name="preco" inputMode="decimal" placeholder="igual" /></div>
            <Tempos id={`pp-${servicoId}`} obrigatorio={false} />
          </div>
          <div><Enviar className="btn sec sm">Salvar preço do profissional</Enviar></div>
        </AcaoForm>
      </div></details>

      <details className="aj"><summary>Sugerir junto {sugeridos.servicos.length + sugeridos.produtos.length ? `(${sugeridos.servicos.length + sugeridos.produtos.length})` : ""}</summary><div className="aj-corpo">
        <AcaoForm action={salvarComplementos}>
          <input type="hidden" name="servico_id" value={servicoId} />
          <p className="cap muted" style={{ margin: 0 }}>Até 5 de cada. Aparecem no link de agendamento (“Quer adicionar?”) e na comanda, para a recepção oferecer.</p>
          <span className="cap" style={{ fontWeight: 500 }}>Serviços</span>
          <div className="row">{opcoesServicos.filter((o) => o.id !== servicoId).map((o) => (
            <label key={o.id} className="chip"><input type="checkbox" name="complemento" value={o.id} defaultChecked={sugeridos.servicos.includes(o.id)} /> {o.nome}</label>
          ))}</div>
          {opcoesProdutos.length > 0 && <><span className="cap" style={{ fontWeight: 500 }}>Produtos para levar para casa</span>
            <div className="row">{opcoesProdutos.map((o) => (
              <label key={o.id} className="chip"><input type="checkbox" name="produto" value={o.id} defaultChecked={sugeridos.produtos.includes(o.id)} /> {o.nome}</label>
            ))}</div></>}
          <div><Enviar className="btn sec sm">Salvar sugestões</Enviar></div>
        </AcaoForm>
      </div></details>

      {recursos.length > 0 && (
        <details className="aj"><summary>Recursos que usa</summary><div className="aj-corpo">
          <AcaoForm action={salvarRecursosServico}>
            <input type="hidden" name="servico_id" value={servicoId} />
            <div className="row">{recursos.map((r) => (
              <label key={r.id} className="chip"><input type="checkbox" name="recurso" value={r.id} defaultChecked={usos.some((u) => u.servico_id === servicoId && u.recurso_id === r.id)} /> {r.nome}</label>
            ))}</div>
            <div><Enviar className="btn sec sm">Salvar recursos</Enviar></div>
          </AcaoForm>
        </div></details>
      )}
    </div>
  );
}

/** Lavatórios, salas e cadeiras: a agenda não marca mais clientes ao mesmo tempo do que o salão tem. */
export function Recursos({ recursos, admin }: { recursos: Recurso[]; admin: boolean }) {
  return (
    <section className="card stack" id="recursos">
      <h2>Recursos do salão</h2>
      <p className="sm sec">Cadastre o que é limitado, como lavatórios, sala de estética ou cadeira de pedicure, e marque em cada serviço o que ele usa (em Editar serviço). A agenda não deixa marcar mais clientes ao mesmo tempo do que o salão tem.</p>
      {recursos.length > 0 && (
        <div className="list">{recursos.map((r) => (
          <div key={r.id} className="item"><span className="t">{r.nome} <span className="sm sec">· {r.quantidade} {r.quantidade === 1 ? "unidade" : "unidades"}</span></span>
            {admin && <form action={removerRecurso}><input type="hidden" name="id" value={r.id} /><button className="btn ghost sm" type="submit">Remover</button></form>}</div>
        ))}</div>
      )}
      {admin && (
        <AcaoForm action={criarRecurso} className="row">
          <div className="field"><label htmlFor="rc-n">Recurso</label><input id="rc-n" name="nome" required maxLength={60} placeholder="Ex.: Lavatório" /></div>
          <div className="field" style={{ width: 110 }}><label htmlFor="rc-q">Quantos tem</label><input id="rc-q" name="quantidade" type="number" min={1} max={50} defaultValue={1} /></div>
          <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Cadastrar</Enviar></div>
        </AcaoForm>
      )}
    </section>
  );
}
