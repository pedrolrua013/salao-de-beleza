import Link from "next/link";

export default function NaoEncontrado() {
  return (
    <main className="auth"><div className="card stack">
      <h1>Página não encontrada</h1>
      <p className="sec">O endereço não existe ou foi removido.</p>
      <Link className="btn" href="/hoje">Ir para o início</Link>
    </div></main>
  );
}
