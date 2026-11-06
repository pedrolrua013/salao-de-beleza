import { blocos, descreverFases } from "@/lib/fases";
import { horaLocal, minutos, zonedToUtc } from "@/lib/slots";
import type { LinhaAgenda, ProfDia } from "@/lib/agenda";
import type { Bloqueio } from "@/lib/types";
import { removerBloqueio } from "@/app/(app)/agenda/actions";

const PX = 1.4; // pixels por minuto

type Props = {
  data: string; dia: LinhaAgenda[]; profs: ProfDia[]; bloqueios: Bloqueio[];
  tz: string; abre: string; fecha: string; agora: Date | null;
  podeRemover: (b: Bloqueio) => boolean;
};

/** Minutos desde a meia-noite local, presos ao dia (bloqueios de vários dias). */
function noDia(iso: number, inicioDia: number, tz: string) {
  if (iso <= inicioDia) return 0;
  if (iso >= inicioDia + 86_400_000) return 1440;
  return minutos(horaLocal(new Date(iso), tz));
}

/** Uma coluna por profissional, com as fases de cada atendimento: o trabalho cheio e a pausa listrada. */
export function GradeAgenda({ data, dia, profs, bloqueios, tz, abre, fecha, agora, podeRemover }: Props) {
  const ativos = dia.filter((a) => a.status !== "cancelado" && a.status !== "faltou");
  const inicioDia = zonedToUtc(data, "00:00", tz).getTime();
  const min = (iso: string) => minutos(horaLocal(iso, tz));
  let ini = Math.min(minutos(abre), ...profs.map((p) => minutos(p.abre)), ...ativos.map((a) => min(a.inicio)));
  let fim = Math.max(minutos(fecha), ...profs.map((p) => minutos(p.fecha)), ...ativos.map((a) => min(a.inicio) + (Date.parse(a.fim) - Date.parse(a.inicio)) / 60_000));
  ini = Math.max(0, Math.floor(ini / 60) * 60); fim = Math.min(1440, Math.ceil(fim / 60) * 60);
  const y = (m: number) => (Math.min(Math.max(m, ini), fim) - ini) * PX;
  const horas = Array.from({ length: (fim - ini) / 60 + 1 }, (_, i) => ini + i * 60);
  const agoraMin = agora ? minutos(horaLocal(agora, tz)) : null;

  // Pausas de cada profissional: quem começa dentro de uma delas é encaixe e vai um pouco para a direita.
  const pausasDe = new Map<string, [number, number][]>();
  for (const a of ativos) for (const b of blocos(Date.parse(a.inicio), a.fases)) if (b.tipo === "pausa") (pausasDe.get(a.profissional_id) ?? pausasDe.set(a.profissional_id, []).get(a.profissional_id)!).push([b.inicio, b.fim]);

  return (
    <div className="grade" style={{ ["--pm" as string]: `${PX}px`, ["--alt" as string]: `${(fim - ini) * PX}px`, ["--cols" as string]: profs.length }}>
      <div className="grade-horas" aria-hidden="true">
        {horas.map((h) => <span key={h} style={{ top: y(h) }}>{String(h / 60).padStart(2, "0")}h</span>)}
      </div>
      <div className="grade-cols">
        {profs.map((p) => {
          const meus = ativos.filter((a) => a.profissional_id === p.id);
          const pausas = pausasDe.get(p.id) ?? [];
          return (
            <section key={p.id} className="grade-col" aria-label={`Agenda de ${p.nome}`}>
              <h3 className="grade-cab">{p.nome}</h3>
              <div className="grade-corpo" data-prof={p.id} data-ini={ini} data-pm={PX}>
                {!p.trabalha && <div className="gb-folga" style={{ top: 0, height: y(fim) }}><span>Folga</span></div>}
                {p.trabalha && minutos(p.abre) > ini && <div className="gb-fora" style={{ top: 0, height: y(minutos(p.abre)) }} />}
                {p.trabalha && minutos(p.fecha) < fim && <div className="gb-fora" style={{ top: y(minutos(p.fecha)), height: y(fim) - y(minutos(p.fecha)) }} />}
                {p.trabalha && p.almoco && <div className="gb-almoco" style={{ top: y(minutos(p.almoco.inicio)), height: y(minutos(p.almoco.fim)) - y(minutos(p.almoco.inicio)) }}><span>Almoço</span></div>}
                {bloqueios.filter((b) => b.profissional_id === p.id).map((b) => {
                  const bi = noDia(Date.parse(b.inicio), inicioDia, tz), bf = noDia(Date.parse(b.fim), inicioDia, tz);
                  return (
                    <div key={b.id} className="gb-bloq" style={{ top: y(bi), height: Math.max(y(bf) - y(bi), 22) }}>
                      <span>{b.motivo || "Bloqueado"}</span>
                      {podeRemover(b) && (
                        <form action={removerBloqueio}><input type="hidden" name="id" value={b.id} /><button type="submit" className="gb-x" aria-label={`Remover bloqueio de ${p.nome}`}>×</button></form>
                      )}
                    </div>
                  );
                })}
                {meus.map((a) => {
                  const t0 = Date.parse(a.inicio);
                  const encaixe = pausas.some(([x, z]) => t0 >= x && t0 < z);
                  const segs = blocos(t0, a.fases);
                  return (
                    <a key={a.id} href={`#ag-${a.id}`} className={`gb${encaixe ? " gb-encaixe" : ""}`} data-s={a.status} data-id={a.id}
                      draggable={a.status === "agendado" || a.status === "confirmado"}
                      style={{ top: y(min(a.inicio)), height: (Date.parse(a.fim) - t0) / 60_000 * PX, ...(a.cor ? { ["--cor-srv" as string]: a.cor } : {}) }}
                      aria-label={`${horaLocal(a.inicio, tz)}, ${a.cliente}, ${a.servico} (${descreverFases(a.fases)})${encaixe ? ", encaixe na pausa" : ""}`}>
                      <span className="gb-rot"><strong>{horaLocal(a.inicio, tz)} {a.vip ? "★ " : ""}{a.cliente}</strong><em>{a.servico}</em></span>
                      {segs.map((s, i) => (
                        <span key={i} className={`gb-seg ${s.tipo}`} style={{ height: (s.fim - s.inicio) / 60_000 * PX }}>
                          {s.tipo === "pausa" && <em>pausa</em>}
                        </span>
                      ))}
                    </a>
                  );
                })}
                {agoraMin !== null && agoraMin >= ini && agoraMin <= fim && <div className="gb-agora" style={{ top: y(agoraMin) }} aria-hidden="true" />}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}
