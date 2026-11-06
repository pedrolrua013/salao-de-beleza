import { notFound } from "next/navigation";
import { CampoOrigem } from "./campo-origem";
import { AREAS_FICHA } from "@/lib/fichas";
import { CampoData } from "@/components/campo-data";
import { clienteAdmin } from "@/lib/supabase/admin";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { responderFicha } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Ficha de primeira visita" };

const SIM_NAO = (nome: string, rotulo: string, naoSei = false) => (
  <fieldset className="pub-pergunta">
    <legend>{rotulo}</legend>
    <label><input type="radio" name={nome} value="nao" defaultChecked /> Não</label>
    <label><input type="radio" name={nome} value="sim" /> Sim</label>
    {naoSei && <label><input type="radio" name={nome} value="ns" /> Não sei</label>}
  </fieldset>
);

/** A cliente nova responde antes de vir. Sem login: o link é o segredo e vale 7 dias. */
export default async function FichaPrevia({ params }: { params: Promise<{ slug: string; token: string }> }) {
  const { slug, token } = await params;
  const db = clienteAdmin();
  if (!db || !/^[0-9a-f]{64}$/.test(token)) notFound();
  const { data } = await db.rpc("ficha_publica", { p_token: token });
  if (!data) notFound();
  const f = data as { salao: string; cliente: string; respondida: boolean; expirada: boolean; pedir_nascimento?: boolean; areas?: string[] };
  const areas = f.areas?.length ? f.areas : ["cabelo"];
  const cabelo = areas.includes("cabelo");
  const outras = areas.filter((a) => a !== "cabelo" && a in AREAS_FICHA) as (keyof typeof AREAS_FICHA)[];
  return (
    <main className="pub">
      <header className="pub-cab"><img src="/icone.png" alt="" width={40} height={40} /><div><h1>{f.salao}</h1><p className="cap sec">Ficha de primeira visita</p></div></header>
      <section className="card stack">
        {f.respondida ? <p className="okmsg">Obrigado, {f.cliente}! Sua ficha já está com a gente.</p>
          : f.expirada ? <p>Este link expirou. Peça um novo ao salão.</p> : (
          <>
            <h2>Oi, {f.cliente}! Conta pra gente um pouco sobre você</h2>
            <p className="sm sec">Leva 2 minutos e ajuda o profissional a acertar já na primeira vez. Só a equipe do salão vê.</p>
            <AcaoForm action={responderFicha}>
              <input type="hidden" name="token" value={token} /><input type="hidden" name="slug" value={slug} />
              {outras.length > 0 && cabelo && <h3>Cabelo</h3>}
              {cabelo && <>
              <fieldset className="pub-pergunta"><legend>Fez alguma química nos últimos 6 meses?</legend>
                {["Coloração", "Descoloração", "Mechas", "Progressiva ou alisamento", "Permanente ou relaxamento", "Aplicou tinta recentemente"].map((t) => <label key={t}><input type="checkbox" name="quimica" value={t} /> {t}</label>)}
                <label className="pub-outro">Outro:<input name="quimica_outro" maxLength={60} placeholder="Escreva qual foi" aria-label="Outra química" /></label>
              </fieldset>
              <div className="field"><label htmlFor="qq">Quando foi a última?</label><input id="qq" name="quimica_quando" maxLength={80} placeholder="Ex.: há 2 meses" /></div>
              </>}
              <div className="field"><label htmlFor="al">Tem alguma alergia?</label><input id="al" name="alergias" maxLength={200} placeholder="Ex.: amônia, PPD, látex" /></div>
              {cabelo && SIM_NAO("reacao_tintura", "Já teve reação a tintura ou química de cabelo?")}
              {cabelo && SIM_NAO("couro_sensivel", "Seu couro cabeludo é sensível?", true)}
              {SIM_NAO("gestante", "Está grávida ou amamentando?")}
              <div className="field"><label htmlFor="md">Toma algum remédio que mexe com pele ou cabelo? (ex.: Roacutan)</label><input id="md" name="medicamento" maxLength={120} /></div>
              {outras.map((a) => (
                <div key={a} className="stack" style={{ gap: 10 }}>
                  <h3>{AREAS_FICHA[a].titulo}</h3>
                  {AREAS_FICHA[a].perguntas.map((p) => (
                    <fieldset key={p.chave} className="pub-pergunta"><legend>{p.texto}</legend>
                      {(p.tipo === "opcoes" ? (p.opcoes ?? []).map((o) => [o, o]) : [["nao", "Não"], ["sim", "Sim"], ...(p.tipo === "simnaons" ? [["ns", "Não sei"]] : [])]).map(([v, t]) => (
                        <label key={v}><input type="radio" name={p.chave} value={v} defaultChecked={p.tipo !== "opcoes" && v === "nao"} /> {t}</label>
                      ))}
                    </fieldset>
                  ))}
                </div>
              ))}
              <div className="field"><label htmlFor="ob">{cabelo ? "O que você quer fazer no cabelo?" : "O que você quer fazer?"}</label><textarea id="ob" name="objetivo" maxLength={400} style={{ minHeight: 70 }} placeholder="Ex.: cobrir os brancos, clarear as pontas, tirar volume" /></div>
              {f.pedir_nascimento && <div className="field"><label htmlFor="na">Data de nascimento (para um mimo no seu aniversário)</label><CampoData id="na" name="nascimento" inicio="ano" max="hoje" /></div>}
              <CampoOrigem />
              <Enviar className="btn pub-btn">Enviar ficha</Enviar>
            </AcaoForm>
          </>
        )}
      </section>
      <p className="cap muted pub-rodape">Seus dados ficam só com o salão, para o seu atendimento.</p>
    </main>
  );
}
