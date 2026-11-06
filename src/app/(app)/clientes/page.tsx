import Link from "next/link";
import { Vazio } from "@/components/ilustracoes";
import { exigirMembro } from "@/lib/auth";
import { idade, telefone } from "@/lib/format";
import type { Cliente } from "@/lib/types";

export const metadata = { title: "Clientes" };

export default async function Clientes({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q = "" } = await searchParams;
  const { supabase, membro } = await exigirMembro();
  let query = supabase.from("clientes").select("id, nome, telefone, nascimento", { count: "exact" }).order("nome").limit(200);
  const termo = q.trim();
  if (termo.startsWith("#")) query = query.contains("etiquetas", [termo.slice(1).trim().toLowerCase()]);
  else if (termo) {
    const dig = termo.replace(/\D/g, "");
    query = dig.length >= 4 && dig.length === termo.replace(/[\s()-]/g, "").length
      ? query.ilike("telefone", `%${dig}%`)
      : query.ilike("nome", `%${termo.replace(/[%,()]/g, " ").replace(/[\\_]/g, (c) => `\\${c}`)}%`);
  }
  const { data, count } = await query;
  const lista = (data ?? []) as Cliente[];
  return (
    <div className="stack-lg">
      <div className="row between"><h1>Clientes</h1><div className="row"><Link className="btn sec" href="/clientes/sumidas">Chamar de volta</Link>{membro.papel === "admin" && <Link className="btn sec" href="/clientes/importar">Importar planilha</Link>}<Link className="btn" href="/clientes/novo">Novo cliente</Link></div></div>
      <form className="row" role="search" action="/clientes">
        <div className="field" style={{ flex: 1, minWidth: 220 }}>
          <label htmlFor="q" className="cap muted">Buscar por nome, telefone ou etiqueta (ex.: #noiva)</label>
          <input id="q" name="q" type="search" defaultValue={q} />
        </div>
        <button className="btn sec" type="submit" style={{ alignSelf: "flex-end" }}>Buscar</button>
      </form>
      {count !== null && count > lista.length && <p className="cap muted" style={{ margin: 0 }}>Mostrando {lista.length} de {count} clientes. Busque pelo nome, telefone ou etiqueta para achar as outras.</p>}
      <section className="card">
        {lista.length === 0 ? (
          <Vazio tipo="pessoas">{termo ? "Nenhum cliente encontrado." : "Nenhum cliente cadastrado ainda."}</Vazio>
        ) : (
          <div className="list">
            {lista.map((p) => (
              <Link key={p.id} href={`/clientes/${p.id}`} className="item" style={{ textDecoration: "none", color: "var(--ink)" }}>
                <span className="t">{p.nome}</span>
                <span className="sm sec">{[idade(p.nascimento) !== null ? `${idade(p.nascimento)} anos` : null, telefone(p.telefone)].filter(Boolean).join(" · ")}</span>
              </Link>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
