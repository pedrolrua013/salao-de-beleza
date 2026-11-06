import type { SupabaseClient } from "@supabase/supabase-js";
import { reais } from "@/lib/dinheiro";

type Meta = { id: string; membro_id: string | null; tipo: "faturamento" | "produtos" | "atendimentos"; valor: number; realizado: number };
const ROTULO = { faturamento: "Faturamento", produtos: "Venda de produtos", atendimentos: "Atendimentos" } as const;

/** Metas do mês com a barra de quanto já foi feito. O banco só devolve as que a pessoa pode ver (dela e do salão). */
export async function MetasDoMes({ supabase, hoje, nomes }: { supabase: SupabaseClient; hoje: string; nomes: Map<string, string> }) {
  const { data } = await supabase.rpc("progresso_metas", { p_mes: hoje });
  const metas = (data ?? []) as Meta[];
  if (metas.length === 0) return null;
  const dia = Number(hoje.slice(8, 10)), diasNoMes = new Date(Number(hoje.slice(0, 4)), Number(hoje.slice(5, 7)), 0).getDate();
  const esperado = dia / diasNoMes;
  const fmt = (m: Meta, v: number) => (m.tipo === "atendimentos" ? String(v) : reais(v));
  return (
    <section className="card stack" aria-labelledby="metas-t">
      <div className="row between"><h2 id="metas-t">Metas do mês</h2><span className="cap muted">dia {dia} de {diasNoMes}</span></div>
      <div className="stack">{metas.sort((a, b) => (a.membro_id ? 1 : 0) - (b.membro_id ? 1 : 0)).map((m) => {
        const pct = Math.min(100, Math.round((Number(m.realizado) / m.valor) * 100));
        const noRitmo = Number(m.realizado) / m.valor >= esperado;
        return (
          <div key={m.id} className="meta">
            <div className="row between"><span className="t">{ROTULO[m.tipo]} · {m.membro_id ? nomes.get(m.membro_id) ?? "Profissional" : "Salão"}</span>
              <span className="sm">{fmt(m, Number(m.realizado))} <span className="muted">de {fmt(m, m.valor)}</span></span></div>
            <div className="meta-barra" role="img" aria-label={`${pct}% da meta`}><i style={{ width: `${pct}%` }} className={noRitmo ? "ok" : ""} /><b style={{ left: `${Math.round(esperado * 100)}%` }} /></div>
            <span className="cap muted">{pct >= 100 ? "Meta batida!" : noRitmo ? "No ritmo para bater" : "Abaixo do ritmo do mês"}</span>
          </div>
        );
      })}</div>
    </section>
  );
}
