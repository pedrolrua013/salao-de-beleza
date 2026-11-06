import Link from "next/link";
import { redirect } from "next/navigation";
import { exigirMembro } from "@/lib/auth";
import { AcaoForm, Enviar } from "@/components/acao-form";
import { simulandoNfse } from "@/lib/nfse";
import { salvarFiscal } from "./actions";

export const metadata = { title: "Nota fiscal" };

/** Dados para emitir a NFS-e. O token do emissor é guardado e nunca volta para a tela. */
export default async function NotaFiscal() {
  const { supabase, membro } = await exigirMembro();
  if (membro.papel !== "admin") redirect("/configuracoes");
  const { data: f } = await supabase.from("fiscal_salao").select("cnpj, razao_social, inscricao_municipal, codigo_municipio, item_lista_servico, codigo_tributario_municipio, aliquota, simples_nacional, ambiente, ativo").maybeSingle();
  const { data: temToken } = await supabase.rpc("fiscal_tem_token");
  return (
    <div className="stack-lg">
      <div className="row between"><h1>Nota fiscal de serviço</h1><Link className="btn ghost sm" href="/configuracoes">← Salão</Link></div>
      {simulandoNfse() && <div className="aviso" role="note">Modo de teste ligado (NFSE_SIMULAR=1): as notas são “autorizadas” na hora e nada vai para a prefeitura.</div>}
      <section className="card stack">
        <p className="sm sec">A nota sai pela Focus NFe, que atende a maioria das prefeituras. Antes, cadastre o salão no painel da Focus com o certificado digital A1 e copie o token da empresa para cá. Os códigos de serviço e a alíquota vêm do contador.</p>
        <AcaoForm action={salvarFiscal}>
          <div className="grid2">
            <div className="field"><label htmlFor="fc">CNPJ</label><input id="fc" name="cnpj" inputMode="numeric" maxLength={18} defaultValue={f?.cnpj ?? ""} placeholder="00.000.000/0000-00" /></div>
            <div className="field"><label htmlFor="fr">Razão social</label><input id="fr" name="razao_social" maxLength={150} defaultValue={f?.razao_social ?? ""} /></div>
            <div className="field"><label htmlFor="fi">Inscrição municipal</label><input id="fi" name="inscricao_municipal" maxLength={20} defaultValue={f?.inscricao_municipal ?? ""} /></div>
            <div className="field"><label htmlFor="fm">Código IBGE da cidade (7 números)</label><input id="fm" name="codigo_municipio" inputMode="numeric" maxLength={7} defaultValue={f?.codigo_municipio ?? ""} placeholder="Ex.: 3548500 (Santos)" /></div>
            <div className="field"><label htmlFor="fl">Item da lista de serviços</label><input id="fl" name="item_lista_servico" maxLength={5} defaultValue={f?.item_lista_servico ?? "06.01"} placeholder="06.01" />
              <span className="cap muted">06.01 = barbearia, cabeleireiros, manicure, pedicure e congêneres</span></div>
            <div className="field"><label htmlFor="ft">Código tributário do município (se a prefeitura pedir)</label><input id="ft" name="codigo_tributario_municipio" maxLength={20} defaultValue={f?.codigo_tributario_municipio ?? ""} /></div>
            <div className="field"><label htmlFor="fa">Alíquota do ISS (%)</label><input id="fa" name="aliquota" inputMode="decimal" maxLength={5} defaultValue={f?.aliquota !== undefined && f?.aliquota !== null ? String(f.aliquota).replace(".", ",") : ""} placeholder="Ex.: 2" /></div>
            <div className="field"><label htmlFor="fe">Ambiente</label>
              <select id="fe" name="ambiente" defaultValue={f?.ambiente ?? "homologacao"}><option value="homologacao">Teste (homologação): nota sem valor fiscal</option><option value="producao">Produção: nota de verdade</option></select></div>
            <div className="field"><label htmlFor="fk">Token da empresa na Focus NFe</label><input id="fk" name="token_emissor" type="password" autoComplete="off" maxLength={200} placeholder={temToken ? "•••••• guardado (deixe vazio para manter)" : "Cole o token aqui"} /></div>
          </div>
          <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}><input type="checkbox" name="simples_nacional" defaultChecked={f?.simples_nacional ?? true} />Optante pelo Simples Nacional (inclui MEI)</label>
          <label className="chip" style={{ display: "inline-flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}><input type="checkbox" name="ativo" defaultChecked={f?.ativo ?? false} />Emitir nota pelas comandas</label>
          <div><Enviar>Salvar</Enviar></div>
        </AcaoForm>
      </section>
    </div>
  );
}
