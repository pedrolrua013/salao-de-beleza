import Link from "next/link";
import { pode } from "@/lib/permissoes";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { clienteAdmin } from "@/lib/supabase/admin";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { dataCurta } from "@/lib/format";
import { AbasDivulgar } from "../abas";
import { todasAsLinhas } from "@/lib/paginar";
import { apagarCampanha, criarCampanha, dispararCampanha } from "../actions";

export const metadata = { title: "Campanhas no WhatsApp" };

type Campanha = { id: string; nome: string; mensagem: string; etiquetas: string[]; sumidas_dias: number | null; total: number; criada_em: string; disparada_em: string | null };

/** Mensagem para um grupo de clientes (por etiqueta ou por tempo sem vir), só para quem aceitou receber. */
export default async function Campanhas() {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "divulgar")) redirect("/hoje");
  const db = clienteAdmin();
  const [{ data: camps }, comEtiqueta, { data: conta }] = await Promise.all([
    supabase.from("campanhas").select("id, nome, mensagem, etiquetas, sumidas_dias, total, criada_em, disparada_em").order("criada_em", { ascending: false }).limit(30),
    todasAsLinhas<{ etiquetas: string[] }>((de, ate) => supabase.from("clientes").select("etiquetas").neq("etiquetas", "{}").order("id").range(de, ate)),
    db ? db.from("whatsapp_contas").select("salao_id").eq("salao_id", salao.id).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  const contagem = new Map<string, number>();
  for (const c of comEtiqueta) for (const e of c.etiquetas) contagem.set(e, (contagem.get(e) ?? 0) + 1);
  const etiquetas = [...contagem.entries()].sort((a, b) => b[1] - a[1]);
  const lista = (camps ?? []) as Campanha[];
  const publico = new Map(await Promise.all(lista.filter((c) => !c.disparada_em).map(async (c) =>
    [c.id, Number((await supabase.rpc("contar_publico_campanha", { p_etiquetas: c.etiquetas, p_sumidas_dias: c.sumidas_dias })).data ?? 0)] as const)));
  const quem = (c: Campanha) => [c.etiquetas.length ? `etiqueta ${c.etiquetas.join(" ou ")}` : "todas as clientes", c.sumidas_dias ? `sem vir há ${c.sumidas_dias} dias` : null].filter(Boolean).join(", ");
  return (
    <div className="stack-lg">
      <AbasDivulgar atual="/divulgar/campanhas" />
      {!conta && <div className="aviso" role="note">O WhatsApp do salão ainda não está conectado: as campanhas ficam salvas, mas só saem depois de conectar em <Link href="/whatsapp">WhatsApp</Link>.</div>}
      <section className="card stack">
        <h2>Nova campanha</h2>
        <AcaoForm action={criarCampanha}>
          <div className="field"><label htmlFor="cn">Nome (só você vê)</label><input id="cn" name="nome" maxLength={60} required placeholder="Ex.: Noivas de dezembro" /></div>
          <div className="field"><label htmlFor="cm">Mensagem</label>
            <textarea id="cm" name="mensagem" required minLength={10} maxLength={500} style={{ minHeight: 90 }} placeholder="Ex.: Dezembro chegou! Pacote noiva com 15% de desconto para quem marcar até dia 10." />
            <p className="cap muted" style={{ margin: 0 }}>Chega assim: “Olá, Maria! (sua mensagem) Para marcar: (link do salão). Responda PARAR para não receber mais.”</p></div>
          <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Para quem tem a etiqueta (sem marcar nada, vai para todas)</span>
            {etiquetas.length === 0 ? <p className="cap muted" style={{ margin: 0 }}>Nenhuma cliente com etiqueta ainda. Coloque etiquetas na ficha da cliente, como “noiva”, “loira” ou “vip”.</p> : (
              <div className="row">{etiquetas.map(([e, n]) => (
                <label key={e} className="chip" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}><input type="checkbox" name="etiquetas" value={e} />{e} <span className="muted">({n})</span></label>
              ))}</div>
            )}</div>
          <div className="field" style={{ maxWidth: 320 }}><label htmlFor="cs">Só quem não vem há</label>
            <select id="cs" name="sumidas_dias" defaultValue=""><option value="">Qualquer tempo</option>{[30, 45, 60, 90, 180, 365].map((d) => <option key={d} value={d}>{d} dias ou mais</option>)}</select></div>
          <div><Enviar>Salvar campanha</Enviar></div>
        </AcaoForm>
      </section>

      <section className="card stack">
        <h2>Campanhas</h2>
        {lista.length === 0 ? <p className="sm sec">Nenhuma campanha ainda.</p> : (
          <div className="list">{lista.map((c) => (
            <div key={c.id} className="item camp">
              <div className="stack" style={{ gap: 4, flex: 1, minWidth: 220 }}>
                <span><span className="t">{c.nome}</span> {c.disparada_em ? <span className="bd ok">enviada para {c.total} em {dataCurta(c.disparada_em, salao.fuso)}</span> : <span className="bd br">{publico.get(c.id) ?? 0} clientes vão receber</span>}</span>
                <span className="sm sec">{quem(c)}</span>
                <p className="camp-msg">{c.mensagem}</p>
              </div>
              {!c.disparada_em && (
                <div className="row" style={{ gap: 6 }}>
                  <AcaoForm action={dispararCampanha} className="row"><input type="hidden" name="id" value={c.id} /><Enviar className="btn sm">Enviar agora</Enviar></AcaoForm>
                  <form action={apagarCampanha}><input type="hidden" name="id" value={c.id} /><button className="btn ghost sm" type="submit">Apagar</button></form>
                </div>
              )}
            </div>
          ))}</div>
        )}
        <p className="cap muted">Só recebe quem aceitou mensagens do salão e não pediu PARAR. Clientes bloqueadas ficam de fora. No máximo uma campanha por dia e 2.000 clientes por campanha, para o WhatsApp não bloquear o número.</p>
      </section>
    </div>
  );
}
