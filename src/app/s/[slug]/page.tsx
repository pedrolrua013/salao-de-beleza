import Link from "next/link";
import { notFound } from "next/navigation";
import { clienteAdmin } from "@/lib/supabase/admin";
import { criarDisponibilidade } from "@/lib/disponibilidade";
import { descreverFases } from "@/lib/fases";
import { reais } from "@/lib/dinheiro";
import { dataLonga } from "@/lib/format";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { CampoTelefone } from "@/components/campo-telefone";
import { agendarOnline, remarcarOnline } from "./actions";
import { Vitrine } from "./vitrine";
import { comDesconto, promocaoPara, type Promocao } from "@/lib/promocoes";
import { zonedToUtc } from "@/lib/slots";

export const dynamic = "force-dynamic";

// ind: código de quem indicou; o: de onde veio (google, instagram...). Seguem por todos os passos.
type Q = { s?: string | string[]; servico?: string; prof?: string; dia?: string; hora?: string; p?: string; remarcar?: string; ind?: string; o?: string };

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const db = clienteAdmin();
  const { data } = db ? await db.from("saloes").select("nome, descricao").eq("slug", slug).maybeSingle() : { data: null };
  return { title: data ? `${data.nome} · agende online` : "Agendar", description: data?.descricao ?? undefined };
}

/**
 * Link público de agendamento: sem app, sem cadastro, sem senha. Cada passo é um link, funciona em qualquer celular.
 * Dá para escolher mais de um serviço (feitos em sequência pelo mesmo profissional) e, com ?remarcar=<token>, trocar o horário.
 */
