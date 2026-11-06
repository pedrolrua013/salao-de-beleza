"use client";
import { useActionState, useEffect, useRef, useState } from "react";
import { Enviar, type Estado } from "@/components/acao-form";
import { assinarTermo } from "./actions";

/** Perguntas (no termo de química, a resposta abre a pergunta seguinte), nome, CPF e a assinatura desenhada com o dedo. */
export function FormTermo({ token, slug, nome, quimica }: { token: string; slug: string; nome: string; quimica: boolean }) {
  const [estado, enviar] = useActionState(assinarTermo, {} as Estado);
  const [alergia, setAlergia] = useState("nao");
  const [gestante, setGestante] = useState("nao");
  const [assinatura, setAssinatura] = useState("");
  const quadro = useRef<HTMLCanvasElement>(null);
  const desenhando = useRef(false);

  // Quadro nítido em qualquer tela; papel branco e tinta escura, como no papel (aparece igual na impressão).
  useEffect(() => {
    const c = quadro.current!;
    const r = c.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    c.width = r.width * dpr; c.height = r.height * dpr;
    const ctx = c.getContext("2d")!;
    ctx.scale(dpr, dpr); ctx.lineWidth = 2.4; ctx.lineCap = "round"; ctx.lineJoin = "round";
    ctx.strokeStyle = "#171722";
  }, []);

  const ponto = (e: React.PointerEvent<HTMLCanvasElement>) => { const r = e.currentTarget.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top] as const; };
  function comecar(e: React.PointerEvent<HTMLCanvasElement>) {
    e.currentTarget.setPointerCapture(e.pointerId);
    desenhando.current = true;
    const ctx = e.currentTarget.getContext("2d")!, [x, y] = ponto(e);
    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 0.1, y + 0.1); ctx.stroke();
  }
  function mover(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!desenhando.current) return;
    const ctx = e.currentTarget.getContext("2d")!, [x, y] = ponto(e);
    ctx.lineTo(x, y); ctx.stroke();
  }
  function terminar(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!desenhando.current) return;
    desenhando.current = false;
    setAssinatura(e.currentTarget.toDataURL("image/png"));
  }
  function limpar() {
    const c = quadro.current!;
    c.getContext("2d")!.clearRect(0, 0, c.width, c.height);
    setAssinatura("");
  }

  if (estado.ok) return <p className="okmsg" role="status">{estado.ok}</p>;
  return (
    <form action={enviar} className="stack">
      <input type="hidden" name="token" value={token} /><input type="hidden" name="slug" value={slug} /><input type="hidden" name="assinatura" value={assinatura} />
      {quimica && (
        <>
          <fieldset className="pub-pergunta"><legend>Tem alergia ou já teve reação a algum produto de cabelo?</legend>
            {[["nao", "Não"], ["sim", "Sim"], ["ns", "Não sei"]].map(([v, t]) => <label key={v}><input type="radio" name="alergia" value={v} checked={alergia === v} onChange={() => setAlergia(v)} /> {t}</label>)}
          </fieldset>
          {alergia === "sim" && <div className="field"><label htmlFor="aq">Qual produto e o que aconteceu?</label><input id="aq" name="alergia_qual" maxLength={200} required autoFocus /></div>}
          <fieldset className="pub-pergunta"><legend>Está grávida ou amamentando?</legend>
            {[["nao", "Não"], ["sim", "Sim"]].map(([v, t]) => <label key={v}><input type="radio" name="gestante" value={v} checked={gestante === v} onChange={() => setGestante(v)} /> {t}</label>)}
          </fieldset>
          {gestante === "sim" && <p className="aviso-preco">Avise a profissional antes de começar: alguns produtos não são indicados na gestação e na amamentação.</p>}
          <fieldset className="pub-pergunta"><legend>Fez teste de mecha ou de alergia antes deste serviço?</legend>
            {[["sim", "Sim"], ["nao", "Não"], ["ns", "Não sei"]].map(([v, t]) => <label key={v}><input type="radio" name="teste" value={v} defaultChecked={v === "nao"} /> {t}</label>)}
          </fieldset>
        </>
      )}
      <div className="grid2">
        <div className="field"><label htmlFor="tn">Nome completo</label><input id="tn" name="nome" required minLength={3} maxLength={120} defaultValue={nome} autoComplete="name" /></div>
        <div className="field"><label htmlFor="tc">CPF (opcional)</label><input id="tc" name="cpf" inputMode="numeric" maxLength={14} placeholder="000.000.000-00" /></div>
      </div>
      <div className="field">
        <span className="cap" style={{ fontWeight: 500 }}>Assine aqui com o dedo</span>
        <canvas ref={quadro} className="assinatura" aria-label="Quadro para desenhar a assinatura"
          onPointerDown={comecar} onPointerMove={mover} onPointerUp={terminar} onPointerLeave={terminar} />
        <div className="row between"><span className="cap muted">{assinatura ? "Assinatura pronta." : "Desenhe sua assinatura no quadro."}</span><button type="button" className="btn ghost sm" onClick={limpar}>Limpar</button></div>
      </div>
      <label className="pub-check"><input type="checkbox" name="concordo" required />Li o termo acima e concordo com ele.</label>
      {estado.erro && <p className="err" role="alert">{estado.erro}</p>}
      <Enviar className="btn pub-btn">Assinar</Enviar>
    </form>
  );
}
