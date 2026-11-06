import Link from "next/link";
import type { SupabaseClient } from "@supabase/supabase-js";
import { reais } from "@/lib/dinheiro";

/** Vales-presente com saldo, para conferir um código e imprimir o vale. */
export async function ValesAtivos({ supabase, fuso }: { supabase: SupabaseClient; fuso: string }) {
  const { data } = await supabase.from("vales_presente").select("id, codigo, para, valor_centavos, saldo_centavos, expira_em").eq("estado", "ativo").gt("saldo_centavos", 0).gt("expira_em", new Date().toISOString()).order("criado_em", { ascending: false }).limit(30);
  if (!data?.length) return null;
  const dia = (iso: string) => new Intl.DateTimeFormat("pt-BR", { timeZone: fuso, day: "2-digit", month: "2-digit", year: "numeric" }).format(new Date(iso));
  return (
    <section className="card stack">
      <h2>Vales-presente</h2>
      <div className="list">
        {data.map((v) => (
          <div key={v.id} className="item">
            <span><span className="t" style={{ letterSpacing: ".08em" }}>{v.codigo}</span> <span className="sm sec">· para {v.para} · vale até {dia(v.expira_em)}</span></span>
            <div className="row"><strong>{reais(v.saldo_centavos)}</strong>{v.saldo_centavos < v.valor_centavos && <span className="cap muted">de {reais(v.valor_centavos)}</span>}
              <Link className="btn ghost sm" href={`/caixa/vale/${v.id}`}>Imprimir</Link></div>
          </div>
        ))}
      </div>
    </section>
  );
}
