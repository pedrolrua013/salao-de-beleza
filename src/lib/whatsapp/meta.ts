// Fala com a WhatsApp Cloud API da Meta: confere a assinatura do webhook, lê o que chega e envia mensagens.
import { createHmac, timingSafeEqual } from "node:crypto";
import type { Saida } from "./tipos.ts";

/** Confere o cabeçalho X-Hub-Signature-256 contra o corpo bruto. Sem segredo configurado, recusa tudo. */
export function assinaturaValida(corpoBruto: string, cabecalho: string | null, segredo: string | undefined): boolean {
  if (!segredo || !cabecalho?.startsWith("sha256=")) return false;
  const esperado = createHmac("sha256", segredo).update(corpoBruto, "utf8").digest();
  let recebido: Buffer;
  try { recebido = Buffer.from(cabecalho.slice(7), "hex"); } catch { return false; }
  return recebido.length === esperado.length && timingSafeEqual(recebido, esperado);
}

export type EventoEntrada = {
  phoneNumberId: string;
  waId: string;
  nome: string | null;
  msgId: string;
  tipo: string;              // texto, interativo, audio, imagem...
  texto: string;             // o que o cliente digitou, ou o título do que tocou
  id?: string;               // id do botão ou da linha da lista
  suportado: boolean;        // false para áudio, imagem, localização etc.
};

const TIPOS: Record<string, string> = { audio: "áudio", image: "imagem", video: "vídeo", document: "documento", sticker: "figurinha", location: "localização", contacts: "contato", reaction: "reação" };

/** Extrai as mensagens recebidas de um webhook. Ignora o que não for mensagem (status de entrega, etc.). */
export function lerWebhook(corpo: unknown): EventoEntrada[] {
  const saida: EventoEntrada[] = [];
  const entradas = (corpo as { entry?: unknown[] } | null)?.entry;
  if (!Array.isArray(entradas)) return saida;
  for (const en of entradas as { changes?: { field?: string; value?: any }[] }[]) {
    for (const ch of en.changes ?? []) {
      if (ch.field !== "messages" || !ch.value) continue;
      const v = ch.value;
      const phoneNumberId = String(v.metadata?.phone_number_id ?? "");
      if (!phoneNumberId) continue;
      const nomes = new Map<string, string>((v.contacts ?? []).map((c: any) => [String(c.wa_id), String(c.profile?.name ?? "")]));
      for (const m of v.messages ?? []) {
        const waId = String(m.from ?? ""), msgId = String(m.id ?? "");
        if (!/^\d{10,15}$/.test(waId) || !msgId) continue;
        const base = { phoneNumberId, waId, nome: nomes.get(waId) || null, msgId };
        if (m.type === "text") saida.push({ ...base, tipo: "texto", texto: String(m.text?.body ?? "").slice(0, 4000), suportado: true });
        else if (m.type === "interactive") {
          const r = m.interactive?.button_reply ?? m.interactive?.list_reply;
          if (r?.id) saida.push({ ...base, tipo: "interativo", texto: String(r.title ?? ""), id: String(r.id), suportado: true });
        } else if (m.type === "button" && m.button?.payload) saida.push({ ...base, tipo: "interativo", texto: String(m.button.text ?? ""), id: String(m.button.payload), suportado: true });
        else if (m.type !== "reaction") saida.push({ ...base, tipo: m.type ?? "outro", texto: `[${TIPOS[m.type] ?? "mensagem"}]`, suportado: false });
      }
    }
  }
  return saida;
}

const corta = (s: string, n: number) => (s.length <= n ? s : s.slice(0, n - 1) + "…");

/** Corpo do POST /messages para a Cloud API, já respeitando os limites de tamanho. */
export function montarEnvio(para: string, s: Saida): Record<string, unknown> {
  const base = { messaging_product: "whatsapp", recipient_type: "individual", to: para };
  if (s.tipo === "texto") return { ...base, type: "text", text: { body: corta(s.corpo, 4000), preview_url: false } };
  if (s.tipo === "botoes") {
    return { ...base, type: "interactive", interactive: { type: "button", body: { text: corta(s.corpo, 1024) },
      action: { buttons: s.botoes.slice(0, 3).map((b) => ({ type: "reply", reply: { id: b.id.slice(0, 256), title: corta(b.titulo, 20) } })) } } };
  }
  return { ...base, type: "interactive", interactive: { type: "list", body: { text: corta(s.corpo, 1024) },
    action: { button: corta(s.botao, 20), sections: [{ title: "Opções", rows: s.itens.slice(0, 10).map((i) => ({ id: i.id.slice(0, 200), title: corta(i.titulo, 24), ...(i.descricao ? { description: corta(i.descricao, 72) } : {}) })) }] } } };
}

