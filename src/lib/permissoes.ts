// Permissões sob medida (iguais às do banco, função pode): o administrador pode tudo; os outros seguem o que ele marcou
// e, sem marcação, o padrão do papel. O banco confere de novo o que importa (caixa, desconto, agenda dos outros, painel, divulgar, estoque).
import type { Papel } from "./types.ts";

export const PERMISSOES = {
  painel: "Ver painel e relatórios (faturamento)",
  divulgar: "Promoções, campanhas e página do salão",
  caixa: "Receber pagamento e fechar comanda",
  desconto: "Dar desconto na comanda",
  agenda_outros: "Marcar e mudar horários na agenda de outros profissionais",
  comissoes: "Ver comissões da equipe",
  estoque: "Estoque, fornecedores e pedidos de compra",
} as const;
export type Permissao = keyof typeof PERMISSOES;

const PADRAO: Record<Permissao, (p: Papel) => boolean> = {
  painel: () => false,
  divulgar: () => false,
  caixa: (p) => p === "recepcao",
  desconto: () => true,
  agenda_outros: () => true,
  comissoes: (p) => p === "recepcao",
  estoque: (p) => p === "recepcao",
};

export function pode(m: { papel: Papel; permissoes?: Record<string, unknown> | null }, chave: Permissao): boolean {
  if (m.papel === "admin") return true;
  const v = m.permissoes?.[chave];
  return typeof v === "boolean" ? v : PADRAO[chave](m.papel);
}

/** Lê os checkboxes do formulário da equipe: só grava o que difere do padrão do papel. */
export function lerPermissoes(papel: Papel, marcadas: string[]): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  for (const k of Object.keys(PERMISSOES) as Permissao[]) {
    const quer = marcadas.includes(k);
    if (quer !== PADRAO[k](papel)) out[k] = quer;
  }
  return out;
}
