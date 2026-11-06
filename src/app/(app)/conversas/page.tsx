import Link from "next/link";
import { exigirMembro } from "@/lib/auth";
import { Vazio } from "@/components/ilustracoes";

export const metadata = { title: "Conversas" };

export default async function Conversas() {
  const { membro } = await exigirMembro();
  return (
    <div className="inbox-vazio">
      <Vazio tipo="conversa">
        Escolha uma conversa para ler e responder.<br />
        <span className="sm">O robô marca horários sozinho; quando alguém da equipe responde, ele para.</span>
        {membro.papel === "admin" && <><br /><Link href="/whatsapp">Conexão com o WhatsApp</Link></>}
      </Vazio>
    </div>
  );
}
