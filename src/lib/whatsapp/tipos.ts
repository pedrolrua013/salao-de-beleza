// Mensagens que o robô envia e recebe. Limites da API da Meta: botão até 20 caracteres, linha de lista até 24, 10 linhas.
export type Saida =
  | { tipo: "texto"; corpo: string }
  | { tipo: "botoes"; corpo: string; botoes: { id: string; titulo: string }[] }
  | { tipo: "lista"; corpo: string; botao: string; itens: { id: string; titulo: string; descricao?: string }[] };

/** Texto livre ou toque em botão/lista (id preenchido). */
export type Entrada = { texto: string; id?: string };

export type EstadoBot = {
  passo: string;
  em?: string;                // última interação (ISO); depois de 2 h sem resposta o fluxo recomeça
  erros?: number;             // respostas não entendidas em sequência
  aceite?: boolean;
  nome?: string;
  servico?: string;
  servicos?: string[];        // remarcação de atendimento com vários serviços (em sequência)
  profissional?: string;      // id, ou "qualquer"
  dia?: string;               // YYYY-MM-DD
  hora?: string;              // HH:MM
  profHora?: string;          // profissional que de fato atende naquele horário
  cancelar?: string;
  remarcar?: string;          // horário antigo: só é cancelado depois que o novo for confirmado
};

export type Opcao = { id: string; nome: string };
export type Horario = { hora: string; profissional: string };
export type ResultadoAgendar = "ok" | "indisponivel" | "limite" | "erro";
export type ResultadoRemarcar = "ok" | "indisponivel" | "equipe" | "erro";

export type Contexto = {
  agora: Date;
  salao: { nome: string; telefone: string | null; endereco: string | null; mensagem: string | null; fuso: string };
  cliente: { nome: string | null; consentiu: boolean };
  servicos: (Opcao & { duracao_min: number })[];
  profissionais: Opcao[];
  dias(servico: string | string[], profissional: string): Promise<string[]>;
  horarios(dia: string, servico: string | string[], profissional: string): Promise<Horario[]>;
  meusAgendamentos(): Promise<{ id: string; inicio: string; servico: string; profissional: string }[]>;
  agendar(a: { servico: string; profissional: string; inicio: Date; nome: string | null; aceite: boolean }): Promise<ResultadoAgendar>;
  cancelar(id: string): Promise<boolean>;
  /** Move o atendimento inteiro (todos os serviços) numa operação só: o antigo só sai se o novo couber. */
  remarcar(agendamento: string, inicio: Date, profissional: string): Promise<ResultadoRemarcar>;
  /** IA para dúvidas em texto livre (só quando o salão ligou). Devolve null se não souber ou falhar. */
  ia?(pergunta: string): Promise<string | null>;
};

export type Resultado = { estado: EstadoBot; saidas: Saida[]; humano?: boolean };