export default async function AgendarOnline({ params, searchParams }: { params: Promise<{ slug: string }>; searchParams: Promise<Q> }) {
  const { slug } = await params;
  const q = await searchParams;
  if (q.ind && !/^[A-Z2-9]{6}$/.test(q.ind)) q.ind = undefined;
  if (q.o && !/^[a-z]{2,12}$/.test(q.o)) q.o = undefined;
  const db = clienteAdmin();
  if (!db) return <Casca nome="Agendamento"><p>Agendamento indisponível no momento.</p></Casca>;
  const { data: salao } = await db.from("saloes").select("id, nome, fuso, abre, fecha, dias_semana, endereco, telefone, agendamento_online, politica_cancelamento, cancelamento_horas, antecedencia_min_horas, antecedencia_max_dias, descricao, instagram, vitrine_ativa, taxa_falta_centavos, indicacao_credito_centavos").eq("slug", slug).maybeSingle();
  if (!salao) notFound();
  if (!salao.agendamento_online) return <Casca nome={salao.nome}><p>O agendamento online está desligado. Fale com o salão{salao.telefone ? ` pelo ${salao.telefone}` : ""}.</p></Casca>;

  // Remarcação: os serviços são os do horário que ela já tem.
  const token = q.remarcar && /^[0-9a-f-]{36}$/.test(q.remarcar) ? q.remarcar : null;
  const atual = token ? ((await db.rpc("horario_publico", { p_token: token })).data as { servico_ids: string[] | null; status: string; inicio: string; servico: string; varios_profissionais: boolean } | null) : null;
  if (token && (!atual || !["agendado", "confirmado"].includes(atual.status) || atual.varios_profissionais || !atual.servico_ids?.length)) return <Casca nome={salao.nome}><p>Esse horário não pode mais ser remarcado pelo link. Fale com o salão{salao.telefone ? ` pelo ${salao.telefone}` : ""}.</p></Casca>;

  // Remarcando, o horário que ela já tem não conta como ocupado (o banco solta o antigo ao mover).
  const proprio = token ? (await db.from("agendamentos").select("id").eq("token", token).maybeSingle()).data : null;
  const grupoAtual = proprio ? (((await db.rpc("do_grupo", { p_ag: proprio.id })).data ?? []) as { id: string; servico_id: string; variacao_id: string | null; status: string; inicio: string }[]) : [];
  const ignorar = grupoAtual.map((g) => g.id);
  const disp = await criarDisponibilidade(db, salao, new Date(), { soOnline: !token, ignorar });
  const promos = ((await db.from("promocoes").select("id, nome, tipo, percentual, dias_semana, hora_inicio, hora_fim, horas_antes, servico_ids, valida_ate, ativa").eq("salao_id", salao.id).eq("ativa", true)).data ?? []) as Promocao[];
  // Remarcando: os serviços (e tamanhos) que ela já tem.
  const pedidos = token ? grupoAtual.filter((g) => g.status === "agendado" || g.status === "confirmado").sort((a, b) => a.inicio.localeCompare(b.inicio)).map((g) => (g.variacao_id ? `${g.servico_id}~${g.variacao_id}` : g.servico_id)) : [...(Array.isArray(q.s) ? q.s : q.s ? [q.s] : []), ...(q.servico ? [q.servico] : [])];
  const srvs = (token ? pedidos : [...new Set(pedidos)]).map((id) => (token ? disp.porId.get(id) : disp.servicos.find((x) => x.id === id))).filter((x): x is NonNullable<typeof x> => !!x).slice(0, 4);
  const profEscolhido = q.prof === "qualquer" ? "qualquer" : disp.profissionais.find((p) => p.id === q.prof)?.id;
  const url = (extra: Partial<Q>) => {
    const u = new URLSearchParams();
    if (token) u.set("remarcar", token); else srvs.forEach((x) => u.append("s", x.id));
    const v = { prof: q.prof, dia: q.dia, ind: q.ind, o: q.o, ...extra };
    for (const [k, x] of Object.entries(v)) if (x) u.set(k, String(x));
    return `/s/${slug}?${u}`;
  };
  const nomeProf = (id?: string) => disp.profissionais.find((p) => p.id === id)?.nome;
  const politica = (salao.politica_cancelamento?.trim() || `Cancelamentos e remarcações até ${salao.cancelamento_horas} horas antes do horário. Depois disso, ou em caso de falta, o sinal não é devolvido.`)
    + (salao.taxa_falta_centavos > 0 ? ` Falta sem aviso: taxa de ${reais(salao.taxa_falta_centavos)} cobrada na próxima visita.` : "");
  const ids = srvs.map((x) => x.id);
  const nomes = srvs.map((x) => x.nome).join(" + ");
  const preco = srvs.reduce((t, x) => t + x.preco_centavos, 0);
  const sinal = srvs.reduce((t, x) => t + (x.preco_centavos ? Math.round(x.preco_centavos * x.sinal_percentual / 100) : 0), 0);
  const titulo = token ? `Remarcar: ${atual!.servico}` : undefined;
  /** Maior desconto entre os serviços escolhidos, começando naquele dia e hora. */
  const descontoEm = (dia: string, hora: string) => Math.max(0, ...srvs.map((x) => promocaoPara(promos, x.servico, zonedToUtc(dia, hora, salao.fuso), salao.fuso)?.percentual ?? 0));

  // Passo 1: serviços (um ou mais)
  if (srvs.length === 0) return (
    <Casca nome={salao.nome} endereco={salao.endereco} passo={1} topo={<Vitrine db={db} salao={salao} promos={promos} />}>
      {q.ind && salao.indicacao_credito_centavos > 0 && <p className="okmsg">Uma amiga indicou você. Que bom te receber!</p>}
      <h2>Quais serviços?</h2>
      {disp.servicos.length === 0 ? <p className="sec">Nenhum serviço disponível online.</p> : (
        <form method="get" action={`/s/${slug}`} className="stack">
          {q.ind && <input type="hidden" name="ind" value={q.ind} />}{q.o && <input type="hidden" name="o" value={q.o} />}
          <div className="pub-lista">
            {disp.servicos.map((x) => (
              <label key={x.id} className="pub-op pub-marca">
                <input type="checkbox" name="s" value={x.id} />
                <span><strong>{x.nome}</strong><span className="cap sec">{descreverFases(x.fases)}</span></span>
                <span className="pub-preco">{x.preco_centavos ? reais(x.preco_centavos) : ""}{x.sinal_percentual > 0 && x.preco_centavos > 0 && <span className="cap muted">sinal {reais(Math.round(x.preco_centavos * x.sinal_percentual / 100))}</span>}</span>
              </label>
            ))}
          </div>
          <p className="cap muted">Pode marcar mais de um: são feitos um depois do outro.</p>
          <button className="btn pub-btn" type="submit">Continuar</button>
        </form>
      )}
    </Casca>
  );

  // Passo 2: profissional (com a sugestão de complemento dos serviços escolhidos)
  const jaTem = new Set(srvs.map((x) => x.servico));
  const sugestoes = token ? [] : [...new Set(srvs.flatMap((x) => x.complementos))].filter((id) => !jaTem.has(id))
    .flatMap((id) => disp.servicos.filter((x) => x.servico === id)).slice(0, 4);
  const comMais = (id: string) => { const u = new URLSearchParams(); [...ids, id].forEach((x) => u.append("s", x)); if (q.ind) u.set("ind", q.ind); if (q.o) u.set("o", q.o); return `/s/${slug}?${u}`; };
  if (!profEscolhido) return (
    <Casca nome={salao.nome} endereco={salao.endereco} passo={2} voltar={token ? `/s/${slug}/h/${token}` : `/s/${slug}`} titulo={titulo}>
      <h2>Com quem?</h2>
      <p className="sec">{nomes}</p>
      {sugestoes.length > 0 && srvs.length < 4 && (
        <div className="pub-sugestao">
          <strong>Quer aproveitar e adicionar?</strong>
          <div className="pub-chips">{sugestoes.map((x) => <Link key={x.id} className="pub-chip" href={comMais(x.id)}>+ {x.nome}{x.preco_centavos ? ` · ${reais(x.preco_centavos)}` : ""}</Link>)}</div>
        </div>
      )}
      <div className="pub-lista">
        <Link className="pub-op" href={url({ prof: "qualquer", dia: undefined })}><strong>Primeiro horário livre</strong><span className="cap sec">qualquer profissional</span></Link>
        {disp.profissionais.map((p) => <Link key={p.id} className="pub-op" href={url({ prof: p.id, dia: undefined })}><strong>{p.nome}</strong></Link>)}
      </div>
    </Casca>
  );

  // Passo 3: dia
  if (!q.dia) {
    const dias = await disp.dias(ids, profEscolhido, 10);
    return (
      <Casca nome={salao.nome} endereco={salao.endereco} passo={3} voltar={url({ prof: undefined })} titulo={titulo}>
        <h2>Que dia?</h2>
        <p className="sec">{nomes} · {profEscolhido === "qualquer" ? "qualquer profissional" : nomeProf(profEscolhido)}</p>
        {dias.length === 0 ? <p>Não há horários livres nos próximos dias. Fale com o salão{salao.telefone ? ` pelo ${salao.telefone}` : ""}.</p> : (
          <div className="pub-chips">{dias.map((d) => <Link key={d} className="pub-chip" href={url({ dia: d })}>{dataLonga(d)}</Link>)}</div>
        )}
      </Casca>
    );
  }

  // Passo 4: horário
  const livres = await disp.horarios(q.dia, ids, profEscolhido);
  const escolhido = q.hora ? livres.find((h) => h.hora === q.hora && (!q.p || h.profissional === q.p)) : undefined;
  if (!escolhido) return (
    <Casca nome={salao.nome} endereco={salao.endereco} passo={4} voltar={url({ dia: undefined })} titulo={titulo}>
      <h2>Que horas?</h2>
      <p className="sec">{dataLonga(q.dia)}</p>
      {q.hora && <p className="err" role="alert">Esse horário não está mais livre. Escolha outro.</p>}
      {livres.length === 0 ? <p>Sem horários livres nesse dia.</p> : (
        <div className="pub-chips">{livres.map((h) => { const d = token ? 0 : descontoEm(q.dia!, h.hora); return (
          <Link key={h.hora} className={`pub-chip${d ? " promo" : ""}`} href={url({ hora: h.hora, p: h.profissional })}>{h.hora}{d > 0 && <span className="pub-desc">-{d}%</span>}</Link>
        ); })}</div>
      )}
    </Casca>
  );

  // Passo 5: confirmação (com o preço do profissional que vai atender)
  const inicioEscolhido = zonedToUtc(q.dia, escolhido.hora, salao.fuso);
  const precoCheio = srvs.reduce((t, x) => t + disp.precoDe(x.id, escolhido.profissional), 0);
  const precoFinal = srvs.reduce((t, x) => t + comDesconto(disp.precoDe(x.id, escolhido.profissional), promocaoPara(promos, x.servico, inicioEscolhido, salao.fuso)?.percentual ?? 0), 0);
  const promoNome = srvs.map((x) => promocaoPara(promos, x.servico, inicioEscolhido, salao.fuso)?.nome).find(Boolean);
  const sinalFinal = srvs.reduce((t, x) => t + Math.round(disp.precoDe(x.id, escolhido.profissional) * x.sinal_percentual / 100), 0);
  const resumo = (
    <div className="pub-resumo">
      <strong>{nomes}</strong>
      <span>{dataLonga(q.dia)}, às {escolhido.hora}</span>
      <span>com {nomeProf(escolhido.profissional)}</span>
      {!token && precoFinal > 0 && <span>{precoFinal < precoCheio && <s className="pub-de">{reais(precoCheio)}</s>} {reais(precoFinal)}{promoNome ? ` · ${promoNome}` : ""}{sinalFinal > 0 ? ` · sinal de ${reais(sinalFinal)} por Pix para garantir o horário` : ""}</span>}
    </div>
  );
  if (token) return (
    <Casca nome={salao.nome} endereco={salao.endereco} passo={5} voltar={url({ hora: undefined, p: undefined })} titulo={titulo}>
      <h2>Confirmar o novo horário</h2>
      {resumo}
      <p className="sm sec">O horário que você tem agora só é liberado quando o novo estiver garantido. O sinal pago continua valendo.</p>
      <AcaoForm action={remarcarOnline}>
        <input type="hidden" name="slug" value={slug} /><input type="hidden" name="token" value={token} />
        <input type="hidden" name="profissional" value={escolhido.profissional} /><input type="hidden" name="dia" value={q.dia} /><input type="hidden" name="hora" value={escolhido.hora} />
        <Enviar className="btn pub-btn">Trocar para este horário</Enviar>
      </AcaoForm>
    </Casca>
  );
  return (
    <Casca nome={salao.nome} endereco={salao.endereco} passo={5} voltar={url({ hora: undefined, p: undefined })}>
      <h2>Confirme seus dados</h2>
      {resumo}
      <AcaoForm action={agendarOnline}>
        <input type="hidden" name="slug" value={slug} />
        {q.ind && <input type="hidden" name="ind" value={q.ind} />}{q.o && <input type="hidden" name="o" value={q.o} />}
        {ids.map((id) => <input key={id} type="hidden" name="servicos" value={id} />)}
        <input type="hidden" name="profissional" value={escolhido.profissional} /><input type="hidden" name="dia" value={q.dia} /><input type="hidden" name="hora" value={escolhido.hora} />
        <div className="field"><label htmlFor="nome">Seu nome</label><input id="nome" name="nome" required minLength={2} maxLength={120} autoComplete="name" /></div>
        <div className="field"><label htmlFor="telefone">Celular com DDD (WhatsApp)</label><CampoTelefone id="telefone" name="telefone" required autoComplete="tel" /></div>
        <label className="pub-check"><input type="checkbox" name="contato" required />Aceito receber a confirmação e os lembretes deste horário pelo WhatsApp.</label>
        <div className="pub-politica"><strong>Política de cancelamento</strong><p>{politica}</p></div>
        <label className="pub-check"><input type="checkbox" name="politica" required />Li e aceito a política de cancelamento.</label>
        <Enviar className="btn pub-btn">{sinalFinal > 0 ? "Marcar e pagar o sinal" : "Marcar horário"}</Enviar>
      </AcaoForm>
    </Casca>
  );
}

function Casca({ nome, endereco, passo, voltar, titulo, topo, children }: { nome: string; endereco?: string | null; passo?: number; voltar?: string; titulo?: string; topo?: React.ReactNode; children: React.ReactNode }) {
  return (
    <main className="pub">
      <header className="pub-cab">
        <img src="/icone.png" alt="" width={40} height={40} />
        <div><h1>{nome}</h1>{endereco && <p className="cap sec">{endereco}</p>}</div>
      </header>
      {topo}
      {titulo && <p className="bd wt" style={{ justifySelf: "start" }}>{titulo}</p>}
      {passo && <div className="pub-passos" aria-label={`Passo ${passo} de 5`}>{[1, 2, 3, 4, 5].map((n) => <span key={n} className={n <= passo ? "on" : ""} />)}</div>}
      <section className="card stack">{children}</section>
      {voltar && <Link className="btn ghost" href={voltar}>← Voltar</Link>}
      <p className="cap muted pub-rodape">Agendamento pelo Belezando · sem app e sem senha</p>
    </main>
  );
}
