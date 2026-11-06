import Link from "next/link";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { Importador } from "./importador";

export const metadata = { title: "Importar clientes" };

/** Traz as clientes de uma planilha ou de outro sistema, sem digitar uma por uma. */
export default async function ImportarClientes() {
  const { membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/clientes");
  return (
    <div className="stack-lg">
      <div className="row between">
        <div><h1>Importar clientes</h1><p className="sec">Traga o cadastro da sua planilha ou do sistema antigo, sem digitar uma por uma.</p></div>
        <Link className="btn sec" href="/clientes">Voltar</Link>
      </div>
      <section className="card"><Importador dddPadrao={salao.telefone?.replace(/\D/g, "").slice(0, 2) || null} /></section>
    </div>
  );
}
