import Link from "next/link";
import { hora, telefone } from "@/lib/format";
import { descreverFases, temPausa } from "@/lib/fases";
import type { LinhaAgenda } from "@/lib/agenda";
import { Selo } from "@/components/selo";
import { MaisAcoes } from "@/components/mais-acoes";
import { cancelarSerie, confirmarSinal, mudarStatus } from "@/app/(app)/agenda/actions";
import { reais } from "@/lib/dinheiro";
import { comandaDoHorario } from "@/app/(app)/caixa/actions";

function Botao({ id, status, texto, classe = "btn sec sm" }: { id: string; status: string; texto: string; classe?: string }) {
  return (
    <form action={mudarStatus}>
      <input type="hidden" name="id" value={id} /><input type="hidden" name="status" value={status} />
      <button className={classe} type="submit">{texto}</button>
    </form>
  );
}

/** Abre a comanda da cliente já com o serviço deste horário. */
function Comanda({ id, texto, classe }: { id: string; texto: string; classe: string }) {
  return (
    <form action={comandaDoHorario}>
      <input type="hidden" name="agendamento_id" value={id} />
      <button className={classe} type="submit">{texto}</button>
    </form>
  );
}

const PESSOA = <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4 3.500-7 8-7s8 3 8 7" /></svg>;
const FONE = <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z" /></svg>;

/** Um horário: hora à esquerda, quem e o quê no meio, situação e ações à direita. */
export function Linha({ a, tz, papel, usuarioId }: { a: LinhaAgenda; tz: string; papel: string; usuarioId: string }) {
  const aberto = a.status === "agendado" || a.status === "confirmado";
  // A recepção e o administrador movem qualquer horário; o profissional, só os próprios.
  const atende = papel !== "profissional" || a.profissional_id === usuarioId;
  const emAtendimento = a.status === "em_atendimento";
  return (
    <article className="ag" id={`ag-${a.id}`} data-s={a.status}>
      <div className="ag-hora">
        <strong>{hora(a.inicio, tz)}</strong>
        <span>até {hora(a.fim, tz)}</span>
      </div>

      <div className="ag-info">
        <Link href={`/clientes/${a.cliente_id}`} className="ag-nome">{a.vip && <span className="ag-vip" title="Cliente VIP">★ </span>}{a.cliente}</Link>
        <p className="ag-det">
          <span className="ag-srv">{a.servico}</span>
          {temPausa(a.fases) && <span className="ag-meta">{descreverFases(a.fases)}</span>}
          <span className="ag-meta">{PESSOA}{a.profissional}</span>
          {a.telefone && <span className="ag-meta">{FONE}{telefone(a.telefone)}</span>}
          {a.origem === "whatsapp" && <span className="ag-meta ag-wpp">via WhatsApp</span>}
          {a.origem === "online" && <span className="ag-meta ag-wpp">pelo link</span>}
          {a.serie_id && <span className="ag-meta">↻ se repete</span>}
        </p>
        {a.sinal && (
          <p className={`ag-lem ${a.sinal.status === "pago" || a.sinal.status === "usado" ? "ok" : a.sinal.status === "pendente" ? "wt" : "mu"}`}>
            {a.sinal.status === "pendente" ? `Sinal de ${reais(a.sinal.valor_centavos)} aguardando Pix` : a.sinal.status === "pago" ? `Sinal de ${reais(a.sinal.valor_centavos)} pago` : a.sinal.status === "usado" ? "Sinal já usado na comanda" : a.sinal.status === "credito" ? `Sinal virou crédito de ${reais(a.sinal.valor_centavos)}` : "Sinal expirado"}
            {a.sinal.status === "pendente" && papel !== "profissional" && <form action={confirmarSinal} style={{ display: "inline" }}><input type="hidden" name="id" value={a.id} /><button className="btn ghost sm" type="submit">Pix caiu: confirmar</button></form>}
          </p>
        )}
        {a.lembrete && <p className={`ag-lem ${a.lembrete.tom}`}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 5h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-6l-4 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" /></svg>{a.lembrete.texto}</p>}
      </div>

      <div className="ag-acoes">
        <Selo status={a.status} />
        {(aberto || emAtendimento) && (
          <div className="ag-botoes">
            {atende && !emAtendimento && <Botao id={a.id} status="em_atendimento" texto="Iniciar" classe="btn sm" />}
            {emAtendimento && <Comanda id={a.id} classe="btn sm" texto="Fechar na comanda" />}
            {emAtendimento && atende && <Botao id={a.id} status="concluido" texto="Concluir" />}
            {aberto && (
              <MaisAcoes rotulo={`Mais ações para ${a.cliente}`}>
                {a.status === "agendado" && <Botao id={a.id} status="confirmado" texto="Confirmar presença" classe="mais-item" />}
                <Comanda id={a.id} classe="mais-item" texto="Abrir comanda" />
                <Botao id={a.id} status="faltou" texto="Marcar falta" classe="mais-item" />
                <Botao id={a.id} status="cancelado" texto="Cancelar horário" classe="mais-item perigo" />
                {a.serie_id && (
                  <form action={cancelarSerie}><input type="hidden" name="serie_id" value={a.serie_id} /><input type="hidden" name="desde" value={a.inicio} />
                    <button className="mais-item perigo" type="submit">Cancelar este e os próximos</button></form>
                )}
              </MaisAcoes>
            )}
          </div>
        )}
      </div>
    </article>
  );
}
