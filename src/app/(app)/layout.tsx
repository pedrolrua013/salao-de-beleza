import Link from "next/link";
import { exigirMembro } from "@/lib/auth";
import { Nav } from "@/components/nav";
import { AlternarTema } from "@/components/alternar-tema";
import { sair } from "../entrar/actions";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { supabase, membro, salao } = await exigirMembro();
  const { data: nl } = await supabase.from("conversas").select("nao_lidas").gt("nao_lidas", 0).limit(200);
  const naoLidas = (nl ?? []).reduce((a, c) => a + c.nao_lidas, 0);
  return (
    <div className="shell">
      <a href="#conteudo" className="pular">Pular para o conteúdo</a>
      <aside className="side">
        <Link href="/hoje" className="logo" aria-label="Belezando, ir para Hoje"><img src="/icone.png" alt="" width={36} height={36} /><span>Belezando</span></Link>
        <Nav naoLidas={naoLidas} papel={membro.papel} permissoes={membro.permissoes ?? null} />
        <div className="stack" style={{ gap: 8 }}>
          <AlternarTema />
          <p className="who">{membro.nome}<br />{salao.nome}</p>
          <form action={sair}><button className="btn sec sm" type="submit">Sair</button></form>
        </div>
      </aside>
      <main id="conteudo" tabIndex={-1} className="main wrap">{children}</main>
    </div>
  );
}
