import type { SupabaseClient } from "@supabase/supabase-js";
import { BuscaCliente } from "@/components/busca-cliente";
import { CampoData } from "@/components/campo-data";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { dataBR } from "@/lib/format";
import { entrarNaEspera, sairDaEspera } from "./actions";

const PERIODO = { qualquer: "qualquer horário", manha: "manhã", tarde: "tarde", noite: "noite" } as const;
type Op = { id: string; nome: string };

/** Quem quer um horário que hoje está cheio. Se alguém cancelar, o sistema avisa essas clientes pelo WhatsApp. */
export async function ListaEspera({ supabase, data, servicos, profs }: { supabase: SupabaseClient; data: string; servicos: Op[]; profs: Op[] }) {
  const { data: es } = await supabase.from("lista_espera")
    .select("id, data_de, data_ate, periodo, estado, observacao, clientes(nome, telefone), servicos(nome), profissional_id")
    .in("estado", ["aguardando", "avisado"]).gte("data_ate", data).order("data_de").limit(100);
  const nomeProf = new Map(profs.map((p) => [p.id, p.nome]));
  const lista = (es ?? []) as unknown as { id: string; data_de: string; data_ate: string; periodo: keyof typeof PERIODO; estado: string; observacao: string | null; clientes: { nome: string; telefone: string | null } | null; servicos: { nome: string } | null; profissional_id: string | null }[];
  const hoje = lista.filter((e) => e.data_de <= data && e.data_ate >= data).length;
  return (
    <section className="card stack" id="espera">
      <div className="row between"><h2>Lista de espera</h2>{hoje > 0 && <span className="bd br">{hoje} {hoje === 1 ? "pessoa quer" : "pessoas querem"} horário neste dia</span>}</div>
      <p className="sm sec">Quando alguém cancelar um horário que combina, quem está aqui recebe o aviso pelo WhatsApp com o link para marcar. Quem marcar primeiro fica.</p>
      {lista.length > 0 && (
        <div className="list">
          {lista.map((e) => (
            <div key={e.id} className="item">
              <span><span className="t">{e.clientes?.nome}</span> <span className="sm sec">· {e.servicos?.nome} · {e.data_de === e.data_ate ? dataBR(e.data_de) : `${dataBR(e.data_de)} a ${dataBR(e.data_ate)}`} · {PERIODO[e.periodo]}{e.profissional_id ? ` · com ${nomeProf.get(e.profissional_id) ?? ""}` : ""}{e.observacao ? ` · ${e.observacao}` : ""}</span></span>
              <div className="row">
                {e.estado === "avisado" && <span className="bd wt">avisada de uma vaga</span>}
                <form action={sairDaEspera}><input type="hidden" name="id" value={e.id} /><button className="btn ghost sm" type="submit">Tirar da lista</button></form>
              </div>
            </div>
          ))}
        </div>
      )}
      <AcaoForm action={entrarNaEspera}>
        <div className="grid2">
          <div className="field"><label htmlFor="le-c">Cliente</label><BuscaCliente id="le-c" name="cliente_id" required /></div>
          <div className="field"><label htmlFor="le-s">Serviço</label><select id="le-s" name="servico_id" required defaultValue="">{<option value="" disabled>Escolha</option>}{servicos.map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}</select></div>
          <div className="field"><label htmlFor="le-p">Profissional</label><select id="le-p" name="profissional_id" defaultValue=""><option value="">Qualquer</option>{profs.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}</select></div>
          <div className="field"><label htmlFor="le-per">Período</label><select id="le-per" name="periodo" defaultValue="qualquer">{Object.entries(PERIODO).map(([k, t]) => <option key={k} value={k}>{t}</option>)}</select></div>
          <div className="field"><label htmlFor="le-de">De</label><CampoData id="le-de" name="data_de" defaultValue={data} required /></div>
          <div className="field"><label htmlFor="le-ate">Até</label><CampoData id="le-ate" name="data_ate" defaultValue={data} required /></div>
        </div>
        <div><Enviar className="btn sec">Colocar na lista</Enviar></div>
      </AcaoForm>
    </section>
  );
}
