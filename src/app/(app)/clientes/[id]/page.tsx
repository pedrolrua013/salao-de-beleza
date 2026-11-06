import Link from "next/link";
import { GerarLink } from "@/components/gerar-link";
import { respostasDasAreas } from "@/lib/fichas";
import { gerarLinkArea, gerarLinkIndicacao, perdoarTaxa } from "./area-actions";
import { GerarTermo } from "./termos";
import { AcaoForm as FormEtiquetas, Enviar as SalvarEtiquetas } from "@/components/acao-form";
import { publicarFotoCliente, salvarEtiquetas } from "@/app/(app)/divulgar/actions";
import { modelosDoSalao, type ModeloTermo } from "@/lib/termos";
import { MarcacoesCliente } from "./marcacoes";
import { CampoData } from "@/components/campo-data";
import { Vazio } from "@/components/ilustracoes";
import { notFound } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { dataBR, dataCurta, hora, idade } from "@/lib/format";
import { reais } from "@/lib/dinheiro";
import { dataLocal } from "@/lib/slots";
import { type Agendamento, type Cliente } from "@/lib/types";
import { Selo } from "@/components/selo";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { FormCliente } from "../form";
import { enderecoEmLinha, formatarCep } from "@/lib/cep";
import { editarCliente } from "../actions";
import { aceiteImagem, apagarFoto, linkFicha, registrarTeste, salvarFicha, unirCadastros } from "./actions";
import { EnviarFoto } from "./enviar-foto";

export const metadata = { title: "Cliente" };

type Linha = { zona?: string; produto: string; gramas?: number; oxidante?: number; oxidante_gramas?: number };
type Ficha = { id: string; data: string; servico: string; tecnica: string | null; formula: Linha[]; pausa_min: number | null; resultado: string | null; observacoes: string | null; profissional_id: string | null };
type Teste = { id: string; tipo: "alergia" | "mecha"; produto: string; resultado: string; feito_em: string; observacoes: string | null };
const RESULT: Record<string, [string, string]> = { sem_reacao: ["Sem reação", "ok"], aprovado: ["Aprovado", "ok"], reacao: ["Teve reação", "no"], nao_recomendado: ["Não recomendado", "no"] };
const ORIGEM: Record<string, string> = { indicacao: "Indicação", instagram: "Instagram", google: "Google", whatsapp: "WhatsApp", passante: "Passou na frente", facebook: "Facebook", tiktok: "TikTok", outro: "Outro" };
const LINHAS = 6;

