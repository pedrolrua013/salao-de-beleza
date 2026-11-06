# Publicar o Belezando na AWS, com Cloudflare na frente

**Aviso:** o código roda em modo de produção e responde corretamente (testado localmente), mas a imagem Docker, o deploy na AWS e a configuração do Cloudflare ainda não foram executados de verdade. Siga este guia na primeira publicação e anote o que precisar de ajuste.

## Ordem recomendada: ambiente de teste primeiro

Monte tudo abaixo duas vezes, em sequência: primeiro **teste** (domínio `teste.seudominio.com.br`, projeto Supabase separado, dados fictícios), depois **produção**. Use nomes com sufixo (`belezando-teste`, `belezando`) para não misturar. O teste só vira produção quando o primeiro fluxo completo funcionar nele: criar salão, convidar equipe, cadastrar cliente, agendar, receber a confirmação pelo WhatsApp e concluir o atendimento.

Pré-requisito: **ter um domínio**. O certificado HTTPS do balanceador (ACM) e o Cloudflare exigem um. Sem HTTPS o login não grava o cookie de sessão em produção, então não adianta subir pelo endereço cru da AWS.

Atalho no Supabase: o arquivo `supabase/tudo.sql` junta as cinco migrações na ordem certa. Cole-o inteiro no SQL Editor de cada projeto.

Custo aproximado do ambiente de teste na AWS: o balanceador é o maior item fixo (algumas dezenas de dólares por mês junto com uma tarefa pequena no Fargate). Confira no AWS Pricing Calculator e desligue o serviço (desired count 0) quando não estiver testando. O WhatsApp pode ficar para depois: sem as variáveis da Meta o sistema funciona, só sem robô e sem lembretes.

## Visão geral

```
Cliente / Meta ──► Cloudflare (DNS, proteção, limite de requisições)
                        │  HTTPS, com cabeçalho secreto de origem
                        ▼
                 AWS sa-east-1 (São Paulo)
                 ALB ──► ECS Fargate (container do Belezando) ──► Supabase (Postgres + Auth)
                 EventBridge ──► chama /api/cron/lembretes a cada 10 min
                 Secrets Manager (segredos) · CloudWatch (logs) · ECR (imagens)
```

Publicação automática: GitHub Actions roda o CI, constrói a imagem, envia para o ECR e atualiza o serviço (`.github/workflows/ci.yml` e `deploy.yml`).

## 1. Banco: Supabase Pro

1. Crie o projeto no plano Pro, na região de São Paulo se estiver disponível.
2. Em SQL Editor, rode na ordem `0001_nucleo.sql`, `0002_whatsapp.sql`, `0003_lembretes.sql`, `0004_endurecimento.sql`, `0005_visibilidade_historico.sql` e `0006_ajustes_advisor.sql`.
3. Em Project Settings > API, copie a URL, a chave `anon` e a `service_role`.
4. Em Authentication > URL Configuration, coloque o endereço final do app (passo 6) em Site URL.
5. Em Authentication, configure um SMTP próprio (o e-mail padrão tem limite baixo).

## 2. Base da AWS (região sa-east-1)

Crie, nesta ordem:

1. **Conta e acesso.** Ative MFA no usuário raiz e use um usuário/papel administrativo para o resto. Ative o CloudTrail.
2. **ECR:** repositório privado `belezando`, com varredura de vulnerabilidades ao enviar e regra para manter só as últimas 20 imagens.
3. **Rede:** use a VPC padrão para começar. Crie dois grupos de segurança: `alb` (entrada 443) e `app` (entrada 3000 só vinda do `alb`).
4. **Segredos (Secrets Manager),** com os nomes usados em `infra/ecs-task-definition.json`: `belezando/SUPABASE_SERVICE_ROLE_KEY`, `belezando/NEXT_PUBLIC_SUPABASE_ANON_KEY`, `belezando/META_APP_SECRET`, `belezando/WHATSAPP_VERIFY_TOKEN`, `belezando/CRON_SECRET`. Gere os dois textos aleatórios com `openssl rand -hex 32`.
5. **Papéis IAM:**
   - `belezando-execucao`: política `AmazonECSTaskExecutionRolePolicy` mais leitura dos cinco segredos acima.
   - `belezando-tarefa`: vazio por enquanto (o app não chama serviços da AWS).
   - `belezando-deploy` (usado pelo GitHub): confiança no provedor OIDC do GitHub, restrita ao seu repositório e à branch `main`; permissões para enviar ao ECR, registrar a task definition, atualizar o serviço ECS e `iam:PassRole` nos dois papéis acima.
6. **CloudWatch:** grupo de logs `/ecs/belezando` com retenção de 30 dias. As mensagens de erro do app não carregam conteúdo de conversa, mas mantenha a retenção curta mesmo assim.

## 3. Cluster, serviço e balanceador

