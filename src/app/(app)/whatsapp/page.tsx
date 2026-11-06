import Link from "next/link";
import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { exigirMembro } from "@/lib/auth";
import { clienteAdmin } from "@/lib/supabase/admin";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { desconectar, salvarConexao } from "./actions";
import { BOTOES_META, MODELOS_META } from "@/lib/whatsapp/lembretes";
import { MODELOS_AVISO } from "@/lib/whatsapp/avisos";
import { MODELO_EQUIPE } from "@/lib/whatsapp/avisos-equipe";

export const metadata = { title: "WhatsApp" };

export default async function Conexao() {
  const { membro, salao } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/conversas");
  const db = clienteAdmin();
  // O token nunca volta para a tela: só mostramos se existe.
  const { data: conta } = db ? await db.from("whatsapp_contas").select("phone_number_id, waba_id").eq("salao_id", salao.id).maybeSingle() : { data: null };
  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "seu-dominio";
  const webhook = `https://${host}/api/whatsapp`;
  return (
    <div className="stack-lg">
      <div className="row between"><div><Link href="/conversas" className="sm sec">← Conversas</Link><h1>Conexão com o WhatsApp</h1></div>
        {conta && <span className="bd ok">Conectado</span>}</div>
      {!db && <p className="err" role="alert">Falta configurar SUPABASE_SERVICE_ROLE_KEY no servidor. Sem ela o robô não funciona.</p>}
      <section className="card stack">
        <h2>Dados do número</h2>
        <p className="sec">Use um número do salão cadastrado na API oficial do WhatsApp (Meta). Um número em uso no aplicativo comum precisa ser migrado antes.</p>
        <AcaoForm action={salvarConexao}>
          <div className="grid2">
            <div className="field"><label htmlFor="phone_number_id">ID do número de telefone</label><input id="phone_number_id" name="phone_number_id" inputMode="numeric" defaultValue={conta?.phone_number_id ?? ""} required /></div>
            <div className="field"><label htmlFor="waba_id">ID da conta do WhatsApp Business (opcional)</label><input id="waba_id" name="waba_id" inputMode="numeric" defaultValue={conta?.waba_id ?? ""} /></div>
          </div>
          <div className="field"><label htmlFor="token">Token de acesso permanente</label>
            <input id="token" name="token" type="password" autoComplete="off" placeholder={conta ? "Já salvo. Deixe em branco para manter." : "Cole aqui"} />
            <span className="hint">Fica guardado só no servidor e nunca é exibido de novo.</span></div>
          <div><Enviar>Salvar conexão</Enviar></div>
        </AcaoForm>
      </section>
      <section className="card stack">
        <h2>Cadastre o webhook na Meta</h2>
        <ol className="sec" style={{ paddingLeft: 20, display: "grid", gap: 8 }}>
          <li>No painel do seu app na Meta, abra WhatsApp &gt; Configuração e clique em editar o webhook.</li>
          <li>URL de retorno de chamada: <code>{webhook}</code></li>
          <li>Token de verificação: o mesmo valor da variável <code>WHATSAPP_VERIFY_TOKEN</code> do servidor.</li>
          <li>Depois de verificar, assine o campo <code>messages</code>.</li>
        </ol>
      </section>
      <section className="card stack">
        <h2>Modelos dos lembretes</h2>
        <p className="sec">A Meta só deixa o salão iniciar uma conversa com um texto aprovado antes. Cadastre os três modelos abaixo em WhatsApp &gt; Modelos de mensagem, com categoria <strong>Utilidade</strong>, idioma <strong>Português (BR)</strong>, exatamente com este nome e este texto. A aprovação costuma levar de algumas horas a 2 dias.</p>
        {Object.values(MODELOS_META).map((m) => (
          <div key={m.nome} className="stack" style={{ gap: 6 }}>
            <p style={{ margin: 0, fontWeight: 600 }}><code>{m.nome}</code></p>
            <p className="modelo">{m.corpo}</p>
          </div>
        ))}
        <p className="sec" style={{ margin: 0 }}>Em cada modelo, adicione três botões de resposta rápida, nesta ordem: {BOTOES_META.map((b) => <strong key={b}>“{b}”</strong>).reduce((x, y) => <>{x}, {y}</>)}. Se a Meta pedir um rodapé, use: <em>Para não receber lembretes, responda PARAR</em>. Variáveis, na ordem: nome, salão, dia, hora, profissional.</p>
      </section>
      <section className="card stack">
        <h2>Modelos de retorno, avisos e campanhas</h2>
        <p className="sec">Cadastre também estes dois, sem botões (o link vai no texto). O de retorno é da categoria <strong>Marketing</strong>, que a Meta cobra mais caro (cerca de R$ 0,32 por mensagem): ele só sai se você ligar o retorno automático em Salão.</p>
        {[...Object.values(MODELOS_AVISO), MODELO_EQUIPE].map((m) => (
          <div key={m.nome} className="stack" style={{ gap: 6 }}>
            <p style={{ margin: 0, fontWeight: 600 }}><code>{m.nome}</code> <span className="bd mu">{m.categoria}</span></p>
            <p className="modelo">{m.corpo}</p>
          </div>
        ))}
        <p className="sec" style={{ margin: 0 }}>Variáveis do retorno: nome, dias desde a visita, serviço, salão, link. Da vaga: nome, serviço, salão, dia, hora, link. Da campanha: nome, mensagem, link. O da equipe (horário novo, remarcado ou cancelado) vai para o celular do profissional.</p>
      </section>
      {conta && (
        <form action={desconectar}><button className="btn ghost sm" type="submit">Desconectar este número</button></form>
      )}
    </div>
  );
}
