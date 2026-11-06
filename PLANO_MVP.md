# Plano do MVP — SaaS para salão de beleza

Base: Clinicando (Next.js 16 + Supabase + WhatsApp oficial). Fonte das decisões: `reports/Estudo ERP salão de beleza.md`.

## Decisões de negócio (sugestões do estudo, aprovadas)

| Tema | Decisão |
|---|---|
| Público-alvo | Salões de 3 a 15 profissionais. Plano de entrada barato para MEI/autônomo como funil |
| Escopo | Cabelo, unha e barbearia no mesmo produto. Estética fica no SaaS irmão |
| Preço | Faixas públicas por número de profissionais (inclusive acima de 3). Mensal sem fidelidade; anual com desconto e sem multa |
| WhatsApp | Número próprio do salão (Embedded Signup). Lembretes (utility) inclusos; campanhas de marketing em créditos |
| IA | Robô de fluxo fixo no MVP. IA como adicional pago depois |
| Pagamentos | Caixa agnóstico (registra qualquer maquininha, Pix ou dinheiro). Um provedor de Pix só para o sinal no MVP. Split automático na V3 |
| Salão Parceiro | MVP: cadastro do parceiro, cota por serviço, razão salão × repasse e relatório de comprovação. Contrato gerado só na V3, revisado por advogado |
| Aluguel de cadeira | Fora, até parecer jurídico |
| NFS-e | V2, via provedor de API de NFS-e |
| Marketplace | Não terá. Link próprio do salão |
| Migração | Gratuita, de planilha e da Trinks, com exportação completa garantida |
| Suporte | Humano pelo WhatsApp, inclusive sábado |

## O que fazer com o código do Clinicando

**Reaproveitar como está:** login, cadastro do negócio, equipe e convites, RLS por empresa, auditoria, conversas do WhatsApp, webhook, envio, motor de lembretes, tema claro/escuro e o design system inteiro.

**Remover do salão:** atendimento clínico, receitas, medicamentos.

**Adaptar:**
- Nomes: `clinicas` → `saloes`, `pacientes` → `clientes`. Cada SaaS da família usa os nomes do próprio nicho.
- Papéis: `admin`, `profissional`, `recepcao` continuam. Profissional passa a ver só a própria comissão.
- Textos do robô e dos modelos de lembrete para o tom de salão.

**A mudança mais delicada — agenda com pausa de química:**
Hoje `agendamentos` tem a trava `sem_conflito` (`exclude using gist`) que bloqueia o horário inteiro do profissional. No salão:
- `servicos` ganha fases: lista de blocos `{tipo: ativo|pausa, minutos}`. Ex.: coloração = 30 ativo + 40 pausa + 30 ativo.
- Nova tabela `agendamento_blocos` (um registro por fase). A trava de conflito do profissional vale só para blocos **ativos**; a cadeira/lavatório (recurso) fica ocupada em todos os blocos.
- `slots.ts` e o robô passam a enxergar os "buracos" da pausa e sugerir encaixes.
- Os testes de banco existentes (142 verificações) são a rede de segurança dessa mudança.

## Etapas de construção

Todas as etapas do MVP estão feitas no código (out/2026). Falta rodar com Supabase, Meta e Mercado Pago de verdade.

1. **Fundação** (feito): Clinicando copiado para `saas-salao`, entidades renomeadas, parte clínica removida, textos e ícone de salão.
2. **Agenda com pausa** (feito): serviços com fases, tabela `ocupacoes` como trava de conflito, encaixe na pausa, agenda em colunas por profissional, bloqueios e jornada. Cadeira e lavatório como recurso da agenda ficaram para a V2.
3. **Comanda e caixa** (feito): serviços com assistente, produtos, gorjeta separada, descontos, pagamento dividido; caixa com troco, sangria, vale, suprimento e fechamento contado × esperado; sugestão de marcar o retorno ao fechar.
4. **Comissão e Salão Parceiro** (feito): regras por serviço, profissional e assistente, taxa e custo de produto opcionais e travados para CLT, vales, pagamento do período, extrato linha a linha e relatório de cota-parte. Contrato gerado pelo sistema continua na V3.
5. **Ficha da cliente** (feito): ficha técnica de química com repetir fórmula, testes imutáveis, fotos com aceite de imagem, alergias em destaque, origem, resumo de gastos e frequência, união de cadastros duplicados.
6. **No-show e captação** (feito): link público sem app e sem senha, aceite da política registrado, sinal via Pix (chave do salão ou Mercado Pago), expiração automática, cancelamento pela cliente no prazo com crédito.
7. **Dono no controle** (feito): painel com comparação ao período anterior, ocupação, faltas, retorno, rebook e % de produto; clientes para chamar de volta; importação por CSV e exportação completa.

V2 já feita no código: retorno automático pelo WhatsApp, lista de espera, estoque (revenda e uso interno por serviço), pacotes, clube mensal e cashback.

Ainda faltam: NFS-e nacional, split e cobrança recorrente, vale-presente, NPS e avaliação no Google, cadeira e lavatório como recurso, contrato de parceria gerado, IA no WhatsApp.

## Antes ou junto da etapa 1

- Conversar com 10 a 20 donos e profissionais de salão sobre comissão, parceria e ficha técnica. O estudo não foi validado com ninguém do setor.
- Primeiro teste real do Clinicando com Supabase e Meta de verdade, porque o salão herda esse código ainda não testado em produção.
