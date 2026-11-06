import { notFound } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { FormTermo } from "./form-termo";

export const dynamic = "force-dynamic";
export const metadata = { title: "Assinar termo", robots: { index: false } };

/** A cliente lê e assina o termo pelo celular (ou no tablet do salão). Sem login: o link é o segredo e vale 7 dias. */
export default async function AssinarTermo({ params }: { params: Promise<{ slug: string; token: string }> }) {
  const { slug, token } = await params;
  const db = clienteAdmin();
  if (!db || !/^[0-9a-f]{64}$/.test(token)) notFound();
  const { data } = await db.rpc("termo_publico", { p_token: token });
  if (!data) notFound();
  const t = data as { salao: string; cliente: string; tipo: string; titulo: string; texto: string; assinado: boolean; expirado: boolean };
  return (
    <main className="pub">
      <header className="pub-cab"><img src="/icone.png" alt="" width={40} height={40} /><div><h1>{t.salao}</h1><p className="cap sec">Termo para assinar</p></div></header>
      <section className="card stack">
        <h2>{t.titulo}</h2>
        <div className="termo-texto">{t.texto.split(/\n{2,}/).map((p, i) => <p key={i}>{p}</p>)}</div>
        {t.assinado ? <p className="okmsg">Este termo já foi assinado. Obrigado!</p>
          : t.expirado ? <p>Este link expirou. Peça um novo ao salão.</p>
          : <FormTermo token={token} slug={slug} nome={t.cliente} quimica={t.tipo === "quimica"} />}
      </section>
      <p className="cap muted pub-rodape">Assinatura eletrônica pelo Belezando · fica guardada com data, hora e aparelho</p>
    </main>
  );
}