export default async function PerfilCliente({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ repetir?: string }> }) {
  const { id } = await params;
  const { repetir } = await searchParams;
  const { supabase, salao, membro } = await exigirMembro();
  const { data: p } = await supabase.from("clientes").select("*").eq("id", id).maybeSingle();
  if (!p) notFound();
  const c = p as Cliente;
  const [{ data: ags }, { data: srvs }, { data: fs }, { data: ts }, { data: fotos }, { data: cms }, { data: profs }, { data: outros }] = await Promise.all([
    supabase.from("agendamentos").select("*").eq("cliente_id", id).order("inicio", { ascending: false }).limit(50),
    supabase.from("servicos").select("id, nome"),
    supabase.from("fichas_tecnicas").select("*").eq("cliente_id", id).order("data", { ascending: false }).order("criado_em", { ascending: false }).limit(30),
    supabase.from("testes_cliente").select("*").eq("cliente_id", id).order("feito_em", { ascending: false }),
    supabase.from("fotos_cliente").select("id, momento, caminho, criado_em").eq("cliente_id", id).order("criado_em", { ascending: false }).limit(24),
    supabase.from("comandas").select("id, fechada_em, desconto_centavos, comanda_itens(tipo, preco_centavos, quantidade, desconto_centavos)").eq("cliente_id", id).eq("status", "fechada").order("fechada_em", { ascending: false }),
    supabase.from("membros").select("user_id, nome"),
    membro.papel !== "profissional" ? supabase.from("clientes").select("id, nome, telefone").neq("id", id).order("nome").limit(500) : Promise.resolve({ data: [] }),
  ]);
  const [{ data: termos }, { data: modelosProprios }, { data: naVitrine }] = await Promise.all([
    supabase.from("termos_assinados").select("id, titulo, tipo, criado_em, expira_em, assinado_em, nome_assinado").eq("cliente_id", id).order("criado_em", { ascending: false }).limit(20),
    supabase.from("termos_modelos").select("id, tipo, titulo, texto").order("titulo"),
    (fotos ?? []).length ? supabase.from("vitrine_fotos").select("foto_cliente_id").in("foto_cliente_id", (fotos ?? []).map((f) => f.id)) : Promise.resolve({ data: [] as { foto_cliente_id: string }[] }),
  ]);
  const modelos = modelosDoSalao((modelosProprios ?? []) as ModeloTermo[]);
  const ext = c as Cliente & { indicado_por?: string | null; codigo_indicacao?: string | null };
  const [{ data: fid }, { data: taxas }, { data: indicadora }, { count: indicadas }] = await Promise.all([
    supabase.rpc("fidelidade", { p_cliente: id }),
    supabase.rpc("taxas_pendentes", { p_cliente: id }),
    ext.indicado_por ? supabase.from("clientes").select("id, nome, telefone").eq("id", ext.indicado_por).maybeSingle() : Promise.resolve({ data: null }),
    supabase.from("clientes").select("id", { count: "exact", head: true }).eq("indicado_por", id),
  ]);
  const fidelidade = fid as { pontos: number; nivel: string | null; bonus: number; proximo: string | null; faltam: number | null } | null;
  const creditoIndicacao = (salao as unknown as { indicacao_credito_centavos?: number }).indicacao_credito_centavos ?? 0;
  const fotosNaVitrine = new Set((naVitrine ?? []).map((v) => v.foto_cliente_id as string));
  const etiquetas = (c as { etiquetas?: string[] }).etiquetas ?? [];
  const nomeServ = new Map((srvs ?? []).map((s) => [s.id, s.nome as string]));
  const nomeProf = new Map((profs ?? []).map((m) => [m.user_id, m.nome as string]));
  const agendamentos = (ags ?? []) as Agendamento[];
  const fichas = (fs ?? []) as Ficha[];
  const testes = (ts ?? []) as Teste[];
  const [{ data: pcs }, { data: cb }, { data: previas }] = await Promise.all([
    supabase.from("pacotes_cliente").select("id, nome, tipo, expira_em, estado, pacote_saldos(servico_id, total, usado)").eq("cliente_id", id).eq("estado", "ativo").gt("expira_em", new Date().toISOString()),
    supabase.rpc("saldo_cashback", { p_cliente: id }),
    supabase.from("fichas_previas").select("id, respondida_em, respostas, expira_em").eq("cliente_id", id).order("criado_em", { ascending: false }).limit(3),
  ]);
  const respondida = (previas ?? []).find((x) => x.respondida_em) as { respondida_em: string; respostas: Record<string, string> } | undefined;
  const pendente = (previas ?? []).find((x) => !x.respondida_em && Date.parse(x.expira_em) > Date.now());
  const pacotesAtivos = (pcs ?? []) as { id: string; nome: string; tipo: string; expira_em: string; pacote_saldos: { servico_id: string; total: number; usado: number }[] }[];
  const urls = (fotos ?? []).length ? (await supabase.storage.from("fotos").createSignedUrls((fotos ?? []).map((f) => f.caminho), 3600)).data ?? [] : [];

  // Resumo da cliente: quanto gasta, com que frequência vem e quando veio pela última vez.
  const gastos = (cms ?? []).map((x) => x.comanda_itens.filter((i) => i.tipo !== "gorjeta").reduce((s, i) => s + i.preco_centavos * i.quantidade - i.desconto_centavos, 0) - x.desconto_centavos);
  const total = gastos.reduce((s, v) => s + v, 0);
  const visitas = agendamentos.filter((a) => a.status === "concluido").map((a) => Date.parse(a.inicio)).sort((a, b) => a - b);
  const intervalo = visitas.length >= 2 ? Math.round((visitas.at(-1)! - visitas[0]) / (visitas.length - 1) / 86_400_000) : null;
  const ultima = visitas.at(-1);
  const diasSemVir = ultima ? Math.floor((Date.now() - ultima) / 86_400_000) : null;
  const proximo = agendamentos.filter((a) => Date.parse(a.inicio) > Date.now() && (a.status === "agendado" || a.status === "confirmado")).at(-1);
  const base = fichas.find((f) => f.id === repetir) ?? null;
  const linhas: Linha[] = [...(base?.formula ?? []), ...Array.from({ length: LINHAS }, () => ({ produto: "" }))].slice(0, LINHAS);
  const alergiaRecente = testes.find((t) => t.tipo === "alergia");
  const diasTeste = alergiaRecente ? Math.floor((Date.now() - Date.parse(alergiaRecente.feito_em)) / 86_400_000) : null;

  const faltasCliente = ((ags ?? []) as { status: string }[]).filter((a) => a.status === "faltou").length;
  return (
    <div className="stack-lg">
      <div className="row between">
        <div>
          <h1>{c.vip && <span className="ag-vip" title="Cliente VIP">★ </span>}{c.nome}</h1>
          <p className="sm sec">{[idade(c.nascimento) !== null ? `${idade(c.nascimento)} anos` : null, c.tipo_cabelo ? `cabelo ${c.tipo_cabelo}` : null, c.origem ? `veio por ${ORIGEM[c.origem]}` : null].filter(Boolean).join(" · ")}</p>
        </div>
        <Link className="btn" href={`/agenda?cliente=${c.id}#novo`}>Agendar</Link>
      </div>
      {enderecoEmLinha(c) && (
        <p className="sm sec end-linha">{enderecoEmLinha(c)}{c.cep ? ` · CEP ${formatarCep(c.cep)}` : ""}{" "}
          <a href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(enderecoEmLinha(c))}`} target="_blank" rel="noopener noreferrer">Abrir no mapa</a></p>
      )}
      {c.alergias && <div className="aviso" role="note"><strong>Alergias e sensibilidades:</strong> {c.alergias}</div>}
      {c.bloqueada && <div className="aviso" role="note"><strong>Bloqueada para marcar sozinha:</strong> pelo link e pelo WhatsApp ela é orientada a falar com o salão.</div>}
      <MarcacoesCliente id={c.id} vip={!!c.vip} bloqueada={!!c.bloqueada} sempreSinal={!!c.sempre_sinal} faltas={faltasCliente} />
      <FormEtiquetas action={salvarEtiquetas} className="row etiquetas-form">
        <input type="hidden" name="cliente_id" value={c.id} />
        <span className="cap sec">Etiquetas</span>
        {etiquetas.map((e) => <span key={e} className="chip">{e}</span>)}
        <input name="etiquetas" defaultValue={etiquetas.join(", ")} maxLength={330} placeholder="noiva, loira, vip (separe por vírgula)" aria-label="Etiquetas da cliente, separadas por vírgula" />
        <SalvarEtiquetas className="btn ghost sm">Salvar</SalvarEtiquetas>
      </FormEtiquetas>

      <div className="kpis">
        <div className="kpi"><span className="cap sec">Total gasto</span><strong>{reais(total)}</strong><span className="cap muted">{gastos.length} comandas</span></div>
        <div className="kpi"><span className="cap sec">Ticket médio</span><strong>{gastos.length ? reais(Math.round(total / gastos.length)) : "—"}</strong></div>
        <div className="kpi"><span className="cap sec">Vem a cada</span><strong>{intervalo ? `${intervalo} dias` : "—"}</strong><span className="cap muted">{visitas.length} visitas concluídas</span></div>
        <div className="kpi"><span className="cap sec">Última visita</span><strong>{diasSemVir === null ? "—" : diasSemVir === 0 ? "hoje" : `há ${diasSemVir} dias`}</strong>
          <span className="cap muted">{proximo ? `próxima em ${dataCurta(proximo.inicio, salao.fuso)}` : intervalo && diasSemVir !== null && diasSemVir > intervalo * 1.5 ? "passou do tempo de voltar" : "sem horário futuro"}</span></div>
      </div>

      {(pacotesAtivos.length > 0 || Number(cb) > 0) && (
        <section className="card stack">
          <h2>Pacotes e cashback</h2>
          {Number(cb) > 0 && <p><span className="bd ok">Cashback: {reais(Number(cb))}</span> <span className="cap muted">para usar na próxima comanda</span></p>}
          {pacotesAtivos.length > 0 && (
            <div className="list">{pacotesAtivos.map((pk) => (
              <div key={pk.id} className="item"><span><span className="t">{pk.nome}</span> <span className="sm sec">· vale até {dataCurta(pk.expira_em, salao.fuso)}</span></span>
                <span className="sm">{pk.pacote_saldos.map((sd) => `${nomeServ.get(sd.servico_id) ?? "Serviço"}: ${sd.total - sd.usado} de ${sd.total}`).join(" · ")}</span></div>
            ))}</div>
          )}
        </section>
      )}

      {((taxas ?? []) as { id: string; valor_centavos: number; falta_em: string }[]).length > 0 && (
        <div className="aviso" role="note"><strong>Taxa de falta pendente:</strong>{" "}
          {((taxas ?? []) as { id: string; valor_centavos: number; falta_em: string }[]).map((t) => (
            <span key={t.id} className="row" style={{ display: "inline-flex", gap: 6 }}>{reais(t.valor_centavos)} (faltou em {dataCurta(t.falta_em, salao.fuso)}). Entra na próxima comanda.
              {membro.papel !== "profissional" && <form action={perdoarTaxa}><input type="hidden" name="id" value={t.id} /><input type="hidden" name="cliente_id" value={c.id} /><button className="btn ghost sm" type="submit">Perdoar</button></form>}</span>
          ))}</div>
      )}
      <section className="card stack" id="area">
        <div className="row between"><h2>Área da cliente</h2>{fidelidade && <span className="bd br">{fidelidade.nivel ? `${fidelidade.nivel} · ${fidelidade.pontos} pontos` : `${fidelidade.pontos} pontos`}</span>}</div>
        <p className="sm sec">Um link só dela, sem senha: próximos horários (para remarcar sozinha), cashback, pacotes{fidelidade ? ", pontos" : ""}{creditoIndicacao > 0 ? " e o link para indicar amigas" : ""}.</p>
        {fidelidade?.proximo && <p className="cap muted" style={{ margin: 0 }}>Faltam {fidelidade.faltam} pontos para {fidelidade.proximo}.</p>}
        <GerarLink acao={gerarLinkArea} campos={{ cliente_id: c.id }} rotulo="Gerar link da área" telefone={c.telefone} />
        {creditoIndicacao > 0 && (
          <div className="stack" style={{ gap: 6 }}>
            <span className="cap" style={{ fontWeight: 500 }}>Indique uma amiga · ganha {reais(creditoIndicacao)} por amiga que vier{(indicadas ?? 0) > 0 ? ` · já indicou ${indicadas}` : ""}</span>
            <GerarLink acao={gerarLinkIndicacao} campos={{ cliente_id: c.id }} rotulo="Link de indicação dela" telefone={c.telefone} />
          </div>
        )}
        {indicadora && <p className="cap muted" style={{ margin: 0 }}>Veio por indicação de <Link href={`/clientes/${indicadora.id}`}>{indicadora.nome}</Link>.</p>}
      </section>

      <section className="card stack" id="termos">
        <div className="row between"><h2>Termos assinados</h2><span className="cap muted">química, uso de imagem e outros</span></div>
        {(termos ?? []).length === 0 ? <p className="sm sec">Nenhum termo ainda. Gere o link, e ela assina com o dedo no celular dela ou no tablet do salão.</p> : (
          <div className="list">{(termos ?? []).map((t) => (
            <div key={t.id} className="item">
              <span><span className="t">{t.titulo}</span> <span className="sm sec">· {t.assinado_em ? `assinado por ${t.nome_assinado} em ${dataCurta(t.assinado_em, salao.fuso)}` : Date.parse(t.expira_em) < Date.now() ? "link vencido sem assinatura" : `aguardando assinatura desde ${dataCurta(t.criado_em, salao.fuso)}`}</span></span>
              {t.assinado_em ? <Link className="btn ghost sm" href={`/clientes/${c.id}/termos/${t.id}`}>Ver termo</Link> : <span className="bd wt">pendente</span>}
            </div>
          ))}</div>
        )}
        <GerarTermo clienteId={c.id} modelos={modelos.map((m) => ({ id: m.id, titulo: m.titulo }))} />
      </section>

      <section className="card stack">
        <div className="row between"><h2>Ficha de primeira visita</h2>{respondida ? <span className="bd ok">respondida em {dataCurta(respondida.respondida_em, salao.fuso)}</span> : pendente ? <span className="bd wt">link enviado, aguardando</span> : null}</div>
        {respondida ? (
          <dl className="ficha-previa">
            {[["Cabelo", "tipo_cabelo"], ["Química recente", "quimica"], ["Quando", "quimica_quando"], ["Alergias", "alergias"], ["Reação a tintura", "reacao_tintura"], ["Couro sensível", "couro_sensivel"], ["Gestante ou amamentando", "gestante"], ["Medicamento", "medicamento"], ["Quer", "objetivo"], ["Conheceu o salão por", "origem_outro"]]
              .filter(([, k]) => respondida.respostas?.[k]).map(([t, k]) => <div key={k}><dt className="cap sec">{t}</dt><dd>{({ sim: "Sim", nao: "Não", ns: "Não sei" } as Record<string, string>)[respondida.respostas[k]] ?? respondida.respostas[k]}</dd></div>)}
            {respostasDasAreas(respondida.respostas).map((x) => <div key={x.pergunta}><dt className="cap sec">{x.area}: {x.pergunta}</dt><dd>{x.resposta}</dd></div>)}
          </dl>
        ) : <p className="sm sec">A cliente responde pelo celular antes de vir: tipo de cabelo, química recente, alergias, gestação e o que quer. As respostas entram na ficha dela. Quem marca pelo link já recebe.</p>}
        <AcaoForm action={linkFicha} className="row"><input type="hidden" name="cliente_id" value={c.id} /><input type="hidden" name="slug" value={salao.slug} /><Enviar className="btn sec sm">{respondida ? "Pedir de novo" : "Gerar link da ficha"}</Enviar></AcaoForm>
      </section>

      <section className="card stack" id="ficha">
        <div className="row between"><h2>Ficha técnica</h2><span className="cap muted">fórmula, técnica, pausa e resultado de cada química</span></div>
        {fichas.length === 0 ? <p className="sm sec">Nenhuma ficha ainda. Registre a fórmula para a cor sair igual na próxima vez, mesmo com outro profissional.</p> : (
          <div className="fichas">
            {fichas.map((f) => (
              <article key={f.id} className="ficha">
                <div className="row between"><strong>{f.servico}{f.tecnica ? ` · ${f.tecnica}` : ""}</strong><span className="cap sec">{dataBR(f.data)}{f.profissional_id ? ` · ${nomeProf.get(f.profissional_id) ?? ""}` : ""}</span></div>
                {f.formula.length > 0 && (
                  <table className="tab"><thead><tr><th>Zona</th><th>Produto / tom</th><th className="num">g</th><th className="num">Oxidante</th></tr></thead>
                    <tbody>{f.formula.map((l, i) => <tr key={i}><td>{l.zona ?? "—"}</td><td>{l.produto}</td><td className="num">{l.gramas ?? "—"}</td><td className="num">{l.oxidante ? `${l.oxidante} vol${l.oxidante_gramas ? ` · ${l.oxidante_gramas} g` : ""}` : "—"}</td></tr>)}</tbody></table>
                )}
                <p className="sm">{f.pausa_min ? `Pausa: ${f.pausa_min} min. ` : ""}{f.resultado ?? ""}</p>
                {f.observacoes && <p className="sm sec">{f.observacoes}</p>}
                <Link className="btn ghost sm" href={`/clientes/${c.id}?repetir=${f.id}#nova-ficha`}>Repetir esta fórmula</Link>
              </article>
            ))}
          </div>
        )}
        <details className="aj" id="nova-ficha" open={!!base}><summary>{base ? `Nova ficha a partir de ${dataBR(base.data)}` : "Nova ficha técnica"}</summary>
          <div className="aj-corpo">
            <AcaoForm action={salvarFicha}>
              <input type="hidden" name="cliente_id" value={c.id} />
              <div className="grid2">
                <div className="field"><label htmlFor="fs">Serviço</label><input id="fs" name="servico" required defaultValue={base?.servico ?? ""} placeholder="Coloração, Mechas, Progressiva…" /></div>
                <div className="field"><label htmlFor="ft">Técnica</label><input id="ft" name="tecnica" defaultValue={base?.tecnica ?? ""} placeholder="Retoque de raiz, babylights…" /></div>
                <div className="field"><label htmlFor="fd">Data</label><CampoData id="fd" name="data" defaultValue={dataLocal(new Date(), salao.fuso)} /></div>
                <div className="field"><label htmlFor="fp">Pausa (min)</label><input id="fp" name="pausa_min" type="number" min={0} max={240} defaultValue={base?.pausa_min ?? ""} /></div>
              </div>
              <div className="scroll">
                <table className="tab formula"><thead><tr><th>Zona</th><th>Produto / tom</th><th>Gramas</th><th>Oxidante (vol)</th><th>Oxidante (g)</th></tr></thead>
                  <tbody>{linhas.map((l, i) => (
                    <tr key={i}>
                      <td><input name={`zona_${i}`} defaultValue={l.zona ?? ""} placeholder={i === 0 ? "raiz" : ""} aria-label={`Zona da linha ${i + 1}`} /></td>
                      <td><input name={`produto_${i}`} defaultValue={l.produto} placeholder={i === 0 ? "Koleston 7.1" : ""} aria-label={`Produto da linha ${i + 1}`} /></td>
                      <td><input name={`gramas_${i}`} inputMode="decimal" defaultValue={l.gramas ?? ""} aria-label={`Gramas da linha ${i + 1}`} /></td>
                      <td><input name={`ox_${i}`} inputMode="numeric" defaultValue={l.oxidante ?? ""} placeholder={i === 0 ? "20" : ""} aria-label={`Volume do oxidante da linha ${i + 1}`} /></td>
                      <td><input name={`oxg_${i}`} inputMode="decimal" defaultValue={l.oxidante_gramas ?? ""} aria-label={`Gramas de oxidante da linha ${i + 1}`} /></td>
                    </tr>))}</tbody></table>
              </div>
              <div className="field"><label htmlFor="fr">Resultado</label><input id="fr" name="resultado" maxLength={1000} placeholder="Ex.: cobriu 100% dos brancos, tom ficou um pouco mais frio" /></div>
              <div className="field"><label htmlFor="fo">Observações</label><textarea id="fo" name="observacoes" maxLength={2000} style={{ minHeight: 60 }} /></div>
              <div><Enviar>Salvar ficha</Enviar></div>
            </AcaoForm>
          </div>
        </details>
      </section>

      <section className="card stack">
        <div className="row between"><h2>Testes de alergia e de mecha</h2>
          {diasTeste !== null && <span className={`bd ${diasTeste > 180 ? "wt" : "ok"}`}>{diasTeste > 180 ? `último teste de alergia há ${diasTeste} dias` : `alergia testada há ${diasTeste} dias`}</span>}</div>
        {testes.length > 0 && (
          <div className="list">
            {testes.map((t) => (
              <div key={t.id} className="item">
                <span><span className="t">{t.tipo === "alergia" ? "Alergia (toque)" : "Mecha"} · {t.produto}</span> <span className="sm sec">· {dataBR(t.feito_em)}{t.observacoes ? ` · ${t.observacoes}` : ""}</span></span>
                <span className={`bd ${RESULT[t.resultado][1]}`}>{RESULT[t.resultado][0]}</span>
              </div>
            ))}
          </div>
        )}
        <AcaoForm action={registrarTeste} className="row">
          <input type="hidden" name="cliente_id" value={c.id} />
          <div className="field"><label htmlFor="tt">Teste</label><select id="tt" name="tipo"><option value="alergia">Alergia (toque)</option><option value="mecha">Mecha</option></select></div>
          <div className="field" style={{ flex: 1, minWidth: 160 }}><label htmlFor="tp">Produto</label><input id="tp" name="produto" required maxLength={120} /></div>
          <div className="field"><label htmlFor="tr">Resultado</label><select id="tr" name="resultado"><option value="sem_reacao">Sem reação</option><option value="aprovado">Aprovado</option><option value="reacao">Teve reação</option><option value="nao_recomendado">Não recomendado</option></select></div>
          <div className="field" style={{ flex: 1, minWidth: 160 }}><label htmlFor="to">Observação</label><input id="to" name="observacoes" maxLength={500} /></div>
          <div style={{ alignSelf: "flex-end" }}><Enviar className="btn sec">Registrar teste</Enviar></div>
        </AcaoForm>
      </section>

      <section className="card stack">
        <div className="row between"><h2>Fotos</h2>
          <form action={aceiteImagem} className="row" style={{ gap: 8 }}>
            <input type="hidden" name="cliente_id" value={c.id} /><input type="hidden" name="aceita" value={c.consentimento_imagem_em ? "0" : "1"} />
            <span className={`bd ${c.consentimento_imagem_em ? "ok" : "mu"}`}>{c.consentimento_imagem_em ? "Autorizou uso no portfólio" : "Sem autorização de uso de imagem"}</span>
            <button className="btn ghost sm" type="submit">{c.consentimento_imagem_em ? "Retirar autorização" : "Registrar autorização"}</button>
          </form>
        </div>
        {/* Uma coluna para cada momento: o que ela quer, como chegou e como saiu. */}
        <div className="fotos-colunas">
          {([["referencia", "Referência", "O que ela quer", "Foto de referência"], ["antes", "Antes", "Como chegou", "Foto de antes"], ["depois", "Depois", "Como saiu", "Foto de depois"]] as const).map(([m, titulo, sub, rotulo]) => {
            const doMomento = (fotos ?? []).map((f, i) => ({ ...f, url: urls[i]?.signedUrl })).filter((f) => f.momento === m);
            return (
              <div key={m} className={`fotos-col ${m}`}>
                <div className="fotos-cab"><strong>{titulo}</strong><span className="cap">{sub}</span><span className="fotos-n">{doMomento.length}</span></div>
                {doMomento.length === 0 ? <p className="cap muted fotos-vazio">Nenhuma foto ainda.</p> : (
                  <div className="fotos">
                    {doMomento.map((f) => (
                      <figure key={f.id}>
                        {f.url ? <a href={f.url} target="_blank" rel="noreferrer" title="Abrir a foto inteira"><img src={f.url} alt={`${titulo}, ${dataBR(f.criado_em.slice(0, 10))}`} loading="lazy" /></a> : <div className="foto-vazia" />}
                        <figcaption className="cap"><span>{dataBR(f.criado_em.slice(0, 10))}</span>
                          {m === "depois" && c.consentimento_imagem_em && membro.papel !== "profissional" && (fotosNaVitrine.has(f.id)
                            ? <span className="bd ok">na vitrine</span>
                            : <form action={publicarFotoCliente}><input type="hidden" name="foto_id" value={f.id} /><input type="hidden" name="cliente_id" value={c.id} /><button className="btn ghost sm" type="submit" title="Mostrar na página do salão">Vitrine</button></form>)}
                          <form action={apagarFoto}><input type="hidden" name="id" value={f.id} /><input type="hidden" name="cliente_id" value={c.id} /><button className="btn ghost sm" type="submit" aria-label={`Apagar foto de ${titulo.toLowerCase()}`}>×</button></form></figcaption>
                      </figure>
                    ))}
                  </div>
                )}
                <EnviarFoto clienteId={c.id} momento={m} rotulo={rotulo} />
              </div>
            );
          })}
        </div>
        <p className="cap muted">As fotos ficam privadas, só para a equipe. Para postar no Instagram, registre antes a autorização de uso de imagem.</p>
      </section>

      <section className="card">
        <h2 style={{ marginBottom: 8 }}>Histórico de horários</h2>
        {agendamentos.length === 0 ? <Vazio tipo="agenda">Nenhum horário registrado.</Vazio> : (
          <div className="list">
            {agendamentos.map((a) => (
              <div key={a.id} className="item">
                <p className="t">{dataCurta(a.inicio, salao.fuso)} · {hora(a.inicio, salao.fuso)} · {nomeServ.get(a.servico_id) ?? "Serviço"} <span className="sm sec">· {nomeProf.get(a.profissional_id) ?? ""}</span></p>
                <Selo status={a.status} />
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="card stack"><h2>Dados</h2><FormCliente action={editarCliente} p={c} indicadora={indicadora ?? null} /></section>

      {(outros ?? []).length > 0 && (
        <details className="card aj"><summary>Esta cliente tem outro cadastro? Unir cadastros duplicados</summary>
          <div className="aj-corpo">
            <AcaoForm action={unirCadastros}>
              <input type="hidden" name="cliente_id" value={c.id} />
              <div className="field"><label htmlFor="ur">Cadastro duplicado (vai sumir e tudo dele vem para cá)</label>
                <select id="ur" name="remover" required defaultValue=""><option value="" disabled>Escolha</option>{(outros ?? []).map((o) => <option key={o.id} value={o.id}>{o.nome}{o.telefone ? ` · ${o.telefone}` : ""}</option>)}</select></div>
              <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", width: "fit-content" }}><input type="checkbox" name="confirmo" />Confirmo que é a mesma pessoa</label>
              <div><Enviar className="btn sec">Unir cadastros</Enviar></div>
            </AcaoForm>
          </div>
        </details>
      )}
    </div>
  );
}
