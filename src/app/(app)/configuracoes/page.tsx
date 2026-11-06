import Link from "next/link";
import { campoReais } from "@/lib/dinheiro";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { CampoTelefone } from "@/components/campo-telefone";
import { salvarCrescer, salvarOnline, salvarRetorno, salvarSalao } from "./actions";
import { Copiar } from "@/app/s/[slug]/h/[token]/copiar";

export const metadata = { title: "Salão" };

const DIAS = [[1, "Seg"], [2, "Ter"], [3, "Qua"], [4, "Qui"], [5, "Sex"], [6, "Sáb"], [7, "Dom"]] as const;

export default async function Configuracoes() {
  const { membro, salao: c, supabase } = await exigirMembro();
  const site = process.env.NEXT_PUBLIC_SITE_URL ?? "";
  const link = `${site}/s/${c.slug}`;
  const r = c as typeof c & { retorno_ativo: boolean; retorno_hora: string; espera_ativa: boolean; cashback_percentual: number; cashback_validade_dias: number; avaliacao_ativa: boolean; google_avaliacao_url: string | null; aniversario_ativo: boolean; aniversario_credito_centavos: number; aniversario_validade_dias: number };
  const o = c as typeof c & { agendamento_online: boolean; politica_cancelamento: string | null; cancelamento_horas: number; pix_chave: string | null; pix_nome: string | null; pix_cidade: string | null; antecedencia_min_horas: number; antecedencia_max_dias: number; sinal_padrao_percentual: number };
  const { count: comSinal } = await supabase.from("servicos").select("id", { count: "exact", head: true }).gt("sinal_percentual", 0);
  const admin = membro.papel === "admin";
  return (
    <div className="stack-lg">
      <div className="row between">
        <h1>Salão</h1>
        <div className="row">
          {admin && <Link className="btn sec" href="/equipe">Equipe</Link>}
          {admin && <Link className="btn sec" href="/whatsapp">WhatsApp</Link>}
          {admin && <Link className="btn sec" href="/configuracoes/termos">Termos</Link>}
          {admin && <Link className="btn sec" href="/configuracoes/nota-fiscal">Nota fiscal</Link>}
          {admin && <Link className="btn sec" href="/dados">Importar e exportar</Link>}
        </div>
      </div>
      {!admin && <p className="sec">Só o administrador altera estes dados.</p>}
      <section className="card">
        <AcaoForm action={salvarSalao}>
          <fieldset disabled={!admin} style={{ border: 0, padding: 0, margin: 0, display: "grid", gap: 16, minWidth: 0 }}>
            <div className="grid2">
              <div className="field"><label htmlFor="nome">Nome do salão</label><input id="nome" name="nome" defaultValue={c.nome} required minLength={2} maxLength={120} /></div>
              <div className="field"><label htmlFor="telefone">Telefone</label><CampoTelefone id="telefone" name="telefone" defaultValue={c.telefone} /></div>
              <div className="field"><label htmlFor="endereco">Endereço</label><input id="endereco" name="endereco" defaultValue={c.endereco ?? ""} maxLength={200} /></div>
            </div>
            <div className="field"><label htmlFor="mensagem">Mensagem de boas-vindas no WhatsApp (até 280 caracteres)</label><textarea id="mensagem" name="mensagem" maxLength={280} defaultValue={c.mensagem ?? ""} style={{ minHeight: 70 }} /></div>
            <div className="grid2">
              <div className="field"><label htmlFor="abre">Abre às</label><input id="abre" name="abre" type="time" defaultValue={c.abre.slice(0, 5)} required /></div>
              <div className="field"><label htmlFor="fecha">Fecha às</label><input id="fecha" name="fecha" type="time" defaultValue={c.fecha.slice(0, 5)} required /></div>
            </div>
            <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Dias de atendimento</span>
              <div className="row">{DIAS.map(([n, t]) => (
                <label key={n} className="chip" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
                  <input type="checkbox" name="dias" value={n} defaultChecked={c.dias_semana.includes(n)} />{t}
                </label>))}</div></div>
            <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Lembretes de horário pelo WhatsApp</span>
              <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}>
                <input type="checkbox" name="lembretes_ativos" defaultChecked={c.lembretes_ativos} />Enviar lembrete de confirmação aos clientes
              </label>
              <p className="cap muted" style={{ margin: 0 }}>Saem na véspera do horário e, para quem não responder, 3 horas antes. Só para clientes com telefone e aceite.</p></div>
            <div className="grid2">
              <div className="field"><label htmlFor="lembrete_hora">Horário do lembrete da véspera</label><input id="lembrete_hora" name="lembrete_hora" type="time" defaultValue={c.lembrete_hora.slice(0, 5)} required /></div>
            </div>
            {admin && <div><Enviar>Salvar</Enviar></div>}
          </fieldset>
        </AcaoForm>
      </section>

      <section className="card stack" id="retorno">
        <h2>Trazer a cliente de volta</h2>
        <AcaoForm action={salvarRetorno}>
          <fieldset disabled={!admin} style={{ border: 0, padding: 0, margin: 0, display: "grid", gap: 12, minWidth: 0 }}>
            <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="retorno_ativo" defaultChecked={r.retorno_ativo} />Convite automático de retorno pelo WhatsApp</label>
            <p className="cap muted" style={{ margin: 0 }}>Quando passa o tempo de voltar do serviço (definido em Catálogos, ex.: corte a cada 30 dias) e a cliente não marcou nada, ela recebe um convite com o link. No máximo um por mês. É mensagem de marketing: a Meta cobra cerca de R$ 0,32 cada.</p>
            <div className="field" style={{ maxWidth: 220 }}><label htmlFor="rh">Horário do convite</label><input id="rh" name="retorno_hora" type="time" defaultValue={r.retorno_hora.slice(0, 5)} /></div>
            <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="espera_ativa" defaultChecked={r.espera_ativa} />Avisar a lista de espera quando um horário vagar</label>
            <div className="grid2">
              <div className="field"><label htmlFor="cbp">Cashback (% do que a cliente paga, 0 = desligado)</label><input id="cbp" name="cashback" inputMode="decimal" defaultValue={r.cashback_percentual} /></div>
              <div className="field"><label htmlFor="cbv">Validade do cashback (dias)</label><input id="cbv" name="cashback_validade" type="number" min={7} max={365} defaultValue={r.cashback_validade_dias} /></div>
            </div>
            <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="avaliacao_ativa" defaultChecked={r.avaliacao_ativa} />Pedir avaliação de 0 a 10 no dia seguinte ao atendimento</label>
            <div className="field"><label htmlFor="gg">Link para avaliar o salão no Google (quem der 9 ou 10 é convidada)</label><input id="gg" name="google" defaultValue={r.google_avaliacao_url ?? ""} placeholder="https://g.page/r/.../review" /></div>
            <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="aniversario_ativo" defaultChecked={r.aniversario_ativo} />Parabéns no aniversário da cliente, com presente</label>
            <div className="grid2">
              <div className="field"><label htmlFor="anv">Presente em crédito (R$, 0 = só os parabéns)</label><input id="anv" name="aniversario_credito" inputMode="decimal" defaultValue={campoReais(r.aniversario_credito_centavos)} /></div>
              <div className="field"><label htmlFor="anvd">Prazo para usar o presente (dias)</label><input id="anvd" name="aniversario_validade" type="number" min={7} max={90} defaultValue={r.aniversario_validade_dias} /></div>
            </div>
            <p className="cap muted" style={{ margin: 0 }}>No dia do aniversário (precisa ter a data de nascimento na ficha) ela recebe os parabéns pelo WhatsApp, no horário das mensagens. O presente entra como crédito e desconta sozinho na comanda, no botão de cashback.</p>
            <p className="cap muted" style={{ margin: 0 }}>O cashback vira crédito quando a comanda fecha (sem contar gorjeta, pacote e o próprio cashback) e aparece na próxima comanda da cliente. Crédito que vence para de valer.</p>
            {admin && <div><Enviar>Salvar</Enviar></div>}
          </fieldset>
        </AcaoForm>
      </section>

      {(() => {
        const g = c as typeof c & { fidelidade_ativa: boolean; fidelidade_niveis: { nome: string; pontos: number; bonus: number }[]; indicacao_credito_centavos: number; taxa_falta_centavos: number; venda_online: boolean; ficha_areas: string[]; ia_ativa: boolean; ia_instrucoes: string | null };
        const niveis = [...g.fidelidade_niveis, { nome: "", pontos: 0, bonus: 0 }, { nome: "", pontos: 0, bonus: 0 }, { nome: "", pontos: 0, bonus: 0 }].slice(0, 3);
        const AREAS = [["cabelo", "Cabelo"], ["unhas", "Unhas"], ["cilios_sobrancelha", "Cílios e sobrancelha"], ["pele", "Pele (limpeza, peeling)"], ["depilacao", "Depilação"]] as const;
        return (
          <section className="card stack" id="crescer">
            <h2>Fidelidade, indicação e vendas</h2>
            <AcaoForm action={salvarCrescer}>
              <fieldset disabled={!admin} style={{ border: 0, padding: 0, margin: 0, display: "grid", gap: 16, minWidth: 0 }}>
                <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}><input type="checkbox" name="fidelidade_ativa" defaultChecked={g.fidelidade_ativa} />Programa de fidelidade (1 ponto por real gasto nos últimos 12 meses)</label>
                <div className="niveis">{niveis.map((n, i) => (
                  <div key={i} className="row" style={{ gap: 8 }}>
                    <input name={`nivel_nome_${i}`} defaultValue={n.nome} maxLength={20} placeholder={["Prata", "Ouro", "Diamante"][i]} aria-label={`Nome do nível ${i + 1}`} />
                    <input name={`nivel_pontos_${i}`} type="number" min={1} defaultValue={n.pontos || ""} placeholder="pontos" aria-label={`Pontos do nível ${i + 1}`} />
                    <input name={`nivel_bonus_${i}`} inputMode="decimal" defaultValue={n.bonus || ""} placeholder="% de cashback extra" aria-label={`Bônus do nível ${i + 1}`} />
                  </div>))}</div>
                <p className="cap muted" style={{ margin: 0 }}>O bônus vira cashback extra em cada comanda da cliente daquele nível. Deixe o nome em branco para não usar o nível.</p>
                <div className="grid2">
                  <div className="field"><label htmlFor="ic">Crédito para quem indica uma amiga (R$)</label><input id="ic" name="indicacao_credito" inputMode="decimal" defaultValue={campoReais(g.indicacao_credito_centavos)} />
                    <span className="cap muted">Entra como cashback quando a amiga fecha a primeira comanda. 0 desliga.</span></div>
                  <div className="field"><label htmlFor="tf">Taxa por falta sem aviso (R$)</label><input id="tf" name="taxa_falta" inputMode="decimal" defaultValue={campoReais(g.taxa_falta_centavos)} />
                    <span className="cap muted">Cobrada na próxima comanda. VIP e quem pagou sinal não pagam. 0 desliga.</span></div>
                </div>
                <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}><input type="checkbox" name="venda_online" defaultChecked={g.venda_online} />Vender vale-presente e pacotes pelo link (Pix)</label>
                {g.venda_online && <p className="cap muted" style={{ margin: 0 }}>Página de compra: <a href={`${site}/s/${c.slug}/comprar`} target="_blank" rel="noopener">{site}/s/{c.slug}/comprar</a>. Escolha em Catálogos quais pacotes aparecem.</p>}
                <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Perguntas da ficha de primeira visita</span>
                  <div className="row">{AREAS.map(([v, t]) => (
                    <label key={v} className="chip" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}><input type="checkbox" name="areas" value={v} defaultChecked={g.ficha_areas.includes(v)} />{t}</label>
                  ))}</div></div>
                <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}><input type="checkbox" name="ia_ativa" defaultChecked={g.ia_ativa} />IA no WhatsApp: responde dúvidas em texto livre (preços, endereço, como funciona)</label>
                <div className="field"><label htmlFor="iai">O que a IA precisa saber além do cadastro (até 1.500 caracteres)</label>
                  <textarea id="iai" name="ia_instrucoes" maxLength={1500} defaultValue={g.ia_instrucoes ?? ""} style={{ minHeight: 80 }} placeholder="Ex.: Temos estacionamento na rua de trás. Aceitamos cartão e Pix. Não atendemos crianças menores de 5 anos." /></div>
                {admin && <div><Enviar>Salvar</Enviar></div>}
              </fieldset>
            </AcaoForm>
          </section>
        );
      })()}

      <section className="card stack" id="online">
        <h2>Agendamento online</h2>
        <p className="sm sec">Um link só do salão para a bio do Instagram, o Google e o status do WhatsApp. A cliente marca sem baixar app e sem criar senha, e só vê horários realmente livres.</p>
        <div className="pub-link"><code>{link}</code><Copiar texto={link} rotulo="Copiar link" /></div>
        <AcaoForm action={salvarOnline}>
          <fieldset disabled={!admin} style={{ border: 0, padding: 0, margin: 0, display: "grid", gap: 16, minWidth: 0 }}>
            <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="agendamento_online" defaultChecked={o.agendamento_online} />Aceitar agendamentos pelo link</label>
            <div className="grid2">
              <div className="field"><label htmlFor="ch">Cancelamento pelo link até (horas antes)</label><input id="ch" name="cancelamento_horas" type="number" min={0} max={168} defaultValue={o.cancelamento_horas} /></div>
              <div className="field"><label htmlFor="amin">Marcar com no mínimo (horas de antecedência)</label><input id="amin" name="antecedencia_min" type="number" min={0} max={72} defaultValue={o.antecedencia_min_horas} /></div>
              <div className="field"><label htmlFor="amax">Marcar com no máximo (dias à frente)</label><input id="amax" name="antecedencia_max" type="number" min={7} max={365} defaultValue={o.antecedencia_max_dias} /></div>
              <div className="field"><label htmlFor="spad">Sinal de quem "sempre paga sinal" (%)</label><input id="spad" name="sinal_padrao" type="number" min={1} max={100} defaultValue={o.sinal_padrao_percentual} /></div>
            </div>
            <p className="cap muted" style={{ margin: 0 }}>Valem para o link e para o robô do WhatsApp. A equipe pode marcar fora dessas regras pela agenda.</p>
            <div className="field"><label htmlFor="pol">Política de cancelamento (a cliente aceita antes de marcar)</label>
              <textarea id="pol" name="politica" maxLength={1000} defaultValue={o.politica_cancelamento ?? ""} placeholder={`Cancelamentos e remarcações até ${o.cancelamento_horas} horas antes do horário. Depois disso, ou em caso de falta, o sinal não é devolvido.`} style={{ minHeight: 70 }} /></div>
            <h3>Sinal por Pix</h3>
            <p className="sm sec">O sinal de cada serviço é definido em Catálogos ({comSinal ?? 0} {comSinal === 1 ? "serviço cobra" : "serviços cobram"} sinal hoje). Com a chave Pix, o sistema gera o QR Code com o valor certo; a recepção confirma na agenda quando o dinheiro cair.</p>
            <div className="grid2">
              <div className="field"><label htmlFor="pc">Chave Pix do salão</label><input id="pc" name="pix_chave" maxLength={77} defaultValue={o.pix_chave ?? ""} placeholder="CNPJ, e-mail, celular ou chave aleatória" /></div>
              <div className="field"><label htmlFor="pn">Nome do recebedor (até 25 letras)</label><input id="pn" name="pix_nome" maxLength={25} defaultValue={o.pix_nome ?? ""} /></div>
              <div className="field"><label htmlFor="pcd">Cidade (até 15 letras)</label><input id="pcd" name="pix_cidade" maxLength={15} defaultValue={o.pix_cidade ?? ""} /></div>
            </div>
            <details className="aj"><summary>Confirmação automática com Mercado Pago (opcional)</summary>
              <div className="aj-corpo stack">
                <p className="sm">Com o Access Token de produção da sua conta Mercado Pago (Seu negócio &gt; Configurações &gt; Credenciais), o Pix é gerado pelo Mercado Pago e o horário confirma sozinho quando a cliente paga. O token fica guardado só no servidor.</p>
                <div className="field"><label htmlFor="mp">Access Token</label><input id="mp" name="mp_token" type="password" autoComplete="off" placeholder="APP_USR-..." /></div>
                <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="mp_remover" />Remover o token e voltar para o Pix da chave</label>
              </div>
            </details>
            {admin && <div><Enviar>Salvar agendamento online</Enviar></div>}
          </fieldset>
        </AcaoForm>
      </section>
    </div>
  );
}
