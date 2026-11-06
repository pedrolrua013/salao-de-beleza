# Mercado de salões de beleza no Brasil e práticas de captação/retenção (incl. automação via WhatsApp)

> Notas de pesquisa — out/2026. Muitas estatísticas operacionais (no-show, retenção, reativação) vêm de blogs de fornecedores de software, sem metodologia publicada; estão sinalizadas como tal. Números oficiais (Sebrae, Meta, ABF) estão marcados como mais confiáveis.

## 1. Tamanho do mercado (nº de salões, MEIs, receita, crescimento, redes vs. pequenos, digitalização)

### Takeaway
O Brasil tem ~935 mil CNPJs ativos no CNAE 9602-5/01 (cabeleireiros, manicure e pedicure) e ~380 mil no 9602-5/02 (estética), ou seja, ~1,1–1,3 milhão de negócios de beleza formalizados, dominados por MEIs: em 2025 abriram ~236 mil novos negócios de beleza (+18,5% vs 2024), 94% deles MEI. Redes/franquias de salão são uma fração pequena (dezenas a poucas centenas de unidades por marca) — o mercado é extremamente pulverizado, o que favorece um SaaS de baixo ticket voltado a pequenos salões e autônomos.

### Cited Findings
**Estoque de empresas (dados da Receita via agregadores, divergem conforme data de extração):**
- CNAE 9602-5/01: 937.536 empresas ativas — [Waxi](https://www.waxi.com.br/retrato-empresas-brasil/2026/atividades/beleza-e-servicos-pessoais); 934.307 — [Econodata](https://www.econodata.com.br/empresas/todo-brasil/cabeleireiros-e-outras-atividades-de-tratamento-de-beleza-s-9602501); ~948.838 — [TodoCNPJ](https://todocnpj.com/cnae/9602502-atividades-de-estetica-e-outros-servicos-de-cuidados-com-a-beleza).
- CNAE 9602-5/02 (estética e outros cuidados com a beleza): 377.223 (base Receita 10/2026) — [Consultadados](https://www.consultadados.com.br/setor/9602502); 382.717 (atualizado 03/07/2026) — [Índice CNPJ](https://indicecnpj.com.br/cnae/9602502-atividades-de-estetica-e-outros-servicos-de-cuidados-com-a-beleza?page=3).
- Bases comerciais que somam os dois CNAEs: 1.348.159 — [Disparo em Massa](https://disparoemassa.com.br/lista-de-saloes-de-beleza); 1.127.201 — [LeadJet](https://leadjet.com.br/lista-de-saloes-de-beleza/). A cifra "mais de 600 mil salões" repetida em blogs não tem fonte clara — [OndeAbrir](https://ondeabrir.com/blog/como-abrir-salao-de-beleza-localizacao) (conflita com os dados acima).

**Aberturas e perfil (Sebrae, fonte primária, divulgado em 12/01/2026):**
- ~236 mil novos negócios de beleza formalizados em 2025 (MEI+ME+EPP), crescimento de 18,5% vs 2024; média de 646/dia ou 27/hora — [Agência Sebrae](https://agenciasebrae.com.br/cultura-empreendedora/a-cada-hora-27-negocios-de-beleza-sao-abertos-no-pais-crescimento-foi-de-185-em-2025/).
- Distribuição: MEI 221.585 (94%), ME 12.424 (5%), EPP 1.672 (1%) — [Agência Sebrae](https://agenciasebrae.com.br/cultura-empreendedora/a-cada-hora-27-negocios-de-beleza-sao-abertos-no-pais-crescimento-foi-de-185-em-2025/).
- O profissional (cabeleireiro, manicure, barbeiro) pode ser MEI nos CNAEs 9602-5/01 e 9602-5/02; o "salão" como estrutura maior em geral não — [Irrivio](https://irrivio.com/blog/mei-cabeleireiro-barbeiro-manicure); [Conta4](https://conta4.com.br/salao-de-beleza-pode-ser-mei-veja-regras-essenciais-e-limites-em-2025/).

**Receita / tamanho do mercado (definições diferentes, não comparáveis):**
- Mercado de beleza (produtos) cresceu 6,8% em 2025, ~R$ 186,8 bi, segundo Euromonitor; Brasil é o 3º maior mercado mundial — [Folha do Litoral](https://folhadolitoral.com.br/editorias/economia/mercado-de-beleza-no-brasil-cresce-em-2025/).
- ~R$ 175 bi em 2025 apenas em vendas de produtos (exclui serviços de salões) — [Cosmetic Innovation](https://cosmeticinnovation.com.br/brasil-e-o-terceiro-maior-mercado-de-beleza-do-mundo-e-movimenta-r-175-bilhoes/).
- ABIHPEC publica página de tamanho de mercado de HPPC 2026 (valores citados por terceiros entre R$ 175 bi e ~R$ 200 bi) — [ABIHPEC](https://abihpec.org.br/tamanho-mercado-cosmeticos-brasil-2026/) (não verifiquei o número exato na página).
- Sebrae/IPC Maps: estimativa mais ampla de R$ 242,3 bi (+11,2%), incluindo higiene e cuidados pessoais em geral — via [Beauty Fair](https://negociosdebeleza.beautyfair.com.br/mercado/mercado-de-beleza-e-higiene-tem-movimentado-bilhoes-no-brasil-em-2025/) / [O Nortão](https://www.onortao.com.br/2026/07/setor-de-beleza-cresce-112-no-brasil.html).
- Franquias de Saúde, Beleza e Bem-Estar (ABF) faturaram R$ 74,3 bi em 2025, +14,6% — [Folha de Alagoas](https://folhadealagoas.com.br/2026/08/11/mercado-da-beleza-faturou-r-743-bilhoes-em-2025-aponta-pesquisa/); [Prensa de Babel](https://prensadebabel.com.br/324708-franquias-de-beleza-e-saude-crescem-146/). Inclui farmácias/cosméticos/estética, não só salões.

**Redes / franquias de salão:**
- ABF: segmento saúde, beleza e bem-estar com 600+ marcas e 36.495 operações no 1T2026 (+2,4% a/a) — [Central do Varejo](https://centraldovarejo.com.br/franquias-de-beleza-e-estetica-guia-de-investimento/).
- Jacques Janine: "primeira franquia de salões da América Latina", 60+ unidades (Brasil e EUA) — [Montar um Negócio](https://montarumnegocio.com/franquia-de-salao-de-beleza-7-boas-opcoes-para-abrir/).
- Werner Coiffeur: 56 unidades; Sobrancelhas Design 317; Emporium da Beleza 100; Fast Escova 88 (guia que soma 907 unidades em 30 marcas de salão, sem data clara) — [franquia-salao-de-beleza.com](https://www.franquia-salao-de-beleza.com/); Fast Escova aparece com 260+ unidades vendidas em outra fonte — [Montar um Negócio](https://montarumnegocio.com/franquia-de-salao-de-beleza-7-boas-opcoes-para-abrir/).

**Digitalização (uso de software):**
- Trinks se apresenta como "maior portal de agendamentos online do Brasil" — [Trinks](https://www.trinks.com/); um comparativo atribui à Trinks ~40 mil negócios cadastrados (sem fonte) — [agende-me](https://agende-me.com/comparacao-sistemas-agendamento/).
- Sistemas nacionais se diferenciam por WhatsApp como canal principal (não SMS), Pix como pagamento padrão e suporte em português — [agende-me](https://agende-me.com/comparacao-sistemas-agendamento/).

### Inferences
- Somando 9602-5/01 + 9602-5/02, o universo endereçável formal é ~1,1–1,3 milhão de CNPJs; a grande maioria é MEI/autônomo (94% das aberturas em 2025). Mesmo considerando que muitos CNPJs são profissionais individuais dentro de salões (salão-parceiro), o número de "estabelecimentos-salão" é provavelmente de algumas centenas de milhares.
- Redes de salão somam ordem de grandeza de ~1 mil unidades entre as principais marcas, ou seja, <1% dos estabelecimentos: o mercado é de salão de bairro e autônomo.
- Se Trinks (líder declarado) tem ~40 mil negócios, e somando concorrentes (Avec, Belasis, Salão99, AppBarber, etc.), a penetração de software dedicado provavelmente fica abaixo de 10–15% do universo formal — estimativa minha, não há dado público. A maioria ainda opera com agenda de papel + WhatsApp manual.
- Perfil MEI implica ticket de SaaS baixo (faixa de dezenas de reais/mês) e onboarding self-service via celular.

### Gaps
- Não encontrei pesquisa pública (Sebrae, IBGE, ABIHPEC) com % de salões que usam software de gestão/agendamento online; nem números auditados de base de Avec/Belasis/Trinks.
- Não há receita oficial específica de "serviços de salão" (IBGE PAS agrega outros serviços pessoais; não consultado diretamente). Números de "R$ 50 bi" ou "R$ 58 bi" para salões circulam sem fonte confiável.
- Dados de Beleza Natural, Walk Hair e outras redes não encontrados; contagens de unidades de franquias sem data de referência.
- Lei do Salão Parceiro (Lei 13.352/2016, que formaliza o profissional-parceiro MEI dentro do salão) é relevante para split de comissão no SaaS, mas não foi verificada nesta pesquisa.

## 2. No-show: taxas típicas e táticas eficazes

### Takeaway
Não existe estudo primário brasileiro sobre no-show em salões; fontes de mercado (fornecedores) citam 15–30% dos agendamentos sem confirmação. As táticas mais citadas e automatizáveis são: lembretes por WhatsApp em 24h e 2h antes com botão de confirmar/remarcar, sinal via Pix no ato do agendamento (10–30% do valor), política de cancelamento clara, e lista de espera para reaproveitar vagas.

### Cited Findings
- Taxa de no-show pode chegar a 30% dos agendamentos; caso relatado de queda de 30% para 4,2% com confirmação automática por WhatsApp (case de fornecedor) — [Cliente Preferido](https://clientepreferido.com.br/blog/como-reduzir-faltas-salao-beleza).
- ~20% de no-show em salões (sem base de dados) — [Otimizou](https://otimizou.com.br/blog/como-reduzir-faltas-salao-de-beleza.html).
- Salões sem confirmação automatizada perdem 15–20% da agenda — [Pandami](https://pandami.com.br/en/blog/gestao-de-salao-de-beleza).
- Atribuição ao Sebrae de 15–25% de receita potencial perdida por faltas em negócios por agendamento — [CresciQ](https://cresciq.com/blog/custo-invisivel-no-show-brasil); outro texto atribui ao Sebrae "até 30%" em salões — [Ordo AI](https://ordoai.app/blog/estrategias-para-reduzir-faltas-em-saloes-de-beleza). As duas atribuições não batem e não localizei o relatório original.
- Em estética, <5% de no-show é considerado saudável — [Scavi Company](https://scavicompany.com.br/blog/como-reduzir-faltas-e-no-show-na-estetica/); 25% em procedimentos não invasivos em clínicas (Contourline) — [OrganizaBot](https://blog.organizabot.com/2026/04/sinal-clinica-estetica.html).
- Estudo JMIR (2020): média global de 23% de no-show em serviços de saúde (referência comparativa) — citado por [CresciQ](https://cresciq.com/blog/custo-invisivel-no-show-brasil).
- Lembretes 24h + 2h antes reduzem no-show em até 40% — [Otimizou](https://otimizou.com.br/blog/como-reduzir-faltas-salao-de-beleza.html).
- Pré-pagamento parcial de 10–30% via Pix sugerido como sinal — [Otimizou](https://otimizou.com.br/blog/como-reduzir-faltas-salao-de-beleza.html).
- Cobrança de sinal associada a reduções de até 70% — [Ordo AI](https://ordoai.app/blog/estrategias-para-reduzir-faltas-em-saloes-de-beleza); 50–70% com sinal + lembrete WhatsApp — [OrganizaBot](https://blog.organizabot.com/2026/04/sinal-clinica-estetica.html).
- Exigir Pix no ato do agendamento reduz faltas "em até 50%" (alegação de fornecedor) — [Simples Agenda](https://www.simplesagenda.com.br/site/novo-sistema-salao-de-beleza.php).
- Outras táticas recomendadas (política de cancelamento, lista de espera, confirmação ativa) — [Afrodite](https://afrodite.online/blog/como-reduzir-faltas-no-salao-de-beleza-guia-completo); [AgendaIA](https://agendaiabr.com/blog/como-reduzir-faltas-no-salao-de-beleza).

### Inferences
- Funcionalidades prioritárias para o SaaS: (1) lembrete de utilidade via WhatsApp oficial (template utility, ~R$ 0,035/msg) 24h antes com botões "Confirmar / Remarcar / Cancelar", e um segundo 2–3h antes; (2) sinal via Pix (link/QR dinâmico) configurável por serviço (ex.: obrigatório para coloração/progressiva, opcional para manicure) e por cliente (obrigatório para quem já faltou); (3) política de cancelamento com prazo (ex.: 24h) exibida no agendamento e aceite registrado; (4) lista de espera automática que, ao cancelar, dispara oferta da vaga aos interessados; (5) "score de risco" por cliente (histórico de faltas) para exigir sinal ou permitir overbooking inteligente apenas em horários/profissionais com histórico alto de faltas.
- Custo de um lembrete (R$ 0,035) é irrisório frente ao ticket médio de um serviço; o ROI da confirmação automática é o argumento de venda mais fácil.
- Overbooking em salão é arriscado (serviço depende de profissional específico); melhor aplicá-lo só a serviços curtos e com score de risco.

### Gaps
- Nenhuma fonte primária (Sebrae, ABC, pesquisa acadêmica brasileira) com taxa de no-show em salões; todos os percentuais vêm de blogs comerciais sem metodologia.
- Sem dados sobre overbooking inteligente aplicado a salões no Brasil.
- Não verifiquei aspectos de CDC (Código de Defesa do Consumidor) sobre retenção de sinal em caso de falta.

## 3. Retenção: intervalos de retorno, reativação, aniversário, NPS, fidelidade, assinatura, avaliações

### Takeaway
A retenção em salão gira em torno de ciclos previsíveis por serviço (corte 4–8 semanas, cor 4–6 semanas a 3–4 meses, manicure semanal/quinzenal), o que permite automações de "lembrete de retorno" e "cliente sumida" (ex.: >60 dias ou 1,5× o intervalo habitual). Fidelidade varia de cartão "10 = 1 grátis" a níveis e cashback; o modelo de assinatura (clube de escova/manicure ilimitada) já existe no Brasil e cresce especialmente em barbearias.

### Cited Findings
- Clientes retornam a cada 4–8 semanas para corte/manutenção e a cada 3–4 meses para coloração/tratamento — [Rework](https://resources.rework.com/pt/libraries/beauty-center-growth/data-driven-decisions-salon-owners).
- Sugestão alternativa: lembrete de retorno 3–4 semanas após corte e 4–6 semanas após coloração — [alteg.io](https://alteg.io/pt/blog/receita-salao-18-sistemas-atrair-reter-clientes/).
- Medir retenção pelo intervalo esperado de cada serviço (não janelas fixas 30/60/90); salão saudável retém 60–70% dos clientes dentro do intervalo esperado; momento ideal de lembrete ≈ 1,5× o intervalo normal entre visitas — [Rework](https://resources.rework.com/pt/libraries/beauty-center-growth/data-driven-decisions-salon-owners).
- Reativação: identificar clientes sem visita há >60 dias e enviar WhatsApp; pode recuperar 10–20% dos inativos (estimativa de fornecedor) — [Cliente Preferido](https://clientepreferido.com.br/blog/como-fidelizar-clientes-salao-beleza).
- Pós-atendimento no dia seguinte perguntando se gostou; mensagem de aniversário com desconto — [alteg.io](https://alteg.io/pt/blog/receita-salao-18-sistemas-atrair-reter-clientes/).
- Programas de fidelidade: "a cada 10 serviços, 1 grátis" e níveis (Bronze → Diamante) com benefícios crescentes — [Pandami](https://pandami.com.br/en/blog/fidelizar-clientes-no-salao); [Marketek](https://marketek.digital/blog/fidelizar-clientes-salao-de-beleza/).
- Assinatura: Belle.Club (Instituto Embelleze) apontado como primeiro salão por assinatura do Brasil, com plano mensal de escova + manicure ilimitadas e plano premium com pedicure, limitado a ~3 atendimentos/semana conforme disponibilidade — [IstoÉ](https://istoe.com.br/salao-de-beleza-por-assinatura-e-a-nova-aposta-para-mulheres-modernas/).
- Clube em São Paulo a R$ 499/mês com visitas ilimitadas viralizou em 2022 (assinante ia quase todo dia — risco de prejuízo) — [Folha PE](https://www.folhape.com.br/economia/clube-de-beleza-viraliza-apos-assinante-contar-rotina-nas-redes/244259/); [A Gazeta](https://www.agazeta.com.br/hz/tv-e-famosos/mulher-da-prejuizo-em-salao-ao-frequentar-o-local-todos-os-dias-1022).
- Barbearias por assinatura em expansão; desafio é equilibrar preço, frequência de uso e capacidade — [O Hoje (set/2026)](https://ohoje.com/2026/08/31/barbearia-por-assinatura-cresce-e-muda-habitos-de-consumo-dos-homens/); [Diário do Nordeste](https://diariodonordeste.verdesmares.com.br/negocios/barbearias-por-assinatura-se-tornam-tendencia-e-garantem-seguranca-financeira-para-empreendedores-1.3719458).
- Salões com assinatura reportariam 35% menos churn; ponto de equilíbrio típico em 1,8 visitas/mês (dado atribuído à Mindbody, não brasileiro) — [Rework](https://resources.rework.com/pt/libraries/beauty-center-growth/membership-models-spas-salons).
- Exemplo de cobrança recorrente "Plano Escova Ilimitada" via link do Asaas (salões usam gateways de recorrência de terceiros) — [Asaas](https://www.asaas.com/c/m5lxkqgszle82ch0).

### Inferences
- Automação-chave: "intervalo de retorno" calculado por cliente×serviço a partir do histórico (com default por serviço), disparando lembrete de reagendamento (template utility ou marketing, conforme conteúdo) e, depois de 1,5–2× o intervalo, a régua "cliente sumida" (marketing, com oferta).
- Régua padrão sugerida: confirmação (D-1/H-2) → agradecimento + NPS/avaliação Google (D+1) → lembrete de retorno (intervalo do serviço) → reativação (>60 dias / 1,5×) → aniversário (mês/dia) → campanhas sazonais.
- Assinatura/clube é um diferencial forte para o SaaS: precisa de cobrança recorrente (Pix Automático/cartão), controle de uso (limite semanal, horários elegíveis) e relatório de rentabilidade por assinante, dado o risco de "assinante que vai todo dia".
- Cashback e pacotes (ex.: 4 escovas pré-pagas) são extensões naturais de um "saldo do cliente" no ERP.

### Gaps
- Não encontrei dados brasileiros sobre efetividade de cashback, NPS em salões ou impacto de avaliações do Google em salões.
- Intervalos de retorno por serviço vêm de fornecedores, sem estudo brasileiro; manicure/pedicure não tem intervalo documentado nas fontes encontradas.
- Sem preço atual de Belle.Club ou benchmarks de churn de clubes no Brasil.

## 4. WhatsApp Business API oficial, Instagram e agendamento via Google

### Takeaway
Desde 1º/07/2025 a Meta cobra por mensagem de template entregue (não mais por conversa). No Brasil (rate card de 01/07/2026, cobrável em BRL): marketing ≈ R$ 0,3217 (US$ 0,0625) e utility/authentication ≈ R$ 0,035 (US$ 0,0068). A partir de 01/10/2026, mensagens de serviço (respostas dentro da janela de 24h) passaram a ser cobradas (~R$ 0,035) após 1.000 grátis/mês por número. APIs não oficiais (QR Code/Baileys: Z-API, Evolution em modo Baileys) violam os termos e têm risco de banimento sem garantia. O Google oferece "Agendamento Online com o Google" (ex-Reserve with Google) via parceiros como Trinks.

### Cited Findings
**Modelo de preço Meta (fonte oficial):**
- Cobrança por mensagem entregue desde 01/07/2025; preço depende da categoria (marketing, utility, authentication, service) e do país do destinatário; Brasil é mercado próprio no rate card — [Meta Developers – Pricing](https://developers.facebook.com/docs/whatsapp/pricing/).
- Janela de atendimento (CSW) de 24h a partir da última mensagem do usuário; fora dela, só templates — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/).
- Cada número tem 1.000 mensagens de serviço grátis/mês (não acumulam) — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/).
- Em 01/10/2026, mensagens de serviço e utility dentro da CSW deixaram de ser gratuitas (passam a ser cobradas após a cota de 1.000) — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/); [WizeBot](https://wizebot.com.br/blog/tabela-precos-whatsapp-business-api-2026).
- Free Entry Point: conversa iniciada por anúncio Click-to-WhatsApp abre janela gratuita para todas as categorias — a Meta descreve "até 7 dias" — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/); WizeBot fala em 72h — [WizeBot](https://wizebot.com.br/blog/tabela-precos-whatsapp-business-api-2026) (conflito; 72h é o valor histórico, confirmar).
- Faturamento em BRL (emitido pela Facebook Brasil) disponível desde 01/07/2026 para BSPs elegíveis e empresas com país de venda Brasil; contas não-BRL devem migrar até 30/06/2027 — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/).
- Nova categoria "Meta Business Agent" (respostas por agente IA da Meta) desde 01/07/2026, cobrada por token (US$ 2,00 por 1M tokens, ~4–5 centavos de dólar/msg) — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/).
- Meta só altera preços em início de trimestre; aviso mínimo de 1 mês para rate cards e 6 meses para mudanças de modelo — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/).
- Página oficial cita ~0,68 centavo de dólar por mensagem utility/authentication para o Brasil — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/).

**Valores Brasil (rate card 01/07/2026, conforme BSPs que citam o CSV oficial):**
- Marketing R$ 0,3217 (US$ 0,0625); Utility R$ 0,0350 (US$ 0,0068); Authentication R$ 0,0350 (US$ 0,0068); Service R$ 0,0350 a partir de 01/10/2026 (após 1.000 grátis) — [WizeBot](https://wizebot.com.br/blog/tabela-precos-whatsapp-business-api-2026); [Dragapp](https://www.dragapp.com/pt-br/blog/api-oficial-do-whatsapp/); [Nicochat](https://nicochat.com/en/blog/whatsapp-api-pricing).
- Brasil não teve aumento de marketing em out/2026 — [WizeBot](https://wizebot.com.br/blog/tabela-precos-whatsapp-business-api-2026).
- Descontos por volume só para utility/authentication: utility R$ 0,0350 até 250 mil/mês; R$ 0,0333 (250 mil–2 mi); R$ 0,0315 (2–17 mi)... até R$ 0,0263 (>70 mi); marketing sem desconto — [WizeBot](https://wizebot.com.br/blog/tabela-precos-whatsapp-business-api-2026).
- Valores divergentes em outras fontes (marketing R$ 0,31–0,55; utility R$ 0,04–0,05), provavelmente desatualizados ou com markup de BSP — [MessageCentral](https://www.messagecentral.com/blog/whatsapp-business-api-pricing-brazil); [SocialHub](https://www.socialhub.pro/blog/api-oficial-whatsapp-preco-2026/); [Connectweek](https://www.connectweek.com.br/artigo/custo-whatsapp-business-api-2026).

**Templates e restrições:**
- A Meta classifica o template pela categoria do conteúdo, não pela intenção declarada; templates podem ser rejeitados ou recategorizados (ex.: utility com conteúdo promocional vira marketing) — [WizeBot](https://wizebot.com.br/blog/tabela-precos-whatsapp-business-api-2026).
- Baixa qualidade do número/denúncias de usuários geram restrições; nenhum provedor garante risco zero de bloqueio — [WizeBot](https://wizebot.com.br/blog/tabela-precos-whatsapp-business-api-2026).

**APIs não oficiais:**
- Canal não oficial (engenharia reversa do WhatsApp Web) contraria os Termos do WhatsApp e tem risco de banimento que nenhuma configuração elimina — [Hora de Codar](https://horadecodar.com.br/evolution-api-vs-api-oficial-whatsapp/).
- A própria Z-API reconhece que uso via QR Code pode levar a banimento e não se responsabiliza; possui endpoint de pedido de desbanimento sem garantia — [Cubo Suite](https://blog.cubosuite.com.br/z-api-vale-a-pena-api-paga-via-qr-code-e-o-risco-que-ninguem-conta/); [Z-API docs](https://developer.z-api.io/mobile/request-unbanning.md).
- Evolution API pode operar via Baileys (não oficial) ou via Cloud API oficial; relato de números antigos banidos logo após conectar instância (caso isolado) — [Hora de Codar](https://horadecodar.com.br/evolution-api-vs-api-oficial-whatsapp/); [GitHub issue Evolution](https://github.com/evolution-foundation/evolution-api/issues/2497).
- Recomendação de desconectar o número da ferramenta não oficial antes de migrar para a oficial — [Tenessi Hub](https://www.tenessihub.com.br/seo/bloqueios-por-uso-de-apis-nao-oficiais/).

**Google e Instagram:**
- "Reserve com o Google" para salões/barbearias no Brasil funciona via parceiros (Trinks, SuperAgendador) e exige perfil no Google Meu Negócio — [Tecnoblog](https://tecnoblog.net/noticias/google-maps-horario-salao-beleza/).
- Trinks renomeou a integração como "Agendamento Online com o Google" (antigo Reserve with Google); cliente é redirecionado à página de agendamento da Trinks — [Beauty Fair](https://negociosdebeleza.beautyfair.com.br/trinks-moderniza-os-agendamentos-com-a-nova-atualizacao-do-agendamento-online-com-o-google/); [Blog Trinks](https://blog.trinks.com/agendamento-pelo-google/).
- Agendamentos via Google entram automaticamente na agenda do sistema — [Blog Trinks](https://blog.trinks.com/atraia-com-o-google-e-fidelize-com-o-trinks/).
- No Instagram, o padrão citado pelos fornecedores é link de agendamento exclusivo na bio/stories, não um botão nativo — [Blog Trinks](https://blog.trinks.com/aplicativo-para-salao-de-beleza-como-divulgar-meu-negocio/).

### Inferences
- Custo unitário para o SaaS: confirmação/lembrete (utility) ≈ R$ 0,035; reativação/aniversário/promoção (marketing) ≈ R$ 0,32. Um salão com 400 atendimentos/mês e 2 lembretes cada ≈ 800 × 0,035 = R$ 28/mês em utility; campanhas de marketing pesam ~9× mais por mensagem — o SaaS deve repassar marketing por consumo (créditos) e embutir utility no plano.
- Aniversário e "cliente sumida" com oferta são marketing; "seu horário de retorno está chegando" sem oferta pode ser aprovado como utility, mas há risco de recategorização — desenhar templates neutros.
- Com a cobrança de service desde out/2026, chatbot de atendimento (IA) passa a ter custo por mensagem após 1.000/mês por número; anúncios Click-to-WhatsApp abrem janela grátis (FEP) — útil para captação.
- Arquitetura recomendada: Cloud API oficial (via BSP ou Tech Provider próprio, com Embedded Signup para o salão conectar o próprio número). Oferecer API não oficial como opção barata é risco reputacional (banimento do número principal do salão).
- Integrar com Reserve with Google exige virar parceiro do programa Actions Center — barreira de entrada relevante; curto prazo: link de agendamento no perfil do Google e Instagram.

### Gaps
- Não consegui baixar o CSV oficial da Meta em BRL; valores em BRL vêm de BSPs que o citam (consistentes entre si).
- Duração do Free Entry Point (72h vs "até 7 dias") conflita entre fontes.
- Não encontrei documentação oficial atual do Google sobre requisitos para novos parceiros de agendamento (Actions Center) no Brasil, nem sobre botão nativo "Reservar" no Instagram para o Brasil.
- Limites de envio de marketing por usuário (frequency capping da Meta) não detalhados nas fontes consultadas.

## 5. Marketing e tendências (Instagram, antes/depois, indicação, Google Meu Negócio, IA, agendamento online, bairro vs premium, autônomos)

### Takeaway
As fontes convergem em Instagram + link de agendamento, Google Meu Negócio (com botão de agendamento) e WhatsApp como os canais centrais de captação para salões brasileiros; dados quantitativos independentes são escassos. Tendências relevantes: explosão de MEIs/autônomos (94% das aberturas), automação/IA no atendimento via WhatsApp e modelos recorrentes (assinatura), com franquias de beleza ainda crescendo dois dígitos.

### Cited Findings
- Clientes podem agendar pela busca do Google ou pelo link de agendamento nas redes sociais; sistema gera link exclusivo para compartilhar — [Blog Trinks](https://blog.trinks.com/agendamento-pelo-google/); [Blog Trinks](https://blog.trinks.com/aplicativo-para-salao-de-beleza-como-divulgar-meu-negocio/).
- Fornecedores recomendam sistemas de captação/retenção (indicação, avaliações, portfólio, régua de WhatsApp) — [alteg.io](https://alteg.io/pt/blog/receita-salao-18-sistemas-atrair-reter-clientes/); [Trinks – rotina de mensagens](https://trinks.com/programa-para-salao/site-aplicativo-de-divulgacao-agendamento).
- Automação com IA listada entre tendências 2025–2026 para salões (fonte de escola de cursos, sem dados) — [Criadores de Imagem](https://cursos.criadoresdeimagem.com.br/tendencias-do-mercado-de-saloes-de-beleza-para-2025-e-2026-o-que-esperar/); IA no WhatsApp para atender e fazer clientes voltarem (fornecedor) — [Assis](https://assis.co/blog/ia-para-salao-de-beleza).
- Tendências de serviço 2026: cobertura de grisalhos em alta (80% das consultas em um salão de celebridades em 2025), cores criativas mais estratégicas — [Estado de Minas](https://www.em.com.br/emfoco/2025/12/10/as-tendencias-de-cortes-e-cores-que-vao-dominar-os-saloes-de-beleza-em-2026/); Mintel 2026: "Human Touch Revolution", "Metabolic Beauty" — [Editorial Brasil](https://www.editorialbrasil.com.br/2026/01/tendencias-para-o-setor-de-beleza-em.html).
- Franquias de saúde/beleza +14,6% em 2025 — [Prensa de Babel](https://prensadebabel.com.br/324708-franquias-de-beleza-e-saude-crescem-146/); Norte e Centro-Oeste com escassez de profissionais qualificados — [O Nortão](https://www.onortao.com.br/2026/07/setor-de-beleza-cresce-112-no-brasil.html).
- 94% das novas empresas de beleza em 2025 são MEI — [Agência Sebrae](https://agenciasebrae.com.br/cultura-empreendedora/a-cada-hora-27-negocios-de-beleza-sao-abertos-no-pais-crescimento-foi-de-185-em-2025/).
- Meta lançou categoria de agente de IA própria (Meta Business Agent) no WhatsApp em jul/2026, cobrada por token — [Meta Developers](https://developers.facebook.com/docs/whatsapp/pricing/).

### Inferences
- Funcionalidades de marketing a automatizar: pedido de avaliação no Google pós-atendimento (D+1, só para quem deu nota alta no NPS), galeria de antes/depois por profissional exportável para Instagram, programa de indicação com cupom rastreável, link de agendamento único para bio do Instagram e Google, campanhas segmentadas por serviço/inatividade.
- Segmentação de produto: (a) autônomo/MEI (agenda + link + lembrete + Pix, preço baixo); (b) salão de bairro (multi-profissional, comissão/salão-parceiro, régua WhatsApp); (c) premium/rede (assinatura, multiunidade, BI).
- IA no WhatsApp (agendamento conversacional) é diferencial, mas agora tem custo por mensagem de serviço após 1.000/mês — precificar.

### Gaps
- Não encontrei dados quantitativos confiáveis sobre % de agendamentos online vs. WhatsApp/telefone em salões brasileiros.
- Sem dados sobre efetividade de antes/depois, indicação ou Google Meu Negócio especificamente para salões no Brasil.
- Sem pesquisa sobre divisão salões de bairro vs premium nem sobre número de profissionais "home"/delivery (atendimento a domicílio).
- Não pesquisei Exame/Valor/PEGN diretamente; matérias desses veículos sobre salões não apareceram nas buscas.
