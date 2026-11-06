import Link from "next/link";
import { notFound } from "next/navigation";
import QRCode from "qrcode";
import { clienteAdmin } from "@/lib/supabase/admin";
import { reais } from "@/lib/dinheiro";
import { hora } from "@/lib/format";
import { dataLocal } from "@/lib/slots";
import { dataLonga } from "@/lib/format";
import { cancelarOnline } from "../../actions";
import { Copiar } from "./copiar";

export const dynamic = "force-dynamic";
export const metadata = { title: "Seu horário" };

type H = {
  inicio: string; status: string; servico: string; profissional: string; cliente: string; salao: string; slug: string; fuso: string;
  endereco: string | null; telefone: string | null; cancelamento_horas: number; pode_cancelar: boolean; politica: string | null;
  sinal: { valor: number; status: string; modo: string; copia_cola: string | null; expira_em: string } | null;
  varios_profissionais: boolean;
};

/** Página do horário da cliente (link guardado no celular): ver, pagar o sinal e cancelar dentro do prazo. */
export default async function SeuHorario({ params, searchParams }: { params: Promise<{ slug: string; token: string }>; searchParams: Promise<{ ficha?: string; area?: string }> }) {
  const { slug, token } = await params;
  const { ficha, area } = await searchParams;
  const db = clienteAdmin();
  if (!db || !/^[0-9a-f-]{36}$/.test(token)) notFound();
  const { data } = await db.rpc("horario_publico", { p_token: token });
  if (!data) notFound();
  const h = data as H;
  const sinalPendente = h.sinal?.status === "pendente" && h.status === "agendado";
  const qr = sinalPendente && h.sinal?.copia_cola ? await QRCode.toDataURL(h.sinal.copia_cola, { margin: 1, width: 240 }) : null;
  const cancelado = h.status === "cancelado";
  return (
    <main className="pub">
      <header className="pub-cab"><img src="/icone.png" alt="" width={40} height={40} /><div><h1>{h.salao}</h1>{h.endereco && <p className="cap sec">{h.endereco}</p>}</div></header>
      <section className="card stack">
        <span className={`bd ${cancelado ? "no" : sinalPendente ? "wt" : "ok"}`} style={{ justifySelf: "start" }}>
          {cancelado ? "Horário cancelado" : sinalPendente ? "Aguardando o sinal" : h.status === "concluido" ? "Atendimento concluído" : "Horário confirmado"}
        </span>
        <h2>{h.cliente}, {cancelado ? "seu horário foi cancelado." : sinalPendente ? "falta só o sinal." : "está marcado!"}</h2>
        <div className="pub-resumo">
          <strong>{h.servico}</strong>
          <span>{dataLonga(dataLocal(new Date(h.inicio), h.fuso))}, às {hora(h.inicio, h.fuso)}</span>
          <span>com {h.profissional}</span>
        </div>
        {sinalPendente && h.sinal && (
          <div className="pub-pix stack">
            <p>Pague o sinal de <strong>{reais(h.sinal.valor)}</strong> por Pix até <strong>{hora(h.sinal.expira_em, h.fuso)}</strong> para garantir o horário. Depois disso ele é liberado.</p>
            {qr ? (
              <>
                <img src={qr} alt="QR Code do Pix" width={240} height={240} />
                <Copiar texto={h.sinal.copia_cola!} />
                <p className="cap muted">{h.sinal.modo === "mercadopago" ? "A confirmação chega sozinha em instantes depois do pagamento." : "Depois de pagar, o salão confere e confirma seu horário."}</p>
              </>
            ) : <p>O salão vai enviar os dados do Pix pelo WhatsApp{h.telefone ? ` (${h.telefone})` : ""}.</p>}
          </div>
        )}
        {h.sinal?.status === "pago" && <p className="okmsg">Sinal de {reais(h.sinal.valor)} recebido. Ele é descontado no dia.</p>}
        {h.sinal?.status === "credito" && <p className="okmsg">O sinal de {reais(h.sinal.valor)} ficou como crédito para sua próxima visita.</p>}
        {area && /^[0-9a-f]{64}$/.test(area) && (
          <div className="rebook"><span><strong>Sua área no salão</strong> Guarde este link: nele você vê seus horários, cashback e pacotes, e remarca sozinha.</span><Link className="btn sm" href={`/s/${slug}/minha/${area}`}>Abrir minha área</Link></div>
        )}
        {ficha && /^[0-9a-f]{64}$/.test(ficha) && !cancelado && (
          <div className="rebook"><span><strong>Primeira vez aqui?</strong> Responda a ficha rapidinho para o profissional já saber o que você precisa.</span><Link className="btn sm" href={`/s/${slug}/ficha/${ficha}`}>Preencher ficha</Link></div>
        )}
        {h.politica && <div className="pub-politica"><strong>Política de cancelamento que você aceitou</strong><p>{h.politica}</p></div>}
        {h.pode_cancelar ? (
          <div className="row">
            {!h.varios_profissionais && <Link className="btn sec" href={`/s/${slug}?remarcar=${token}`}>Remarcar</Link>}
            <form action={cancelarOnline}><input type="hidden" name="token" value={token} /><input type="hidden" name="slug" value={slug} /><button className="btn ghost" type="submit">Cancelar este horário</button></form>
          </div>
        ) : !cancelado && h.status !== "concluido" && <p className="cap muted">Remarcar ou cancelar pelo link só até {h.cancelamento_horas} horas antes. Depois disso, fale com o salão{h.telefone ? ` pelo ${h.telefone}` : ""}.</p>}
      </section>
      <Link className="btn sec" href={`/s/${slug}`}>Marcar outro horário</Link>
      <p className="cap muted pub-rodape">Guarde este link: é por ele que você vê e cancela seu horário.</p>
    </main>
  );
}
