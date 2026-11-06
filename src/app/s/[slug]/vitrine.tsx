import type { SupabaseClient } from "@supabase/supabase-js";
import { descreverPromocao, type Promocao } from "@/lib/promocoes";
import { todasAsLinhas } from "@/lib/paginar";

type SalaoVitrine = { id: string; nome: string; endereco: string | null; telefone: string | null; abre: string; fecha: string; dias_semana: number[]; descricao: string | null; instagram: string | null; vitrine_ativa: boolean };

const I = ({ d }: { d: React.ReactNode }) => <svg className="vit-ic" viewBox="0 0 24 24" aria-hidden="true">{d}</svg>;
const RELOGIO = <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>;
const PINO = <><path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.800-7 11-7 11z" /><circle cx="12" cy="10" r="2.5" /></>;
const BALAO = <path d="M5 5h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-6l-4 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />;
const CAMERA = <><rect x="3" y="3" width="18" height="18" rx="5" /><circle cx="12" cy="12" r="4" /><path d="M17.5 6.500h.01" /></>;

const DIAS = ["", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];
const h = (x: string) => { const [hh, mm] = x.slice(0, 5).split(":"); return `${Number(hh)}h${mm === "00" ? "" : mm}`; };

/** "Seg a Sex" quando os dias são seguidos; senão a lista. */
function diasAbertos(d: number[]): string {
  const s = [...d].sort((a, b) => a - b);
  const seguidos = s.length > 2 && s.every((x, i) => i === 0 || x === s[i - 1] + 1);
  return seguidos ? `${DIAS[s[0]]} a ${DIAS[s[s.length - 1]]}` : s.map((x) => DIAS[x]).join(", ");
}

/** Topo da página pública: apresentação, promoções, fotos dos trabalhos e o que as clientes dizem. */
export async function Vitrine({ db, salao, promos }: { db: SupabaseClient; salao: SalaoVitrine; promos: Promocao[] }) {
  const umAno = new Date(Date.now() - 365 * 86_400_000).toISOString();
  const [{ data: fotos }, { data: notas }, { data: comentarios }] = salao.vitrine_ativa ? await Promise.all([
    db.from("vitrine_fotos").select("id, caminho, legenda").eq("salao_id", salao.id).order("criado_em", { ascending: false }).limit(12),
    todasAsLinhas<{ nota: number }>((de, ate) => db.from("avaliacoes").select("nota").eq("salao_id", salao.id).not("respondida_em", "is", null).gte("respondida_em", umAno).order("id").range(de, ate))
      .then((data) => ({ data }), () => ({ data: [] as { nota: number }[] })),
    db.from("avaliacoes").select("id, nota, comentario, respondida_em, clientes(nome)").eq("salao_id", salao.id).eq("publica", true).gte("nota", 7).order("respondida_em", { ascending: false }).limit(4),
  ]) : [{ data: [] }, { data: [] }, { data: [] }];
  const urls = (fotos ?? []).length ? (await db.storage.from("fotos").createSignedUrls((fotos ?? []).map((f) => f.caminho), 3600)).data ?? [] : [];
  const ns = (notas ?? []).map((n) => n.nota as number);
  const media = ns.length >= 3 ? ns.reduce((a, b) => a + b, 0) / ns.length : null;
  const tel = salao.telefone?.replace(/\D/g, "");
  const ativas = promos.filter((p) => p.ativa && (!p.valida_ate || p.valida_ate >= new Date().toISOString().slice(0, 10)));
  return (
    <section className="card stack vit">
      {salao.descricao && <p className="vit-sobre">{salao.descricao}</p>}
      <div className="vit-info">
        <span><I d={RELOGIO} />{diasAbertos(salao.dias_semana)}, {h(salao.abre)} às {h(salao.fecha)}</span>
        {salao.endereco && <a href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(salao.endereco)}`} target="_blank" rel="noopener"><I d={PINO} />{salao.endereco}</a>}
        {tel && <a href={`https://wa.me/55${tel}`} target="_blank" rel="noopener"><I d={BALAO} />WhatsApp</a>}
        {salao.instagram && <a href={`https://instagram.com/${salao.instagram}`} target="_blank" rel="noopener"><I d={CAMERA} />@{salao.instagram}</a>}
      </div>
      {media !== null && (
        <div className="vit-nota" aria-label={`Nota ${media.toFixed(1).replace(".", ",")} de 10`}>
          <strong>{media.toFixed(1).replace(".", ",")}</strong><span>de 10 · {ns.length} avaliações de clientes</span>
        </div>
      )}
      {ativas.length > 0 && (
        <div className="vit-promos">{ativas.map((p) => <span key={p.id} className="vit-promo"><strong>{p.nome}</strong> {descreverPromocao(p)}</span>)}</div>
      )}
      {(fotos ?? []).length > 0 && (
        <div className="vit-fotos">{(fotos ?? []).map((f, i) => urls[i]?.signedUrl && (
          <figure key={f.id}><img src={urls[i].signedUrl} alt={f.legenda ?? "Trabalho do salão"} loading="lazy" />{f.legenda && <figcaption>{f.legenda}</figcaption>}</figure>
        ))}</div>
      )}
      {(comentarios ?? []).length > 0 && (
        <div className="vit-coments">{(comentarios ?? []).map((c) => (
          <blockquote key={c.id}><p>“{c.comentario}”</p><cite>{((c.clientes as unknown as { nome: string } | null)?.nome ?? "Cliente").split(" ")[0]} · nota {c.nota}</cite></blockquote>
        ))}</div>
      )}
    </section>
  );
}