1. **ECS:** cluster `belezando` (Fargate). Registre a primeira versão de `infra/ecs-task-definition.json` trocando `CONTA` pelo número da conta e o endereço do Supabase.
2. **Certificado (ACM):** peça um certificado público para `app.seudominio.com.br`, validando por DNS (o registro é criado no Cloudflare, passo 5).
3. **ALB** público, com listener 443 usando o certificado. Grupo de destino do tipo IP, porta 3000, verificação de saúde em `/api/saude`.
4. **Regra do listener:** encaminhe para o grupo de destino **somente se** o cabeçalho `X-Origin-Secret` tiver o valor combinado com o Cloudflare (passo 5). Qualquer outra requisição recebe resposta fixa 403. Isso impede que alguém acesse o ALB direto, pulando a proteção.
5. **Serviço ECS** `belezando`: 1 tarefa para começar (2 quando houver clientes, em zonas diferentes), grupo de segurança `app`, ligado ao grupo de destino do ALB.
6. Nas variáveis do repositório do GitHub, preencha as listadas no topo de `deploy.yml`. Rode "Deploy" à mão uma vez.

## 4. Agendador dos lembretes (EventBridge)

1. Em EventBridge > Conexões, crie uma conexão do tipo chave de API: nome do cabeçalho `Authorization`, valor `Bearer <o mesmo CRON_SECRET>`.
2. Crie um destino de API: `GET https://app.seudominio.com.br/api/cron/lembretes`, usando a conexão.
3. Crie uma regra agendada `rate(10 minutes)` com esse destino.
4. Opcional: alarme no CloudWatch para falhas da regra.

Os lembretes toleram atraso: saem na primeira chamada depois da hora, e os atrasados demais são descartados.

## 5. Cloudflare

1. Adicione o domínio ao Cloudflare e aponte os servidores de nome no registro.br (ou onde o domínio estiver).
2. **DNS:** registro `app` do tipo CNAME apontando para o endereço do ALB, com o proxy ligado (nuvem laranja). Crie também o registro de validação do ACM, sem proxy.
3. **SSL/TLS:** modo **Full (strict)**; ligue "Always Use HTTPS" e HSTS.
4. **Regra de transformação de cabeçalho:** para `app.seudominio.com.br`, adicione à requisição o cabeçalho `X-Origin-Secret` com um valor aleatório (o mesmo da regra do ALB).
5. **Cache:** regra para ignorar o cache em todo o domínio (o app é dinâmico).
6. **Limite de requisições:** uma regra para `/api/whatsapp` com teto generoso por IP, e proteção semelhante em `/entrar` e `/cadastro` contra tentativa de senha. No plano gratuito o número de regras é limitado, então priorize essas.
7. **Bot Fight Mode:** até onde sei, no plano gratuito ele não permite exceção por caminho e pode bloquear a Meta e o EventBridge. Deixe desligado: o webhook já confere a assinatura e o agendador usa segredo.
8. Ligue as regras gerenciadas de segurança (WAF) disponíveis no seu plano.
9. **IP real (obrigatório):** a tarefa do ECS já define `IP_CABECALHO=cf-connecting-ip`. Não remova: o Cloudflare reescreve esse cabeçalho com o IP de quem acessa, enquanto `X-Real-IP` e `X-Forwarded-For` podem ser inventados pela pessoa. Sem isso, os limites de tentativa (login, cadastro, agendamento online) e o IP guardado no aceite da política e nos termos assinados ficam falsificáveis. Na Vercel, deixe `IP_CABECALHO` vazio.

## 6. Meta (WhatsApp) e primeiro acesso

1. Webhook na Meta: `https://app.seudominio.com.br/api/whatsapp`, com o token `WHATSAPP_VERIFY_TOKEN`. Assine o campo `messages`.
2. Cadastre os três modelos de mensagem dos lembretes (textos em Salão > WhatsApp). Faça isso cedo: a aprovação leva de horas a 2 dias.
3. Crie sua conta e o salão em `https://app.seudominio.com.br`.

## 7. Operação

- **Monitoramento:** Sentry (ou equivalente) para erros do app, e um verificador de disponibilidade externo em `/api/saude`, com alerta no celular.
- **Backup:** o backup diário do Supabase Pro, mais uma cópia criptografada periódica num bucket S3 seu, com versionamento. Prontuário exige guarda de 20 anos.
- **Segredos:** troque as chaves a cada 6 a 12 meses e sempre que alguém sair da equipe.
- **LGPD:** contratos de operador com Supabase, AWS, Cloudflare e Meta; política de retenção das conversas; fluxo para atender pedidos de titular.

## Ainda por fazer (precisa de uma conta AWS para testar)

- Infraestrutura como código (Terraform) de tudo acima. Não incluí agora porque não consigo validar contra a AWS daqui, e IaC não testado atrapalha mais do que ajuda.
- Segunda zona de disponibilidade e escala automática, quando houver carga.
- Migrar o token da Meta da tabela `whatsapp_contas` para o Supabase Vault.
