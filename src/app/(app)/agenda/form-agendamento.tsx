"use client";
import { useEffect, useState, useTransition } from "react";
import { CampoData } from "@/components/campo-data";
import { BuscaCliente } from "@/components/busca-cliente";
import { AcaoForm, Enviar } from "@/components/acao-form";
import type { HorarioLivre } from "@/lib/slots";
import { criarAgendamento, sugerirHorarios } from "./actions";

type Op = { id: string; nome: string };
type Servico = Op & { descricao: string; variacoes: (Op & { descricao: string })[] };
type Props = { clienteInicial: { id: string; nome: string; telefone: string | null } | null; servicos: Servico[]; profs: Op[]; data: string; profPadrao: string };
type LinhaForm = { servico: string; prof: string; variacao: string; outroNome: string; outroMin: number };

const novaLinha = (prof: string): LinhaForm => ({ servico: "", prof, variacao: "", outroNome: "", outroMin: 30 });

/**
 * Novo agendamento: ao escolher serviço, profissional e dia, mostra os horários livres (e os encaixes na pausa de uma química).
 * Vários serviços podem ser em sequência (a mesma cliente) ou em grupo (noiva e madrinhas, na mesma hora). Pode repetir toda semana.
 */
export function FormAgendamento({ clienteInicial, servicos, profs, data, profPadrao }: Props) {
  const [linhas, setLinhas] = useState<LinhaForm[]>([novaLinha(profPadrao)]);
  const [modo, setModo] = useState<"sequencia" | "grupo">("sequencia");
  const [repetir, setRepetir] = useState("");
  const mudar = (k: number, campo: keyof LinhaForm, v: string | number) =>
    setLinhas((ls) => ls.map((l, i) => (i === k ? { ...l, [campo]: v, ...(campo === "servico" ? { variacao: "" } : {}) } : l)));
  const varsDe = (id: string) => servicos.find((s) => s.id === id)?.variacoes ?? [];
  // Serviço com tamanhos só fica pronto depois de escolher o tamanho.
  const prontas = linhas.filter((l) => l.servico && l.prof && (!varsDe(l.servico).length || l.variacao))
    .map(({ servico, prof, variacao, outroMin }) => ({ servico, prof, variacao: variacao || undefined, outroMin }));
  const chave = JSON.stringify([prontas, modo]);
  const [dia, setDia] = useState(data);
  const [hora, setHora] = useState("09:00");
  const [livres, setLivres] = useState<HorarioLivre[] | null>(null);
  const [carregando, iniciar] = useTransition();

  useEffect(() => {
    if (prontas.length === 0 || !dia) { setLivres(null); return; }
    let vivo = true;
    iniciar(async () => { const r = await sugerirHorarios(prontas, dia, modo); if (vivo) setLivres(r); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chave, dia]);

  const grupo = modo === "grupo";
  return (
    <AcaoForm action={criarAgendamento}>
      <input type="hidden" name="modo" value={modo} />
      <div className="grid2">
        <div className="field"><label htmlFor="cliente_id">{grupo ? "Cliente 1" : "Cliente"}</label>
          <BuscaCliente id="cliente_id" name="cliente_id" required inicial={clienteInicial} /></div>
        {linhas.map((l, k) => {
          const vars = varsDe(l.servico);
          return (
            <div key={k} className="ag-linha" style={{ display: "contents" }}>
              {grupo && k > 0
                ? <div className="field"><label htmlFor={`cl_${k}`}>Cliente {k + 1}</label><BuscaCliente id={`cl_${k}`} name="cliente_linha" required /></div>
                : <input type="hidden" name="cliente_linha" value="" />}
              <div className="field"><label htmlFor={`servico_${k}`}>{k === 0 ? "Serviço" : grupo ? `Serviço da cliente ${k + 1}` : `Depois, serviço ${k + 1}`}</label>
                <select id={`servico_${k}`} name="servico_id" required value={l.servico} onChange={(e) => mudar(k, "servico", e.target.value)}>
                  <option value="" disabled>Escolha</option>
                  {servicos.map((s) => <option key={s.id} value={s.id}>{s.nome}{s.variacoes.length ? ` · ${s.variacoes.length} tamanhos` : ` · ${s.descricao}`}</option>)}
                  <option value="outro">Outro (escrever)…</option>
                </select>
                {vars.length > 0 ? (
                  <div className="ag-tamanhos" role="radiogroup" aria-label="Tamanho do cabelo">
                    {vars.map((v) => (
                      <label key={v.id} className={`chip${l.variacao === v.id ? " on" : ""}`}>
                        <input type="radio" name={`tam_${k}`} value={v.id} checked={l.variacao === v.id} onChange={() => mudar(k, "variacao", v.id)} required />
                        {v.nome} <span className="cap sec">{v.descricao}</span>
                      </label>
                    ))}
                  </div>
                ) : null}
                <input type="hidden" name="variacao_id" value={l.variacao} />
                {l.servico === "outro" && (
                  <div className="ag-outro">
                    <input name={`outro_nome_${k}`} required minLength={2} maxLength={120} placeholder="Qual serviço? Ex.: Sobrancelha" aria-label="Nome do serviço" autoFocus
                      value={l.outroNome} onChange={(e) => mudar(k, "outroNome", e.target.value)} />
                    <select name={`outro_min_${k}`} aria-label="Duração" value={l.outroMin} onChange={(e) => mudar(k, "outroMin", Number(e.target.value))}>
                      {[15, 20, 30, 40, 45, 60, 75, 90, 120, 150, 180, 240].map((m) => <option key={m} value={m}>{m < 60 ? `${m} min` : `${Math.floor(m / 60)} h${m % 60 ? ` ${m % 60}` : ""}`}</option>)}
                    </select>
                  </div>
                )}</div>
              <div className="field"><label htmlFor={`prof_${k}`}>Profissional{k > 0 ? (grupo ? ` da cliente ${k + 1}` : ` do serviço ${k + 1}`) : ""}</label>
                <div className="row" style={{ gap: 6, flexWrap: "nowrap" }}>
                  <select id={`prof_${k}`} name="profissional_id" required value={l.prof} onChange={(e) => mudar(k, "prof", e.target.value)} style={{ flex: 1 }}>
                    <option value="" disabled>Escolha</option>
                    {profs.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
                  </select>
                  {k > 0 && <button type="button" className="btn ghost sm" aria-label={`Tirar a linha ${k + 1}`} onClick={() => setLinhas((ls) => ls.filter((_, i) => i !== k))}>×</button>}
                </div></div>
            </div>
          );
        })}
        <div className="field"><label htmlFor="data">Dia</label><CampoData id="data" name="data" value={dia} onChange={setDia} required /></div>
        <div className="field"><label htmlFor="hora">Horário</label><input id="hora" name="hora" type="time" step={300} required value={hora} onChange={(e) => setHora(e.target.value)} /></div>
        <div className="field"><label htmlFor="repetir">Repetir</label>
          <select id="repetir" name="repetir" value={repetir} onChange={(e) => setRepetir(e.target.value)}>
            <option value="">Não repetir</option><option value="7">Toda semana</option><option value="14">A cada 2 semanas</option><option value="mes">Todo mês</option>
          </select></div>
        {repetir && (
          <div className="field"><label htmlFor="vezes">Quantas vezes (contando esta)</label>
            <select id="vezes" name="vezes" defaultValue="4">{[2, 3, 4, 5, 6, 8, 10, 12].map((n) => <option key={n} value={n}>{n} vezes</option>)}</select></div>
        )}
      </div>
      {linhas.length < 3 && (
        <div className="row" style={{ gap: 6 }}>
          <button type="button" className="btn ghost sm" onClick={() => { setModo("sequencia"); setLinhas((ls) => [...ls, novaLinha(ls[ls.length - 1].prof)]); }}>+ Outro serviço em seguida</button>
          <button type="button" className="btn ghost sm" onClick={() => { setModo("grupo"); setLinhas((ls) => [...ls, novaLinha("")]); }}>+ Outra pessoa junto (grupo)</button>
        </div>
      )}
      {linhas.length > 1 && (
        <div className="seg" role="group" aria-label="Como os serviços acontecem">
          <button type="button" aria-pressed={!grupo} onClick={() => setModo("sequencia")}>Em sequência (mesma cliente)</button>
          <button type="button" aria-pressed={grupo} onClick={() => setModo("grupo")}>Ao mesmo tempo (grupo)</button>
        </div>
      )}
      {prontas.length > 0 && (
        <div className="sug" aria-live="polite">
          <p className="cap sec">{carregando ? "Procurando horários livres…" : livres?.length ? "Horários livres. Toque para escolher:" : "Nenhum horário livre na jornada desse dia. Você ainda pode digitar um horário."}</p>
          {!!livres?.length && (
            <div className="sug-lista">
              {livres.map((h) => (
                <button key={h.hora} type="button" className={`sug-h${h.encaixe ? " enc" : ""}${h.hora === hora ? " sel" : ""}`} aria-pressed={h.hora === hora} onClick={() => setHora(h.hora)}
                  title={h.encaixe ? "Encaixe na pausa de outra cliente" : undefined}>
                  {h.hora}{h.encaixe && <span className="sr"> (encaixe na pausa)</span>}
                </button>
              ))}
            </div>
          )}
          {livres?.some((h) => h.encaixe) && <p className="cap muted"><span className="sug-leg" aria-hidden="true" /> Encaixe: o horário cai na pausa da química de outra cliente.</p>}
        </div>
      )}
      <div><Enviar>{repetir ? "Agendar todas" : "Agendar"}</Enviar></div>
    </AcaoForm>
  );
}
