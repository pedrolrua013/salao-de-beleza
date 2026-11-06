import { test } from "node:test";
import assert from "node:assert/strict";
import { emitirNfse, faltaConfigurar, lerSituacao, montarNfse, type ConfigFiscal } from "./nfse.ts";

const cfg: ConfigFiscal = {
  cnpj: "12345678000199", razao_social: "Studio Bela", inscricao_municipal: "12345", codigo_municipio: "3548500", item_lista_servico: "06.01",
  codigo_tributario_municipio: null, aliquota: 2, simples_nacional: true, ambiente: "homologacao", token_emissor: "tok-123",
};

test("monta a nota com valor em reais, item sem ponto e CPF da cliente", () => {
  const n = montarNfse(cfg, 15050, "Escova e hidratação", { nome: "Maria", documento: "529.982.247-25", email: null }, new Date("2026-11-02T12:00:00Z"));
  assert.equal(n.servico.valor_servicos, 150.5);
  assert.equal(n.servico.item_lista_servico, "0601");
  assert.deepEqual(n.tomador, { cpf: "52998224725", razao_social: "Maria", email: undefined });
  assert.equal(n.prestador.cnpj, "12345678000199");
});

test("sem dados da cliente, a nota sai sem tomador", () => {
  assert.equal(montarNfse(cfg, 1000, "Corte", { nome: null, documento: null, email: null }).tomador, undefined);
});

test("lista o que falta configurar", () => {
  assert.deepEqual(faltaConfigurar({ ...cfg, token_emissor: null }), ["token do emissor"]);
  assert.deepEqual(faltaConfigurar(null), ["dados fiscais"]);
});

test("lê a situação devolvida pelo emissor", () => {
  const base = "https://homologacao.focusnfe.com.br";
  assert.deepEqual(lerSituacao({ status: "autorizado", numero: 42, codigo_verificacao: "AB12", url_danfse: "https://x/pdf", caminho_xml_nota_fiscal: "/arquivos/n.xml" }, base),
    { status: "autorizada", numero: "42", codigo_verificacao: "AB12", url_pdf: "https://x/pdf", url_xml: `${base}/arquivos/n.xml` });
  const ruim = lerSituacao({ status: "autorizado", url_danfse: "javascript:alert(1)", caminho_xml_nota_fiscal: "http://x/n.xml" }, base);
  assert.equal(ruim.url_pdf, undefined, "link que não é https não vira botão");
  assert.equal(ruim.url_xml, undefined);
  assert.deepEqual(lerSituacao({ status: "erro_autorizacao", erros: [{ mensagem: "CNPJ inválido" }] }, base), { status: "erro", mensagem: "CNPJ inválido" });
  assert.deepEqual(lerSituacao({ status: "processando_autorizacao" }, base), { status: "processando" });
});

test("envia para o ambiente certo com autenticação", async () => {
  let pedido: { url: string; init?: RequestInit } | null = null;
  const f = (async (url: string, init?: RequestInit) => { pedido = { url, init }; return new Response(JSON.stringify({ status: "processando_autorizacao" }), { status: 202 }); }) as typeof fetch;
  const r = await emitirNfse(cfg, "blz-1", {}, f);
  assert.equal(r.status, "processando");
  assert.equal(pedido!.url, "https://homologacao.focusnfe.com.br/v2/nfse?ref=blz-1");
  assert.equal((pedido!.init!.headers as Record<string, string>).Authorization, `Basic ${Buffer.from("tok-123:").toString("base64")}`);
});
