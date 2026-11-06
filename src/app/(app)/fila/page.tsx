import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { BuscaCliente } from "@/components/busca-cliente";
import { Vazio } from "@/components/ilustracoes";
import { carregarProfissionais } from "@/lib/agenda";
import { dataLocal, horaLocal, minutos, zonedToUtc, somarDias } from "@/lib/slots";
import { chamarDaFila, entrarNaFila, sairDaFila } from "./actions";

export const metadata = { title: "Fila" };

/**
 * Quem chega sem hora marcada (comum em barbearia). O rodízio sugere de quem é a vez: entre quem está livre agora,
 * quem atendeu menos hoje, e no empate quem está livre há mais tempo.
 */
export default async function Fila({ searchParams }: { searchParams: Promise<{ cliente?: string }> }) {
  const { supabase, salao } = await exigirMembro();
  const { cliente } = await searchParams;
  const { data: clienteInicial } = /^[0-9a-f-]{36}$/.test(cliente ?? "") ? await supabase.from("clientes").select("id, nome, telefone").eq("id", cliente!).maybeSingle() : { data: null };
  const agora = new Date();
  const hoje = dataLocal(agora, salao.fuso);
  const de = zonedToUtc(hoje, "00:00", salao.fuso).toISOString(), ate = zonedToUtc(somarDias(hoje, 1), "00:00", salao.fuso).toISOString();
  const [{ data: fila }, { data: srvs }, profs, { data: ags }, { data: ocs }] = await Promise.all([
    supabase.from("fila_atendimento").select("id, nome, servico_id, profissional_preferido, chegou_em").eq("estado", "aguardando").gte("chegou_em", de).order("chegou_em"),
    supabase.from("servicos").select("id, nome").eq("ativo", true).eq("avulso", false).order("nome"),
    carregarProfissionais(supabase, salao, hoje),
    supabase.from("agendamentos").select("profissional_id, status, fim").gte("inicio", de).lt("inicio", ate).in("status", ["em_atendimento", "concluido"]),
    supabase.from("ocupacoes").select("profissional_id").overlaps("periodo", `[${agora.toISOString()},${new Date(agora.getTime() + 60_000).toISOString()})`),
  ]);
  const ocupadosAgora = new Set((ocs ?? []).map((o) => o.profissional_id as string));
  const nomeSrv = new Map((srvs ?? []).map((s) => [s.id as string, s.nome as string]));
  const agoraMin = minutos(horaLocal(agora, salao.fuso));
  // Rodízio: quem está trabalhando agora e livre; menos atendimentos hoje primeiro; empate: quem terminou o último há mais tempo.
  const vez = profs
    .filter((p) => p.trabalha && minutos(p.abre) <= agoraMin && agoraMin < minutos(p.fecha) && !ocupadosAgora.has(p.id))
    .map((p) => {
      const meus = (ags ?? []).filter((a) => a.profissional_id === p.id);
      const ultimo = Math.max(0, ...meus.map((a) => Date.parse(a.fim as string)));
      return { ...p, atendimentos: meus.length, ultimo };
    })
    .sort((a, b) => a.atendimentos - b.atendimentos || a.ultimo - b.ultimo);
  const lista = (fila ?? []) as { id: string; nome: string; servico_id: string | null; profissional_preferido: string | null; chegou_em: string }[];
  const espera = (iso: string) => Math.max(0, Math.round((agora.getTime() - Date.parse(iso)) / 60_000));
  return (
    <div className="stack-lg">
      <h1>Fila de quem chegou sem hora</h1>
      <section className="card stack">
        <h2>Vez de quem</h2>
        {vez.length === 0 ? <p className="sec">Ninguém livre agora. Assim que alguém terminar, aparece aqui.</p> : (
          <div className="fila-vez">{vez.map((p, i) => (
            <span key={p.id} className={`chip${i === 0 ? " on" : ""}`}>{i === 0 ? "Próximo: " : ""}<strong>{p.nome}</strong> <span className="cap sec">{p.atendimentos} hoje</span></span>
          ))}</div>
        )}
      </section>
      <section className="card stack">
        <h2>Esperando ({lista.length})</h2>
        {lista.length === 0 ? <Vazio tipo="pessoas">Ninguém esperando.</Vazio> : (
          <div className="list">{lista.map((x, i) => {
            const sugerido = (x.profissional_preferido && vez.find((p) => p.id === x.profissional_preferido)) || vez[0];
            return (
              <div key={x.id} className="item fila-item">
                <span><span className="t">{i + 1}. {x.nome}</span> <span className="sm sec">· {x.servico_id ? nomeSrv.get(x.servico_id) ?? "Serviço" : "sem serviço"} · esperando há {espera(x.chegou_em)} min{x.profissional_preferido ? ` · prefere ${profs.find((p) => p.id === x.profissional_preferido)?.nome ?? ""}` : ""}</span></span>
                <div className="row" style={{ gap: 6 }}>
                  <AcaoForm action={chamarDaFila} className="row">
                    <input type="hidden" name="id" value={x.id} />
                    <select name="profissional" aria-label={`Quem atende ${x.nome}`} defaultValue={sugerido?.id ?? ""} required>
                      <option value="" disabled>Quem atende</option>
                      {profs.filter((p) => p.trabalha).map((p) => <option key={p.id} value={p.id}>{p.nome}{ocupadosAgora.has(p.id) ? " (ocupado)" : ""}</option>)}
                    </select>
                    <Enviar className="btn sm">Chamar</Enviar>
                  </AcaoForm>
                  <form action={sairDaFila}><input type="hidden" name="id" value={x.id} /><button className="btn ghost sm" type="submit">Foi embora</button></form>
                </div>
              </div>
            );
          })}</div>
        )}
      </section>
      <section className="card stack">
        <h2>Chegou alguém</h2>
        <AcaoForm action={entrarNaFila}>
          <div className="grid2">
            <div className="field"><label htmlFor="fc">Cliente (se tiver cadastro)</label><BuscaCliente id="fc" name="cliente_id" avulso inicial={clienteInicial} /></div>
            <div className="field"><label htmlFor="fn">Ou só o nome</label><input id="fn" name="nome" maxLength={120} placeholder="Ex.: João" /></div>
            <div className="field"><label htmlFor="fs">Serviço</label><select id="fs" name="servico_id" required defaultValue=""><option value="" disabled>Escolha</option>{(srvs ?? []).map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}</select></div>
            <div className="field"><label htmlFor="fp">Prefere alguém?</label><select id="fp" name="profissional" defaultValue=""><option value="">Quem estiver livre</option>{profs.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}</select></div>
          </div>
          <div><Enviar>Pôr na fila</Enviar></div>
        </AcaoForm>
      </section>
    </div>
  );
}
