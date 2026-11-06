import QRCode from "qrcode";
import { exigirMembro } from "@/lib/auth";
import { Imprimir } from "@/app/(app)/comissoes/parceria/imprimir";

export const metadata = { title: "Cartaz para o balcão" };

/** Cartaz em A4 com o QR Code do agendamento: imprimir e deixar no balcão ou no espelho. */
export default async function Cartaz() {
  const { salao } = await exigirMembro();
  const link = `${process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") ?? ""}/s/${salao.slug}`;
  const qr = await QRCode.toDataURL(`${link}?o=qr`, { margin: 1, width: 600 });
  return (
    <div className="stack-lg">
      <div className="row between nao-imprimir"><h1>Cartaz para o balcão</h1><Imprimir /></div>
      <section className="cartaz">
        <p className="cartaz-salao">{salao.nome}</p>
        <h2>Agende seu próximo horário pelo celular</h2>
        <img src={qr} alt="QR Code do agendamento" width={320} height={320} />
        <p>Aponte a câmera do celular para o código</p>
        <p className="cap">sem app e sem senha · {link.replace(/^https?:\/\//, "")}</p>
      </section>
    </div>
  );
}
