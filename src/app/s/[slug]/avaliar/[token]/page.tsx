import { notFound } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { avaliar } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Como foi?" };

type A = { salao: string; cliente: string; nota: number | null; respondida: boolean; google: string | null; expirada: boolean };

/** Pergunta de 0 a 10. Quem dá 9 ou 10 é convidada a contar no Google; quem dá nota baixa fala direto com o salão. */
export default async function Avaliar({ params }: { params: Promise<{ slug: string; token: string }> }) {
  const { slug, token } = await params;
  const db = clienteAdmin();
  if (!db || !/^[0-9a-f]{64}$/.test(token)) notFound();
  const { data } = await db.rpc("avaliacao_publica", { p_token: token });
  if (!data) notFound();
  const a = data as A;
  return (
    <main className="pub">
      <header className="pub-cab"><img src="/icone.png" alt="" width={40} height={40} /><div><h1>{a.salao}</h1></div></header>
      <section className="card stack">
        {a.respondida ? (
          <>
            <p className="okmsg">Obrigado, {a.cliente}! Sua opinião chegou ao salão.</p>
            {a.nota !== null && a.nota >= 9 && a.google && (
              <div className="stack"><p>Que bom que você gostou! Pode contar isso no Google? Ajuda muito outras clientes a conhecerem o salão.</p>
                <a className="btn pub-btn" href={a.google} target="_blank" rel="noopener noreferrer">Avaliar no Google</a></div>
            )}
          </>
        ) : a.expirada ? <p>Este link expirou. Obrigado mesmo assim!</p> : (
          <>
            <h2>{a.cliente}, de 0 a 10, quanto você recomendaria o {a.salao} para uma amiga?</h2>
            <AcaoForm action={avaliar}>
              <input type="hidden" name="token" value={token} /><input type="hidden" name="slug" value={slug} />
              <fieldset className="nps"><legend className="sr">Nota de 0 a 10</legend>
                {Array.from({ length: 11 }, (_, n) => (
                  <label key={n} className={n <= 6 ? "baixa" : n <= 8 ? "media" : "alta"}><input type="radio" name="nota" value={n} required /><span>{n}</span></label>
                ))}
              </fieldset>
              <div className="nps-leg cap muted"><span>nada provável</span><span>com certeza</span></div>
              <div className="field"><label htmlFor="cm">Quer contar alguma coisa? (opcional)</label><textarea id="cm" name="comentario" maxLength={1000} style={{ minHeight: 80 }} /></div>
              <label className="pub-check"><input type="checkbox" name="publica" />Pode mostrar meu comentário (só com meu primeiro nome) na página do salão.</label>
              <Enviar className="btn pub-btn">Enviar</Enviar>
            </AcaoForm>
          </>
        )}
      </section>
    </main>
  );
}
