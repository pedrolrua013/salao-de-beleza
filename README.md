# Belezando

Sistema de gestão para salões de beleza (nome provisório). Next.js 16 + Supabase (Postgres com isolamento por salão).
Nasceu do Clinicando (SaaS para clínicas odontológicas, mesma identidade visual). O plano está em `PLANO_MVP.md`; o estudo de mercado e a pesquisa de concorrentes, em `reports/`.

## O que já funciona

| Área | O que faz |
|---|---|
| Conta, salão e papéis | Cadastro, login, criação do salão com serviços de partida. Administrador, profissional e recepção, aplicados no banco (RLS) |
| Equipe e jornada | Convite por e-mail, ativar/desativar. Cada profissional tem dias, entrada, saída e almoço próprios |
| Agenda | Colunas por profissional ou lista, horários livres sugeridos ao marcar. Serviços com fases de trabalho e pausa: na pausa da química o profissional fica livre e a agenda aceita encaixe. Bloqueios de folga, férias e compromisso. O banco impede sobreposição de trabalho ou bloqueio do mesmo profissional |
| Link de agendamento | `/s/<salao>`: a cliente marca sem app e sem senha (serviço, profissional ou o primeiro livre, dia, horário), aceita a política de cancelamento (guardada com texto, IP e aparelho) e recebe um link para ver e cancelar dentro do prazo |
| Sinal via Pix | Percentual por serviço. Pix copia e cola gerado na chave do salão (confirmado pela recepção) ou Pix do Mercado Pago (confirmado pelo webhook). Não pago em 30 min, o horário é liberado; cancelado no prazo, vira crédito; entra sozinho na comanda |
| Comanda e caixa | Serviços (com assistente), produtos, gorjeta separada, descontos, pagamento dividido. Caixa com troco, sangria, vale, suprimento, resumo por forma de pagamento e fechamento com contado versus esperado. Ao fechar a comanda, sugere marcar o retorno |
| Comissão | Regras por serviço, profissional e assistente; taxa do cartão e custo de produto descontados só se o salão quiser e nunca para CLT; vales; pagamento do período que trava os valores; extrato linha a linha para o profissional |
| Salão Parceiro | Vínculo, CNPJ e contrato de cada profissional, alertas de pendência (sem CNPJ, sem homologação, vencendo) e relatório de comprovação de cota-parte para o contador |
| Ficha da cliente | Ficha técnica de química (fórmula por zona, gramas, oxidante, técnica, pausa, resultado, repetir fórmula), testes de alergia e mecha imutáveis, fotos antes/depois no Storage privado com aceite de imagem, alergias em destaque, tipo de cabelo, origem, total gasto e frequência, união de cadastros duplicados |
| Painel do dono | Faturamento, ticket médio e atendimentos comparados ao período anterior, ocupação da agenda, faltas, clientes que voltaram, retorno marcado ao sair, % de produto, por profissional, serviços que mais faturam e origem dos clientes novos |
| Clientes para chamar de volta | Quem passou do tempo de costume sem horário marcado, com atalho para o WhatsApp já com o link de agendamento |
| Retorno automático | Cada serviço tem o prazo de retorno; ligado, quem passou do prazo sem marcar recebe convite com o link (no máximo um por mês) |
| Lista de espera | Por serviço, dias, período e profissional; quando um horário que combina é cancelado, até três clientes recebem o aviso com o link no dia e hora |
| Estoque | Revenda (sai na venda) e uso interno em g/ml (sai pelo consumo de cada serviço ao fechar a comanda), entrada por embalagem, perda, contagem, alerta de reposição |
| Pacotes e clube | Venda de pacotes e clube mensal na comanda; sessão usada entra pelo valor proporcional, com comissão; saldo na ficha da cliente |
| Cashback | Percentual e validade configuráveis; crédito ao fechar a comanda e uso na próxima |
| Vários serviços num atendimento | Na agenda e no link: até 3 ou 4 serviços em sequência; um lembrete só, e confirmar, cancelar, sinal e remarcação valem para o atendimento todo |
| Remarcar pelo link | A cliente troca o horário sozinha; o antigo só é liberado se o novo couber |
| Ficha de primeira visita | Link que a cliente nova responde antes de vir (cabelo, química recente, alergias, gestação, medicamento, objetivo); vai para a ficha dela |
| Avaliação (NPS) | Pergunta de 0 a 10 no dia seguinte; nota alta é convidada ao Google, nota baixa vira alerta no painel |
| Vale-presente | Vendido na comanda, com código e vale para imprimir; usado como pagamento até acabar o saldo |
| Simulador de WhatsApp | Testa robô, lembretes e avisos sem conta na Meta (`docs/TESTE-WHATSAPP.md`) |
| Importar e exportar | Clientes por CSV (reconhece colunas de outros sistemas, não duplica celular). Exportação em CSV e backup completo em JSON a qualquer hora |
| WhatsApp | Conversas espelhadas, robô de agendamento por fluxo fixo (respeita pausa, jornada e bloqueios), lembretes na véspera e 3 h antes com Confirmo / Preciso remarcar / Cancelar, PARAR respeitado |
| App no celular | Pode ser adicionado à tela inicial (PWA) |
| Auditoria | Quem alterou o quê e quando em clientes, agenda, comandas, caixa, comissões, fichas e sinais, sem copiar o conteúdo |

