import { AcaoForm, Enviar, type Acao } from "@/components/acao-form";
import { BuscaCliente } from "@/components/busca-cliente";
import type { Cliente } from "@/lib/types";
import { CampoTelefone } from "@/components/campo-telefone";
import { CampoData } from "@/components/campo-data";
import { CampoEndereco } from "@/components/campo-endereco";

export function FormCliente({ action, p, voltar, padrao, indicadora }: { action: Acao; p?: Cliente; voltar?: string | null; padrao?: { nome?: string; telefone?: string }; indicadora?: { id: string; nome: string; telefone: string | null } | null }) {
  return (
    <AcaoForm action={action}>
      {p && <input type="hidden" name="id" value={p.id} />}
      {voltar && <input type="hidden" name="voltar" value={voltar} />}
      <div className="grid2">
        <div className="field"><label htmlFor="nome">Nome completo</label><input id="nome" name="nome" required minLength={2} maxLength={120} defaultValue={p?.nome ?? padrao?.nome} autoFocus={!p} /></div>
        <div className="field"><label htmlFor="telefone">Telefone com DDD</label><CampoTelefone id="telefone" name="telefone" defaultValue={p?.telefone ?? padrao?.telefone} /></div>
        <div className="field"><label htmlFor="email">E-mail</label><input id="email" name="email" type="email" maxLength={200} defaultValue={p?.email ?? ""} /></div>
        <div className="field"><label htmlFor="nascimento">Nascimento</label><CampoData id="nascimento" name="nascimento" defaultValue={p?.nascimento} inicio="ano" max="hoje" /></div>
      </div>
      <div className="grid2">
        <div className="field"><label htmlFor="tipo_cabelo">Tipo de cabelo</label>
          <select id="tipo_cabelo" name="tipo_cabelo" defaultValue={p?.tipo_cabelo ?? ""}><option value="">Não informado</option><option value="liso">Liso</option><option value="ondulado">Ondulado</option><option value="cacheado">Cacheado</option><option value="crespo">Crespo</option></select></div>
        <div className="field"><label htmlFor="origem">Como conheceu o salão</label>
          <select id="origem" name="origem" defaultValue={p?.origem ?? ""}><option value="">Não informado</option><option value="indicacao">Indicação</option><option value="instagram">Instagram</option><option value="google">Google</option><option value="whatsapp">WhatsApp</option><option value="facebook">Facebook</option><option value="tiktok">TikTok</option><option value="passante">Passou na frente</option><option value="outro">Outro</option></select></div>
      </div>
      <div className="field"><label htmlFor="indicado_por">Indicada por (se veio por indicação de uma cliente)</label><BuscaCliente id="indicado_por" name="indicado_por" inicial={indicadora ?? null} avulso ariaLabel="Cliente que indicou" /></div>
      <CampoEndereco inicial={p} />
      <div className="field"><label htmlFor="alergias">Alergias e sensibilidades</label><input id="alergias" name="alergias" maxLength={500} defaultValue={p?.alergias ?? ""} placeholder="Ex.: amônia, couro cabeludo sensível" /></div>
      <div className="field"><label htmlFor="preferencias">Preferências</label><input id="preferencias" name="preferencias" maxLength={1000} defaultValue={p?.preferencias ?? ""} placeholder="Ex.: gosta de café, prefere não conversar, escova bem lisa" /></div>
      <div className="field"><label htmlFor="observacoes">Observações</label><textarea id="observacoes" name="observacoes" maxLength={2000} defaultValue={p?.observacoes ?? ""} style={{ minHeight: 80 }} /></div>
      {!p?.consentimento_em && (
        <label className="chip" style={{ display: "flex", gap: 8, alignItems: "center", cursor: "pointer", width: "fit-content" }}>
          <input type="checkbox" name="aceite_whatsapp" />O cliente autorizou receber lembretes e mensagens do salão por WhatsApp
        </label>
      )}
      {p?.consentimento_em && <p className="cap muted" style={{ margin: 0 }}>Autorizou contato por WhatsApp.</p>}
      <div><Enviar>{p ? "Salvar alterações" : voltar ? "Salvar e voltar" : "Salvar cliente"}</Enviar></div>
    </AcaoForm>
  );
}
