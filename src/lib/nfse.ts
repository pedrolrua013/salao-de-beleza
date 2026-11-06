// Nota fiscal de serviço (NFS-e) pela Focus NFe, que fala com a prefeitura de cada cidade.
// Cada salão é cadastrado no painel da Focus com o certificado digital dele; o token da empresa fica em fiscal_salao.
// Em desenvolvimento, com NFSE_SIMULAR=1, nada sai daqui: a nota é "autorizada" na hora.

export type ConfigFiscal = {
  cnpj: string; razao_social: string | null; inscricao_municipal: string | null; codigo_municipio: string; item_lista_servico: string;
  codigo_tributario_municipio: string | null; aliquota: number; simples_nacional: boolean; ambiente: "homologacao" | "producao"; token_emissor: string | null;
};
export type Tomador = { nome: string | null; documento: string | null; email: string | null };
export type SituacaoNota = { status: "processando" | "autorizada" | "erro" | "cancelada"; numero?: string; codigo_verificacao?: string; url_pdf?: string; url_xml?: string; mensagem?: string };

const BASE = { homologacao: "https://homologacao.focusnfe.com.br", producao: "https://api.focusnfe.com.br" } as const;

export function simulandoNfse(env: Record<string, string | undefined> = process.env): boolean {
  return env.NFSE_SIMULAR === "1" && env.NODE_ENV !== "production";
}

/** O que falta para emitir (em português, para mostrar na tela). */
export function faltaConfigurar(c: Partial<ConfigFiscal> | null): string[] {
  if (!c) return ["dados fiscais"];
  return [
    !c.cnpj && "CNPJ", !c.codigo_municipio && "código da cidade (IBGE)", !c.item_lista_servico && "item da lista de serviços",
    (c.aliquota === null || c.aliquota === undefined) && "alíquota do ISS", !c.token_emissor && "token do emissor",
  ].filter((x): x is string => !!x);
}

/** Corpo da NFS-e no formato da Focus NFe (v2). Valores em reais com 2 casas. */
export function montarNfse(c: ConfigFiscal, valorCentavos: number, discriminacao: string, t: Tomador, agora = new Date()) {
  const doc = t.documento?.replace(/\D/g, "") || null;
  return {
    data_emissao: agora.toISOString(),
    natureza_operacao: "1",
    optante_simples_nacional: c.simples_nacional,
    prestador: { cnpj: c.cnpj, inscricao_municipal: c.inscricao_municipal ?? undefined, codigo_municipio: c.codigo_municipio },
    tomador: doc || t.nome ? {
      ...(doc?.length === 14 ? { cnpj: doc } : doc?.length === 11 ? { cpf: doc } : {}),
      razao_social: t.nome ?? undefined, email: t.email ?? undefined,
    } : undefined,
    servico: {
      valor_servicos: Number((valorCentavos / 100).toFixed(2)),
      aliquota: c.aliquota,
      iss_retido: false,
      item_lista_servico: c.item_lista_servico.replace(".", ""),
      codigo_tributario_municipio: c.codigo_tributario_municipio ?? undefined,
      discriminacao: discriminacao.slice(0, 2000),
    },
  };
}

/** Situação da Focus → a nossa. */
export function lerSituacao(r: Record<string, unknown>, base: string): SituacaoNota {
  const st = String(r.status ?? "");
  const erros = Array.isArray(r.erros) ? (r.erros as { mensagem?: string }[]).map((e) => e.mensagem).filter(Boolean).join("; ") : "";
  // Só endereço https vira link na tela (nada de "javascript:" vindo de fora).
  const abs = (u: unknown) => {
    if (typeof u !== "string" || !u) return undefined;
    const url = u.startsWith("/") ? `${base}${u}` : u;
    return /^https:\/\/[^\s"'<>]+$/.test(url) ? url : undefined;
  };
  if (st === "autorizado") return {
    status: "autorizada", numero: r.numero ? String(r.numero) : undefined, codigo_verificacao: r.codigo_verificacao ? String(r.codigo_verificacao) : undefined,
    url_pdf: abs(r.url_danfse) ?? abs(r.url), url_xml: abs(r.caminho_xml_nota_fiscal),
  };
  if (st === "cancelado") return { status: "cancelada" };
  if (st === "erro_autorizacao") return { status: "erro", mensagem: (erros || String(r.mensagem ?? "A prefeitura recusou a nota.")).slice(0, 1000) };
  return { status: "processando" };
}

type Fetch = typeof fetch;
const auth = (token: string) => ({ Authorization: `Basic ${Buffer.from(`${token}:`).toString("base64")}` });

export async function emitirNfse(c: ConfigFiscal, ref: string, corpo: unknown, f: Fetch = fetch): Promise<SituacaoNota> {
  if (simulandoNfse()) return { status: "autorizada", numero: String(Math.floor(Date.now() / 1000) % 100000), mensagem: "Simulação: nenhuma nota foi enviada à prefeitura." };
  const base = BASE[c.ambiente];
  const r = await f(`${base}/v2/nfse?ref=${encodeURIComponent(ref)}`, { method: "POST", headers: { ...auth(c.token_emissor ?? ""), "Content-Type": "application/json" }, body: JSON.stringify(corpo) });
  const j = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  if (!r.ok) return { status: "erro", mensagem: String(j.mensagem ?? `O emissor recusou (código ${r.status}).`).slice(0, 1000) };
  return lerSituacao(j, base);
}

export async function consultarNfse(c: ConfigFiscal, ref: string, f: Fetch = fetch): Promise<SituacaoNota> {
  const base = BASE[c.ambiente];
  const r = await f(`${base}/v2/nfse/${encodeURIComponent(ref)}`, { headers: auth(c.token_emissor ?? "") });
  const j = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  if (!r.ok) return { status: "processando", mensagem: String(j.mensagem ?? "") || undefined };
  return lerSituacao(j, base);
}

export async function cancelarNfse(c: ConfigFiscal, ref: string, justificativa: string, f: Fetch = fetch): Promise<{ ok: boolean; mensagem?: string }> {
  if (simulandoNfse()) return { ok: true };
  const r = await f(`${BASE[c.ambiente]}/v2/nfse/${encodeURIComponent(ref)}`, { method: "DELETE", headers: { ...auth(c.token_emissor ?? ""), "Content-Type": "application/json" }, body: JSON.stringify({ justificativa }) });
  const j = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  return r.ok && (j.status === "cancelado" || j.status === undefined) ? { ok: true } : { ok: false, mensagem: String(j.mensagem ?? "A prefeitura não aceitou o cancelamento.") };
}
