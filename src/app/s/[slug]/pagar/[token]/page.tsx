import QRCode from "qrcode";
import { notFound } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { reais } from "@/lib/dinheiro";
import { Copiar } from "@/app/s/[slug]/h/[token]/copiar";
import { Atualizar } from "@/components/atualizar";

export const dynamic = "force-dynamic";
export const metadata = { title: "Pagar pelo Pix", robots: { index: false } };

type Cobranca = { salao: string; slug: string; tipo: "comanda" | "vale" | "pacote"; valor_centavos: number; status: string; copia_cola: string | null; modo: string;
  presente_para: string | null; nome: string | null; pacote: string | null; itens: { descricao: string; valor: number }[] };

/** A cliente paga pelo celular: a comanda (ou o vale/pacote que comprou) com o Pix pronto para copiar ou ler o QR. */
export default async function Pagar({ params }: { params: Promise<{ slug: string; token: string }> }) {
  const { token } = await params;
  const db = clienteAdmin();
  if (!db || !/^[0-9a-f]{64}$/.test(token)) notFound();
  const { data } = await db.rpc("cobranca_publica", { p_token: token });
  if (!data) notFound();
  const c = data as Cobranca;
  const qr = c.status === "pendente" && c.copia_cola ? await QRCode.toDataURL(c.copia_cola, { margin: 1, width: 240 }) : null;
  const titulo = c.tipo === "vale" ? `Vale-presente para ${c.presente_para}` : c.tipo === "pacote" ? c.pacote ?? "Pacote" : "Sua comanda";
  return (
    <main className="pub">
      <header className="pub-cab"><img src="/icone.png" alt="" width={40} height={40} /><div><h1>{c.salao}</h1><p className="cap sec">Pagamento pelo Pix</p></div></header>
      <section className="card stack">
        <h2>{titulo}</h2>
        {c.itens.length > 0 && (
          <div className="list">{c.itens.map((i, k) => <div key={k} className="item"><span>{i.descricao}</span><span>{reais(i.valor)}</span></div>)}</div>
        )}
        <div className="pub-resumo"><strong>Total a pagar: {reais(c.valor_centavos)}</strong>{c.nome && <span>{c.nome}</span>}</div>
        {c.status === "paga" ? <p className="okmsg">Pagamento confirmado. Obrigado!{c.tipo !== "comanda" ? " O salão vai te mandar a confirmação." : ""}</p>
          : c.status === "cancelada" ? <p>Este link foi cancelado. Peça um novo ao salão.</p>
          : c.status === "expirada" ? <p>Este link venceu. Peça um novo ao salão.</p>
          : !c.copia_cola ? <p>O salão ainda não configurou o Pix. Pague no balcão.</p>
          : (
            <div className="pub-pix stack">
              {qr && <img src={qr} alt="QR Code do Pix" width={240} height={240} />}
              <p className="sm sec">Abra o app do banco, escolha Pix copia e cola e cole o código.</p>
              <Copiar texto={c.copia_cola} />
              <p className="cap muted">{c.modo === "mercadopago" ? "A confirmação aparece aqui sozinha em instantes." : "Depois de pagar, o salão confere e confirma."}</p>
              {c.modo === "mercadopago" && <Atualizar segundos={10} />}
            </div>
          )}
      </section>
      <p className="cap muted pub-rodape">Pagamento pelo Belezando</p>
    </main>
  );
}
