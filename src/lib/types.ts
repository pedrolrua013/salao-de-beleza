import type { Fase } from "@/lib/fases";
export type Papel = "admin" | "profissional" | "recepcao";
export type Status = "agendado" | "confirmado" | "em_atendimento" | "concluido" | "faltou" | "cancelado";

export type Salao = {
  id: string; nome: string; slug: string; cor_marca: string;
  telefone: string | null; endereco: string | null; mensagem: string | null;
  fuso: string; abre: string; fecha: string; dias_semana: number[];
  lembretes_ativos: boolean; lembrete_hora: string;
  taxa_debito: number; taxa_credito: number; taxa_credito_parcelado: number; taxa_pix: number;
  comissao_desconta_taxa: boolean; comissao_desconta_custo: boolean;
  guia_concluido_em?: string | null;
};
export type Membro = { user_id: string; salao_id: string; papel: Papel; nome: string; permissoes?: Record<string, unknown> | null };
export type Jornada = { dias_semana: number[] | null; entrada: string | null; saida: string | null; almoco_inicio: string | null; almoco_fim: string | null };
export type Cliente = {
  id: string; nome: string; telefone: string | null; email: string | null;
  nascimento: string | null; observacoes: string | null; consentimento_em?: string | null; criado_em: string;
  alergias?: string | null; tipo_cabelo?: string | null; preferencias?: string | null; origem?: string | null; consentimento_imagem_em?: string | null;
  vip?: boolean; bloqueada?: boolean; sempre_sinal?: boolean;
  cep?: string | null; logradouro?: string | null; numero?: string | null; complemento?: string | null; bairro?: string | null; cidade?: string | null; uf?: string | null;
};
export type Servico = { id: string; nome: string; duracao_min: number; fases: Fase[]; ativo: boolean };
export type Agendamento = {
  id: string; cliente_id: string; profissional_id: string; servico_id: string;
  inicio: string; fim: string; fases: Fase[]; status: Status; origem: "interno" | "whatsapp" | "online";
  variacao_id?: string | null; serie_id?: string | null; grupo_id?: string | null; intervalo_min?: number;
};
export type Bloqueio = { id: string; profissional_id: string; inicio: string; fim: string; motivo: string | null };

export const STATUS: Record<Status, { texto: string; classe: "ok" | "wt" | "no" | "br" | "mu"; icone: string }> = {
  agendado: { texto: "Sem confirmar", classe: "wt", icone: "clock" },
  confirmado: { texto: "Confirmado", classe: "ok", icone: "check" },
  em_atendimento: { texto: "Em atendimento", classe: "br", icone: "chat" },
  concluido: { texto: "Concluído", classe: "mu", icone: "check" },
  faltou: { texto: "Faltou", classe: "no", icone: "x" },
  cancelado: { texto: "Cancelado", classe: "no", icone: "x" },
};