/** Texto que fica salvo no histórico para uma mensagem enviada. */
export function textoParaHistorico(s: Saida): string {
  if (s.tipo === "texto") return s.corpo;
  if (s.tipo === "botoes") return `${s.corpo}\n[${s.botoes.map((b) => b.titulo).join(" | ")}]`;
  return `${s.corpo}\n[${s.itens.map((i) => i.titulo).join(" | ")}]`;
}

export type ContaMeta = { phone_number_id: string; token: string };
export type ResultadoEnvio = { ok: true; msgId: string } | { ok: false; erro: string; janelaFechada?: boolean; definitivo?: boolean };

// Erros que não adianta tentar de novo: modelo inexistente, parâmetros errados, número que não recebe.
const ERROS_DEFINITIVOS = new Set([100, 131026, 131030, 131051, 132000, 132001, 132005, 132007, 132012, 132015, 132016]);

/**
 * Modo simulado, para testar o robô, os lembretes e os avisos sem conta na Meta: nada sai para a internet, e as respostas
 * só aparecem na tela de Conversas. Nunca liga em produção, mesmo que a variável esteja definida por engano.
 */
export function simulando(env: Record<string, string | undefined> = process.env): boolean {
  return env.WHATSAPP_SIMULAR === "1" && env.NODE_ENV !== "production";
}

async function postar(conta: ContaMeta, corpo: Record<string, unknown>, f: typeof fetch): Promise<ResultadoEnvio> {
  if (simulando()) {
    console.log("[whatsapp:simulado] enviaria", JSON.stringify(corpo));
    return { ok: true, msgId: `sim.${crypto.randomUUID()}` };
  }
  const versao = process.env.WHATSAPP_API_VERSION || "v23.0";
  try {
    const r = await f(`https://graph.facebook.com/${versao}/${conta.phone_number_id}/messages`, {
      method: "POST",
      headers: { Authorization: `Bearer ${conta.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(corpo),
      signal: AbortSignal.timeout(10_000),
    });
    const j: any = await r.json().catch(() => ({}));
    if (r.ok && j.messages?.[0]?.id) return { ok: true, msgId: String(j.messages[0].id) };
    const codigo = Number(j.error?.code);
    // 131047: mais de 24 h desde a última mensagem do cliente. Só modelo aprovado passa.
    return { ok: false, erro: `Meta ${codigo || r.status}: ${String(j.error?.message ?? "falha ao enviar").slice(0, 200)}`, janelaFechada: codigo === 131047, definitivo: ERROS_DEFINITIVOS.has(codigo) };
  } catch (e) {
    return { ok: false, erro: `Falha de rede: ${e instanceof Error ? e.message : "desconhecida"}`.slice(0, 200) };
  }
}

export async function enviar(conta: ContaMeta, para: string, s: Saida, f: typeof fetch = fetch): Promise<ResultadoEnvio> {
  return postar(conta, montarEnvio(para, s), f);
}

export type Modelo = { nome: string; parametros: string[]; botoes: string[] };

/** Mensagem de modelo (template) aprovado pela Meta. Única forma de falar com o cliente fora da janela de 24 h. */
export function montarModelo(para: string, m: Modelo): Record<string, unknown> {
  return {
    messaging_product: "whatsapp", recipient_type: "individual", to: para, type: "template",
    template: {
      name: m.nome, language: { code: "pt_BR" },
      components: [
        { type: "body", parameters: m.parametros.map((t) => ({ type: "text", text: t.replace(/[\n\t]+/g, " ").slice(0, 200) })) },
        ...m.botoes.map((payload, index) => ({ type: "button", sub_type: "quick_reply", index: String(index), parameters: [{ type: "payload", payload: payload.slice(0, 256) }] })),
      ],
    },
  };
}

export async function enviarModelo(conta: ContaMeta, para: string, m: Modelo, f: typeof fetch = fetch): Promise<ResultadoEnvio> {
  return postar(conta, montarModelo(para, m), f);
}

/** Confere na Meta que o token realmente dá acesso a este número. Sem isso, qualquer um poderia "reivindicar" o número de outro salão. */
export async function validarConta(conta: ContaMeta, f: typeof fetch = fetch): Promise<{ ok: true } | { ok: false; erro: string }> {
  if (simulando()) return { ok: true };
  const versao = process.env.WHATSAPP_API_VERSION || "v23.0";
  try {
    const r = await f(`https://graph.facebook.com/${versao}/${encodeURIComponent(conta.phone_number_id)}?fields=id,display_phone_number`, {
      headers: { Authorization: `Bearer ${conta.token}` },
      signal: AbortSignal.timeout(10_000),
    });
    const j: any = await r.json().catch(() => ({}));
    if (r.ok && String(j.id) === conta.phone_number_id) return { ok: true };
    return { ok: false, erro: `Meta ${j.error?.code ?? r.status}` };
  } catch {
    return { ok: false, erro: "Sem resposta da Meta" };
  }
}
