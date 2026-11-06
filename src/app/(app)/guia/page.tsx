import Link from "next/link";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { campoReais } from "@/lib/dinheiro";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { CampoTelefone } from "@/components/campo-telefone";
import { CampoEndereco } from "@/components/campo-endereco";
import { Copiar } from "@/app/s/[slug]/h/[token]/copiar";
import { Importador } from "../clientes/importar/importador";
import { convidar } from "../equipe/actions";
import { concluirGuia, guiaSalao, guiaServicos } from "./actions";

export const metadata = { title: "Configurar o salão" };

const PASSOS = ["Seu salão", "Serviços", "Equipe", "Clientes", "Pronto"] as const;
const DIAS = [[1, "Seg"], [2, "Ter"], [3, "Qua"], [4, "Qui"], [5, "Sex"], [6, "Sáb"], [7, "Dom"]] as const;
const PAPEL = { admin: "Administrador", profissional: "Profissional", recepcao: "Recepção" } as const;

/** Primeiro acesso: em cinco passos o salão sai pronto para receber agendamentos. */
export default async function Guia({ searchParams }: { searchParams: Promise<{ passo?: string }> }) {
  const { supabase, membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/hoje");
  const passo = Math.min(5, Math.max(1, Number((await searchParams).passo) || 1));
  const proximo = `/guia?passo=${passo + 1}`;

  return (
    <div className="stack-lg guia">
      <div className="stack" style={{ gap: 6 }}>
        <p className="cap sec" style={{ margin: 0 }}>Passo {passo} de {PASSOS.length}</p>
        <ol className="guia-passos" aria-label="Etapas">
          {PASSOS.map((t, i) => (
            <li key={t} className={i + 1 < passo ? "feito" : i + 1 === passo ? "atual" : ""} aria-current={i + 1 === passo ? "step" : undefined}>
              {i + 1 < passo ? <Link href={`/guia?passo=${i + 1}`}>{t}</Link> : <span>{t}</span>}
            </li>
          ))}
        </ol>
      </div>
      {passo === 1 && <PassoSalao salao={salao} />}
      {passo === 2 && <PassoServicos supabase={supabase} />}
      {passo === 3 && <PassoEquipe supabase={supabase} proximo={proximo} />}
      {passo === 4 && (
        <section className="card stack">
          <div><h1>Traga suas clientes</h1><p className="sec">Tem as clientes numa planilha ou em outro sistema? Importe tudo de uma vez. Se não tiver, pule: elas entram quando marcarem.</p></div>
          <Importador dddPadrao={salao.telefone?.replace(/\D/g, "").slice(0, 2) || null} depois={{ href: proximo, rotulo: "Continuar" }} />
          <div className="row between guia-rodape"><Link href="/guia?passo=3">Voltar</Link><Link className="btn sec" href={proximo}>Pular por agora</Link></div>
        </section>
      )}
      {passo === 5 && <PassoPronto slug={salao.slug} nome={salao.nome} online={(salao as typeof salao & { agendamento_online?: boolean }).agendamento_online !== false} />}
    </div>
  );
}

function PassoSalao({ salao }: { salao: Awaited<ReturnType<typeof exigirMembro>>["salao"] }) {
  return (
    <section className="card stack">
      <div><h1>Boas-vindas ao Belezando!</h1><p className="sec">Vamos deixar seu salão pronto em poucos minutos. Tudo isso dá para mudar depois em Salão.</p></div>
      <AcaoForm action={guiaSalao}>
        <div className="grid2">
          <div className="field"><label htmlFor="nome">Nome do salão</label><input id="nome" name="nome" defaultValue={salao.nome} required minLength={2} maxLength={120} /></div>
          <div className="field"><label htmlFor="telefone">WhatsApp do salão</label><CampoTelefone id="telefone" name="telefone" defaultValue={salao.telefone} /></div>
        </div>
        <CampoEndereco sempreAberto legenda="Endereço do salão" dica={salao.endereco ? `Hoje está: ${salao.endereco}. Deixe em branco para manter.` : "Aparece no link de agendamento e nos lembretes."} />
        <div className="field"><span className="cap" style={{ fontWeight: 500 }}>Dias que o salão abre</span>
          <div className="row">{DIAS.map(([n, t]) => (
            <label key={n} className="chip" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
              <input type="checkbox" name="dias" value={n} defaultChecked={salao.dias_semana.includes(n)} />{t}
            </label>))}</div></div>
        <div className="grid2">
          <div className="field"><label htmlFor="abre">Abre às</label><input id="abre" name="abre" type="time" defaultValue={salao.abre.slice(0, 5)} required /></div>
          <div className="field"><label htmlFor="fecha">Fecha às</label><input id="fecha" name="fecha" type="time" defaultValue={salao.fecha.slice(0, 5)} required /></div>
        </div>
        <div className="row between guia-rodape"><Link href="/hoje">Fazer depois</Link><Enviar>Salvar e continuar</Enviar></div>
      </AcaoForm>
    </section>
  );
}

async function PassoServicos({ supabase }: { supabase: Awaited<ReturnType<typeof exigirMembro>>["supabase"] }) {
  const { data } = await supabase.from("servicos").select("id, nome, preco_centavos, duracao_min, fases, ativo").order("nome");
  const servicos = (data ?? []) as { id: string; nome: string; preco_centavos: number; duracao_min: number; fases: unknown[]; ativo: boolean }[];
  return (
    <section className="card stack">
      <div><h1>O que o salão faz?</h1><p className="sec">Deixe marcados os serviços que vocês fazem e coloque o preço e o tempo de cada um. O preço vai para a comanda e para o link de agendamento.</p></div>
      <AcaoForm action={guiaServicos}>
        <div className="guia-srv" role="table" aria-label="Serviços">
          <div className="guia-srv-l guia-srv-cab" role="row"><span role="columnheader">Serviço</span><span role="columnheader">Preço (R$)</span><span role="columnheader">Tempo (min)</span></div>
          {servicos.map((s) => (
            <div key={s.id} className="guia-srv-l" role="row">
              <input type="hidden" name="id" value={s.id} />
              <label className="guia-srv-n" role="cell"><input type="checkbox" name={`ativo_${s.id}`} defaultChecked={s.ativo} />{s.nome}</label>
              <span role="cell"><input name={`preco_${s.id}`} inputMode="decimal" aria-label={`Preço de ${s.nome}`} defaultValue={s.preco_centavos ? campoReais(s.preco_centavos) : ""} placeholder="0,00" /></span>
              <span role="cell">{s.fases.length === 1
                ? <input name={`min_${s.id}`} type="number" min={10} max={480} step={5} aria-label={`Tempo de ${s.nome} em minutos`} defaultValue={s.duracao_min} />
                : <span className="sm sec" title="Tem pausa para a química agir; ajuste em Catálogos">{s.duracao_min} (com pausa)</span>}</span>
            </div>
          ))}
          <p className="cap sec" style={{ margin: "8px 0 0" }}>Faltou algum? Adicione aqui:</p>
          {[0, 1, 2].map((i) => (
            <div key={i} className="guia-srv-l" role="row">
              <span role="cell"><input name={`novo_nome_${i}`} maxLength={80} aria-label="Nome do serviço novo" placeholder={["Ex.: Progressiva", "Ex.: Design de sobrancelha", "Ex.: Alongamento de unha"][i]} /></span>
              <span role="cell"><input name={`novo_preco_${i}`} inputMode="decimal" aria-label="Preço do serviço novo" placeholder="0,00" /></span>
              <span role="cell"><input name={`novo_min_${i}`} type="number" min={10} max={480} step={5} aria-label="Tempo do serviço novo em minutos" placeholder="60" /></span>
            </div>
          ))}
        </div>
        <p className="cap muted" style={{ margin: 0 }}>Serviços com pausa (como coloração), sinal, preço por profissional e tamanhos de cabelo ficam em Catálogos.</p>
        <div className="row between guia-rodape"><Link href="/guia?passo=1">Voltar</Link><Enviar>Salvar e continuar</Enviar></div>
      </AcaoForm>
    </section>
  );
}

async function PassoEquipe({ supabase, proximo }: { supabase: Awaited<ReturnType<typeof exigirMembro>>["supabase"]; proximo: string }) {
  const { data } = await supabase.from("membros").select("user_id, nome, papel").order("nome");
  const equipe = (data ?? []) as { user_id: string; nome: string; papel: keyof typeof PAPEL }[];
  return (
    <section className="card stack">
      <div><h1>Quem trabalha com você?</h1><p className="sec">Cada pessoa entra com o próprio login e vê a própria agenda. Se você trabalha sem equipe, é só continuar.</p></div>
      <ul className="guia-equipe">{equipe.map((m) => <li key={m.user_id}><strong>{m.nome}</strong> <span className="sm sec">· {PAPEL[m.papel]}</span></li>)}</ul>
      <AcaoForm action={convidar}>
        <div className="guia-convite">
          <div className="field"><label htmlFor="cnome">Nome</label><input id="cnome" name="nome" required minLength={2} maxLength={120} placeholder="Ana Souza" /></div>
          <div className="field"><label htmlFor="cemail">E-mail</label><input id="cemail" name="email" type="email" required placeholder="ana@email.com" /></div>
          <div className="field"><label htmlFor="cpapel">Função</label>
            <select id="cpapel" name="papel" defaultValue="profissional"><option value="profissional">Profissional (atende)</option><option value="recepcao">Recepção</option><option value="admin">Administrador</option></select></div>
        </div>
        <div><Enviar className="btn sec">Enviar convite</Enviar></div>
      </AcaoForm>
      <p className="cap muted" style={{ margin: 0 }}>A pessoa recebe um e-mail para criar a senha. Horários de cada um, comissão e permissões ficam em Equipe.</p>
      <div className="row between guia-rodape"><Link href="/guia?passo=2">Voltar</Link><Link className="btn" href={proximo}>{equipe.length > 1 ? "Continuar" : "Trabalho sozinho(a), continuar"}</Link></div>
    </section>
  );
}

function PassoPronto({ slug, nome, online }: { slug: string; nome: string; online: boolean }) {
  const link = `${process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") ?? ""}/s/${slug}`;
  const texto = `Agora você pode marcar seu horário no ${nome} pelo link, a qualquer hora: ${link}`;
  return (
    <section className="card stack">
      <div><h1>Seu salão está pronto!</h1><p className="sec">Este é o link de agendamento. As clientes escolhem o serviço, o profissional e o horário livre, sem baixar aplicativo e sem senha.</p></div>
      <div className="guia-link"><code>{link}</code><Copiar texto={link} rotulo="Copiar link" /></div>
      <div className="row">
        <a className="btn sec" href={`https://wa.me/?text=${encodeURIComponent(texto)}`} target="_blank" rel="noopener noreferrer">Enviar no WhatsApp</a>
        <a className="btn sec" href={link} target="_blank" rel="noopener noreferrer">Ver como a cliente vê</a>
      </div>
      <p className="sm sec" style={{ margin: 0 }}>Dica: coloque o link na bio do Instagram e no status do WhatsApp.</p>
      <AcaoForm action={concluirGuia}>
        <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}>
          <input type="checkbox" name="online" defaultChecked={online} />Deixar as clientes marcarem pelo link
        </label>
        <div className="row between guia-rodape"><Link href="/guia?passo=4">Voltar</Link><Enviar>Ir para o salão</Enviar></div>
      </AcaoForm>
    </section>
  );
}
