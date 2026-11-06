import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import Link from "next/link";

export const metadata = { title: "Importar e exportar" };

const EXPORTS = [
  ["clientes", "Clientes", "nome, telefone, e-mail, nascimento, origem, alergias e observações"],
  ["agenda", "Agenda", "todos os horários, com cliente, serviço, profissional e situação"],
  ["comandas", "Comandas", "cada item vendido, com cliente, profissional, valor e descontos"],
  ["comissoes", "Comissões", "a comissão de cada item e se já foi paga"],
  ["fichas", "Fichas técnicas", "fórmulas, técnicas e resultados de química"],
] as const;

/** Os dados são do salão: entram de planilha ou de outro sistema e saem quando o salão quiser, sem pedir a ninguém. */
export default async function Dados() {
  const { membro } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/hoje");
  return (
    <div className="stack-lg">
      <div><h1>Importar e exportar</h1><p className="sec">Seus dados são seus. Exporte tudo quando quiser, sem pedir ao suporte e sem multa.</p></div>
      <section className="card stack">
        <h2>Importar clientes</h2>
        <p className="sm sec">Traga as clientes de uma planilha do Excel, de um CSV ou do sistema antigo. Você confere as colunas antes de importar, e quem já existe não é duplicado.</p>
        <div><Link className="btn" href="/clientes/importar">Importar planilha</Link></div>
      </section>
      <section className="card stack">
        <h2>Exportar</h2>
        <div className="list">
          {EXPORTS.map(([k, t, d]) => (
            <div key={k} className="item"><span><span className="t">{t}</span> <span className="sm sec">· {d}</span></span><a className="btn sec sm" href={`/api/exportar/${k}`} download>Baixar CSV</a></div>
          ))}
          <div className="item"><span><span className="t">Tudo</span> <span className="sm sec">· cópia completa em JSON, para backup ou para levar a outro sistema</span></span><a className="btn sm" href="/api/exportar/tudo" download>Baixar tudo</a></div>
        </div>
      </section>
    </div>
  );
}
