import QRCode from "qrcode";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Copiar } from "@/app/s/[slug]/h/[token]/copiar";
import { pode } from "@/lib/permissoes";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { AbasDivulgar } from "../abas";
import { apagarFotoVitrine, enviarFotoVitrine, salvarVitrine } from "../actions";

export const metadata = { title: "Página do salão" };

/** A página pública do salão: apresentação, fotos dos trabalhos e avaliações, com o botão de agendar. */
export default async function Vitrine() {
  const { supabase, membro, salao } = await exigirMembro();
  if (!pode(membro, "divulgar")) redirect("/hoje");
  const admin = membro.papel === "admin";
  const [{ data: s }, { data: fotos }] = await Promise.all([
    supabase.from("saloes").select("descricao, instagram, vitrine_ativa, slug").eq("id", salao.id).single(),
    supabase.from("vitrine_fotos").select("id, caminho, legenda, foto_cliente_id").order("criado_em", { ascending: false }),
  ]);
  const urls = (fotos ?? []).length ? (await supabase.storage.from("fotos").createSignedUrls((fotos ?? []).map((f) => f.caminho), 3600)).data ?? [] : [];
  const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "") ?? "";
  const link = `${site}/s/${s?.slug ?? salao.slug}`;
  // Cada lugar tem seu link (?o=...): a cliente nova que chega por ele fica com a origem certa no cadastro.
  const qr = await QRCode.toDataURL(`${link}?o=qr`, { margin: 1, width: 220 });
  const botao = `<a href="${link}?o=site" style="display:inline-block;padding:12px 22px;border-radius:999px;background:#5B4BDB;color:#fff;font:600 16px sans-serif;text-decoration:none">Agendar horário</a>`;
  return (
    <div className="stack-lg">
      {admin ? <AbasDivulgar atual="/divulgar/vitrine" /> : <h1>Página do salão</h1>}
      <section className="card stack">
        <div className="row between"><h2>Seu endereço na internet</h2><a className="btn ghost sm" href={link} target="_blank" rel="noopener">Abrir a página</a></div>
        <div className="pub-link"><code>{link}</code></div>
        <p className="cap muted" style={{ margin: 0 }}>Coloque esse link na bio do Instagram e no Google. A cliente vê as fotos, as avaliações e já marca o horário.</p>
      </section>
      <section className="card stack">
        <h2>Botão de agendar, QR Code e Google</h2>
        <div className="divulga-grade">
          <div className="stack" style={{ gap: 8 }}>
            <h3>QR Code para o balcão</h3>
            <img src={qr} alt="QR Code do agendamento" width={180} height={180} className="divulga-qr" />
            <Link className="btn sec sm" href="/divulgar/cartaz" target="_blank">Imprimir cartaz</Link>
          </div>
          <div className="stack" style={{ gap: 10 }}>
            <div className="stack" style={{ gap: 4 }}>
              <h3>Instagram</h3>
              <p className="sm sec" style={{ margin: 0 }}>Cole na bio e no botão “Reservar” do perfil comercial (Editar perfil → Botões de ação → Reservar → link).</p>
              <div className="pub-link"><code>{link}?o=instagram</code><Copiar texto={`${link}?o=instagram`} rotulo="Copiar" /></div>
            </div>
            <div className="stack" style={{ gap: 4 }}>
              <h3>Google (Busca e Maps)</h3>
              <p className="sm sec" style={{ margin: 0 }}>No Perfil da Empresa no Google: Editar perfil → Reservas (ou “Link de agendamento”) → cole o link. O botão “Agendar” aparece na busca e no Maps.</p>
              <div className="pub-link"><code>{link}?o=google</code><Copiar texto={`${link}?o=google`} rotulo="Copiar" /></div>
            </div>
            <div className="stack" style={{ gap: 4 }}>
              <h3>Site do salão</h3>
              <p className="sm sec" style={{ margin: 0 }}>Copie este código e cole no site, onde quiser o botão.</p>
              <div className="pub-link"><code>{botao}</code><Copiar texto={botao} rotulo="Copiar código" /></div>
            </div>
          </div>
        </div>
        <p className="cap muted" style={{ margin: 0 }}>Cliente nova que chega por cada link fica com a origem no cadastro (Instagram, Google…), e o Painel mostra de onde vêm as clientes.</p>
      </section>

      {admin && (
        <section className="card stack">
          <h2>Apresentação</h2>
          <AcaoForm action={salvarVitrine}>
            <div className="field"><label htmlFor="vd">Sobre o salão (até 600 caracteres)</label>
              <textarea id="vd" name="descricao" maxLength={600} defaultValue={s?.descricao ?? ""} style={{ minHeight: 90 }} placeholder="Ex.: Especialistas em loiros e cachos há 10 anos. Ambiente climatizado, café e estacionamento na porta." /></div>
            <div className="grid2">
              <div className="field"><label htmlFor="vi">Instagram</label><input id="vi" name="instagram" maxLength={60} defaultValue={s?.instagram ? `@${s.instagram}` : ""} placeholder="@seusalao" /></div>
            </div>
            <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}>
              <input type="checkbox" name="vitrine_ativa" defaultChecked={s?.vitrine_ativa ?? true} />Mostrar fotos e avaliações na página
            </label>
            <div><Enviar>Salvar</Enviar></div>
          </AcaoForm>
        </section>
      )}
      <section className="card stack">
        <div className="row between"><h2>Fotos dos trabalhos</h2><span className="cap muted">{(fotos ?? []).length} de 40</span></div>
        <AcaoForm action={enviarFotoVitrine} className="row vit-form">
          <input name="foto" type="file" accept="image/jpeg,image/png,image/webp" required aria-label="Foto" />
          <input name="legenda" maxLength={80} placeholder="Legenda (ex.: Loiro perolado)" aria-label="Legenda" />
          <Enviar className="btn sm">Pôr na vitrine</Enviar>
        </AcaoForm>
        <p className="cap muted" style={{ margin: 0 }}>Também dá para mandar uma foto “depois” direto da ficha da cliente, quando ela autorizou o uso de imagem.</p>
        {(fotos ?? []).length === 0 ? <p className="sm sec">Nenhuma foto ainda.</p> : (
          <div className="vit-grade">{(fotos ?? []).map((f, i) => (
            <figure key={f.id} className="vit-foto">
              {urls[i]?.signedUrl && <img src={urls[i].signedUrl} alt={f.legenda ?? "Trabalho do salão"} loading="lazy" />}
              <figcaption><span>{f.legenda ?? ""}</span>
                <form action={apagarFotoVitrine}><input type="hidden" name="id" value={f.id} /><button className="btn ghost sm" type="submit" aria-label={`Tirar ${f.legenda ?? "foto"} da vitrine`}>Tirar</button></form>
              </figcaption>
            </figure>
          ))}</div>
        )}
      </section>
    </div>
  );
}
