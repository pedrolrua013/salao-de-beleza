import { fasesParaFormulario, type Fase } from "@/lib/fases";
import { campoReais } from "@/lib/dinheiro";

/** Nome e tempos de um serviço. Pausa é o tempo em que a química age e o profissional fica livre para outra cliente. */
export function CamposServico({ id, nome = "", fases, preco = 0, custo = 0, sinal = 0, online = true, retorno = null, cor = null, intervalo = 0 }: { id: string; nome?: string; fases?: Fase[]; preco?: number; custo?: number; sinal?: number; online?: boolean; retorno?: number | null; cor?: string | null; intervalo?: number }) {
  const t = fases ? fasesParaFormulario(fases) : { antes: 30, pausa: 0, depois: 0 };
  return (
    <div className="srv-campos">
      <div className="field srv-nome"><label htmlFor={`${id}-nome`}>Serviço</label><input id={`${id}-nome`} name="nome" required minLength={2} maxLength={120} defaultValue={nome} /></div>
      <div className="field"><label htmlFor={`${id}-preco`}>Preço (R$)</label><input id={`${id}-preco`} name="preco" inputMode="decimal" defaultValue={preco ? campoReais(preco) : ""} placeholder="0,00" /></div>
      <div className="field"><label htmlFor={`${id}-custo`}>Custo de produto (R$)</label><input id={`${id}-custo`} name="custo" inputMode="decimal" defaultValue={custo ? campoReais(custo) : ""} placeholder="0,00" /></div>
      <div className="field"><label htmlFor={`${id}-antes`}>Trabalho (min)</label><input id={`${id}-antes`} name="antes" type="number" min={5} max={480} step={5} defaultValue={t.antes} required /></div>
      <div className="field"><label htmlFor={`${id}-pausa`}>Pausa (min)</label><input id={`${id}-pausa`} name="pausa" type="number" min={0} max={480} step={5} defaultValue={t.pausa} aria-describedby="srv-ajuda" /></div>
      <div className="field"><label htmlFor={`${id}-depois`}>Finalização (min)</label><input id={`${id}-depois`} name="depois" type="number" min={0} max={480} step={5} defaultValue={t.depois} /></div>
      <div className="field"><label htmlFor={`${id}-sinal`}>Sinal online (%)</label><input id={`${id}-sinal`} name="sinal" type="number" min={0} max={100} step={5} defaultValue={sinal} /></div>
      <div className="field"><label htmlFor={`${id}-ret`}>Voltar em (dias)</label><input id={`${id}-ret`} name="retorno" type="number" min={7} max={365} defaultValue={retorno ?? ""} placeholder="—" /></div>
      <div className="field"><label htmlFor={`${id}-int`}>Intervalo depois (limpeza)</label>
        <select id={`${id}-int`} name="intervalo" defaultValue={intervalo}>{[0, 5, 10, 15, 20, 30].map((m) => <option key={m} value={m}>{m ? `${m} min` : "Nenhum"}</option>)}</select></div>
      <div className="field"><label htmlFor={`${id}-cor`}>Cor na agenda</label><input id={`${id}-cor`} name="cor" type="color" defaultValue={cor ?? "#8E80EF"} className="srv-cor" /></div>
      <label className="chip srv-online"><input type="checkbox" name="online" defaultChecked={online} />Aparece no link de agendamento</label>
    </div>
  );
}
