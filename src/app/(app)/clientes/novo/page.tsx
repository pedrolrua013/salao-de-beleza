import Link from "next/link";
import { exigirMembro } from "@/lib/auth";
import { formatarTelefone } from "@/lib/telefone";
import { FormCliente } from "../form";
import { criarCliente } from "../actions";
import { voltaSegura } from "@/lib/volta";

export const metadata = { title: "Novo cliente" };

export default async function Novo({ searchParams }: { searchParams: Promise<{ nome?: string; telefone?: string; voltar?: string }> }) {
  await exigirMembro();
  const q = await searchParams;
  const voltar = voltaSegura(q.voltar);
  return (
    <div className="stack-lg">
      <div className="row between"><h1>Novo cliente</h1>{voltar && <Link className="btn ghost sm" href={voltar}>Voltar sem cadastrar</Link>}</div>
      <section className="card"><FormCliente action={criarCliente} voltar={voltar} padrao={{ nome: q.nome?.slice(0, 120), telefone: q.telefone ? formatarTelefone(q.telefone) : undefined }} /></section>
    </div>
  );
}