## O que ainda não existe

NFS-e (depende de contratar um emissor), split de pagamento e cobrança recorrente do clube (dependem de um meio de pagamento), cadeira e lavatório como recurso da agenda, contrato de parceria gerado pelo sistema, IA no WhatsApp, Agendamento pelo Google.

Publicar na AWS com Cloudflare: veja `DEPLOY.md`.

## Como rodar

1. Crie um projeto no [Supabase](https://supabase.com).
2. Aplique o banco com `supabase db push` (as migrações em ordem). Pelo SQL Editor, cole e execute um arquivo de `supabase/migrations` por vez, em ordem: as migrações 0011 em diante usam valores novos de tipos criados nelas mesmas, e o Postgres só aceita usá-los depois de gravados.
3. Copie `.env.example` para `.env.local` e preencha as chaves (Project Settings > API).
4. Em Authentication > URL Configuration, informe o endereço do site. Se quiser entrar sem confirmar e-mail em desenvolvimento, desligue "Confirm email".
5. `npm install` e `npm run dev`, depois abra `http://localhost:3000`.

## Conectar o WhatsApp

1. Na Meta for Developers, crie um app com o produto WhatsApp e cadastre o número do salão na API oficial (a Meta pede verificação do negócio).
2. Preencha `META_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN` e `SUPABASE_SERVICE_ROLE_KEY` no servidor.
3. Entre no Belezando como administrador, abra Salão > WhatsApp e informe o ID do número e o token permanente.
4. Na Meta, cadastre o webhook com a URL e o token mostrados nessa tela e assine o campo `messages`.
5. Mande uma mensagem para o número: o menu do robô deve responder e a conversa aparece em Conversas.

Como funciona: a Meta chama `/api/whatsapp`, o servidor confere a assinatura, grava a mensagem (uma vez só, mesmo que a Meta reenvie) e o robô responde. Se a equipe responde ou o cliente pede atendente, o robô para naquela conversa. O robô só oferece horários livres, e o banco recusa qualquer horário fora do expediente, no passado ou em conflito.

## Lembretes de horário

Regras (todas no banco, testadas): só recebe quem tem telefone, aceite e não pediu PARAR. Só horários ainda "aguardando" geram lembrete; horário marcado pelo robô já nasce confirmado. Remarcar, confirmar ou cancelar na agenda refaz ou cancela o que ainda não saiu. No máximo 2 mensagens por horário, sem envio de madrugada, e lembrete atrasado demais (servidor fora do ar) é descartado em vez de sair na hora errada. Duas execuções ao mesmo tempo nunca enviam o mesmo lembrete.

Para ativar:
1. Em Salão > WhatsApp, copie os três modelos exibidos e cadastre-os na Meta (categoria Utilidade, português BR, mesmo nome e mesmo texto, três botões de resposta rápida). A aprovação leva de horas a 2 dias: faça isso primeiro.
2. Defina `CRON_SECRET` no servidor. Em produção, o EventBridge da AWS chama `/api/cron/lembretes` a cada 10 minutos com `Authorization: Bearer <CRON_SECRET>` (veja `DEPLOY.md`).
3. Em Salão, confira o horário do lembrete da véspera e se os lembretes estão ligados.

Sem resposta, o horário continua marcado e aparece em Hoje para a recepção ligar. Não há cancelamento automático.

## Agendamento online, sinal e fotos

1. Defina `NEXT_PUBLIC_SITE_URL` (endereço público do sistema). O link de cada salão é `<site>/s/<slug>` e aparece em Salão > Agendamento online.
2. Sinal pelo Pix da chave: em Salão > Agendamento online, informe chave, nome e cidade; em Catálogos, o percentual de sinal de cada serviço. A recepção confirma o Pix na agenda.
3. Sinal automático (opcional): cole o Access Token do Mercado Pago na mesma tela. O aviso de pagamento chega em `/api/pagamentos/mercadopago`, que confere o pagamento na API antes de confirmar. Implementado pela documentação pública e testado com respostas simuladas; falta testar com conta real.
4. O mesmo cron dos lembretes (`/api/cron/lembretes`) expira os sinais não pagos e libera o horário.
5. Fotos da ficha: a migração 0010 cria o balde privado `fotos` no Storage do Supabase com acesso só à pasta do próprio salão.

## Divulgar, avisos da equipe, nota fiscal e termos

1. Divulgar (menu, só administrador): mapa dos horários vazios das últimas 8 semanas, promoções de dia/horário fixo ou de última hora (aparecem no link e o desconto entra sozinho na comanda), campanhas no WhatsApp por etiqueta da cliente (no máximo uma por dia, só para quem aceitou e não pediu PARAR) e a página pública do salão (descrição, Instagram, fotos dos trabalhos e avaliações que a cliente deixou mostrar).
2. Cadastre na Meta também os modelos `belezando_campanha` (Marketing) e `belezando_equipe` (Utilidade) que aparecem em Salão > WhatsApp.
3. Avisos da equipe: em Equipe, informe o celular do profissional e ligue o aviso. Ele recebe no WhatsApp (e vê em Hoje) horário novo, remarcado ou cancelado na agenda dele.
4. Nota fiscal de serviço: cadastre o salão (com certificado A1) no painel da Focus NFe e preencha Salão > Nota fiscal com os dados do contador e o token. Comece em homologação. Para testar sem emissor, `NFSE_SIMULAR=1` (ignorado em produção).
5. Termos: em Salão > Termos, ajuste os textos prontos (química e uso de imagem) com o advogado do salão. Na ficha da cliente, gere o link: ela assina com o dedo no celular ou no tablet do salão.

## Vender mais, equipe e cliente

1. Salão > Fidelidade, indicação e vendas: níveis de fidelidade (bônus em cashback), crédito por indicação, taxa por falta, venda de vale e pacote pelo link (`/s/<slug>/comprar`), áreas da ficha de primeira visita (cabelo, unhas, cílios e sobrancelha, pele, depilação) e IA no WhatsApp.
2. IA no WhatsApp: defina `ANTHROPIC_API_KEY` no servidor e ligue em Salão. Ela só responde dúvidas com os dados do salão; marcar continua pelo menu. Até 20 perguntas por conversa por dia.
3. Cobrança pelo celular: na comanda aberta, "Cliente paga pelo celular" gera o link com Pix (Mercado Pago confirma sozinho; Pix na chave, a recepção confirma). Vale e pacote comprados pelo link viram uma comanda "Venda pelo link" para fechar no caixa.
4. Equipe: permissões sob medida para cada pessoa e metas do mês (aparecem em Hoje e no Painel). Estoque > Pedidos de compra sugere o que repor por fornecedor.

## Testes

- `npm test`: horários livres e fuso, fluxo do robô, assinatura e leitura do webhook, envio, lembretes e respostas a eles, remarcação, e o processamento de ponta a ponta com banco de mentira.
- `npm run test:db`: sobe um Postgres temporário e roda 563 verificações de isolamento entre salões, papéis, conflito de horário, tamanhos, recursos, antecedência, fila, promoções, campanhas, vitrine, avisos da equipe, nota fiscal, termos, endereço da cliente, primeiro acesso, auditoria, WhatsApp e lembretes (programação, envio sem duplicar, respostas, PARAR) e endurecimento de segurança. Precisa de Postgres 14+ instalado.
- `npm run typecheck` e `npm run build`.

**O que não foi testado:** o app rodando contra um Supabase de verdade (login, consultas pelo PostgREST, convite por e-mail) e a integração com a Meta de verdade (webhook real, envio real). A API da Meta foi implementada pela documentação e simulada nos testes. O banco, a lógica de horários, os tipos e o build passam, mas o primeiro uso real pode revelar ajustes.

## Acessibilidade

Revisão feita em 24/10/2026 contra WCAG 2.1 AA. Contraste de todos os pares de cores do sistema, no claro e no escuro, passa (texto 4,9:1 ou mais; bordas e anel de foco 3,3:1 ou mais). Corrigidos: botão de tema sem nome no celular, contadores sem texto para leitor de tela, ausência de "pular para o conteúdo", foco do campo de busca e do campo de mensagem sem contorno, botões repetidos sem o nome do cliente, e alvos de toque abaixo de 44 px em telas de toque. Ainda sem teste manual com leitor de tela (VoiceOver/NVDA) e sem revisão no celular de verdade.

## Segurança

Uma revisão de segurança (24/10/2026) gerou a migração `0004_endurecimento.sql` e ajustes no app: permissões por coluna (ninguém altera aceite, PARAR, slug ou fuso pela API), aceite de contato só pela função `registrar_aceite_contato` (auditada) ou pela caixa no cadastro do cliente, conexão do WhatsApp só depois que a Meta confirma o token para aquele número, teto de 3 horários futuros por cliente pelo robô, limite de 30 mensagens em 10 minutos por conversa, mensagem do cliente só dada como tratada depois de processada (a Meta reenvia em caso de erro), cabeçalhos de segurança com CSP, e funções sem acesso anônimo e com `search_path` fixo.

Riscos conhecidos e aceitos por ora:
- Se o servidor cair exatamente entre enviar um lembrete e registrar o envio, o lembrete pode sair de novo (no máximo 3 vezes, só em falha).
- A recepção lê todas as conversas do WhatsApp. Pode ser a regra desejada, mas confira contra a minimização da LGPD.
- O robô só limita abuso por conversa. Um atacante com muitos números ainda gera conversas novas; a proteção maior vem do Cloudflare e do aceite exigido antes de marcar.

## Decisões que precisam de você

- **Um usuário, um salão.** Um profissional que atende em dois salões precisaria de duas contas.
- **Nome do produto.** "Belezando" é provisório.

## WhatsApp: pontos de atenção

- **Janela de 24 horas.** A Meta só deixa responder em texto livre até 24 h depois da última mensagem do cliente. Depois disso, só com modelo de mensagem aprovado (necessário para lembretes). A tela avisa quando a janela fecha.
- **Token guardado no banco.** O token da Meta fica na tabela `whatsapp_contas`, que só a chave de serviço lê. Para produção, o ideal é migrar para o Supabase Vault.
- **Conversa é dado pessoal.** Todos os membros do salão leem as conversas (recepção atende o WhatsApp). Falta definir política de retenção e exclusão.
- **Duas mensagens ao mesmo tempo** do mesmo cliente podem se cruzar no estado do robô. É raro e só repete uma pergunta, mas não há trava.
- **Quem aparece na lista de profissionais** são os membros ativos com papel administrador ou profissional, igual à agenda.
- **Custo.** Mensagens que o salão inicia fora da janela de 24 h (os lembretes) são cobradas pela Meta por mensagem entregue. Confira a tabela de preços atual da Meta antes de repassar valor ao cliente.
- **Qualidade do número.** Muitos bloqueios ou denúncias baixam a qualidade do número e podem limitar os envios. Por isso o lembrete só vai para quem tem aceite e o PARAR é respeitado.
- **Lembrete só para horários marcados pela recepção.** Quem marca pelo robô já confirmou na hora e não recebe lembrete. Se quiser lembrar também esses clientes, é um ajuste simples (um lembrete sem pedido de confirmação).


## Usabilidade

O sistema precisa ser intuitivo: ver `docs/USABILIDADE.md` (requisito, regras de projeto e roteiro de teste com usuários). Primeiros passos na tela Hoje e página Ajuda por papel já estão no código.
