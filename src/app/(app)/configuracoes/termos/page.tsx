import Link from "next/link";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { modelosDoSalao, type ModeloTermo } from "@/lib/termos";
import { apagarModelo, salvarModelo } from "./actions";

export const metadata = { title: "Termos para assinar" };

const TIPOS: Record<string, string> = { quimica: "Química (com perguntas de alergia, gestação e teste)", imagem: "Uso de imagem (registra a autorização na ficha)", outro: "Outro" };

/** Textos dos termos que a cliente assina. Os prontos podem ser ajustados; o termo já assinado guarda o texto da época. */
export default async function Termos() {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/configuracoes");
  const { data } = await supabase.from("termos_modelos").select("id, tipo, titulo, texto").order("titulo");
  const modelos = modelosDoSalao((data ?? []) as ModeloTermo[]);
  return (
    <div className="stack-lg">
      <div className="row between"><h1>Termos para assinar</h1><Link className="btn ghost sm" href="/configuracoes">← Salão</Link></div>
      <p className="sec">A cliente assina com o dedo, no celular dela ou no tablet do salão, pela ficha dela em Clientes. Os textos prontos são um ponto de partida: vale revisar com o advogado do salão.</p>
      {modelos.map((m) => (
        <section key={m.id} className="card stack">
          <div className="row between"><h2>{m.titulo}</h2>{m.padrao ? <span className="bd mu">texto pronto</span> : <span className="bd br">texto do salão</span>}</div>
          <AcaoForm action={salvarModelo}>
            <input type="hidden" name="id" value={m.id} /><input type="hidden" name="tipo" value={m.tipo} />
            <div className="field"><label htmlFor={`t-${m.id}`}>Título</label><input id={`t-${m.id}`} name="titulo" defaultValue={m.titulo} required minLength={3} maxLength={80} /></div>
            <div className="field"><label htmlFor={`x-${m.id}`}>Texto (deixe uma linha em branco entre os parágrafos)</label><textarea id={`x-${m.id}`} name="texto" defaultValue={m.texto} required minLength={20} maxLength={8000} style={{ minHeight: 200 }} /></div>
            <p className="cap muted" style={{ margin: 0 }}>Tipo: {TIPOS[m.tipo]}</p>
            <div className="row" style={{ gap: 8 }}><Enviar>Salvar</Enviar></div>
          </AcaoForm>
          {!m.padrao && <form action={apagarModelo}><input type="hidden" name="id" value={m.id} /><button className="btn ghost sm" type="submit">{m.tipo === "outro" ? "Apagar este termo" : "Voltar ao texto pronto"}</button></form>}
        </section>
      ))}
      <section className="card stack">
        <h2>Novo termo</h2>
        <AcaoForm action={salvarModelo}>
          <input type="hidden" name="tipo" value="outro" />
          <div className="field"><label htmlFor="nt">Título</label><input id="nt" name="titulo" required minLength={3} maxLength={80} placeholder="Ex.: Termo de micropigmentação" /></div>
          <div className="field"><label htmlFor="nx">Texto</label><textarea id="nx" name="texto" required minLength={20} maxLength={8000} style={{ minHeight: 160 }} /></div>
          <div><Enviar>Criar termo</Enviar></div>
        </AcaoForm>
      </section>
    </div>
  );
}
