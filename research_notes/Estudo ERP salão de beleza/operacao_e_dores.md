# Operação diária e dores de um salão de beleza brasileiro (foco em cabeleireiro), 2025-2026

> Notas de pesquisa para desenhar um SaaS/ERP de gestão de salões. Observações sobre as fontes:
> (1) muito conteúdo sobre "dores" vem de blogs de fornecedores de software (Belasis, SocialHub, Chatsac, Rework, Aurora Inbox), que têm interesse comercial e números sem metodologia, o que está sinalizado em cada caso;
> (2) a fonte primária mais forte e recente é a pesquisa **Data Sebrae-SP "Perfil e Desafios dos Negócios de Beleza e Estética"**, com 800 MEIs do estado de SP, coletada entre 31/05 e 08/06/2025 e publicada em 11/2025 ([PDF Data Sebrae](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf)). Daqui em diante ela aparece como "Data Sebrae-SP 2025";
> (3) não achei relatos em primeira pessoa no Reddit nem em grupos de Facebook pela busca na web. Grupos de Facebook e comentários do Instagram/YouTube não são indexáveis. Isso está registrado nas lacunas.

---

## 1. Fluxo diário: abertura, recepção, encaixes, agenda por profissional, atendimento simultâneo, pausa de química, comanda e fechamento de caixa

### Takeaway
O dia do salão gira em torno de uma **agenda por profissional** que é vendida e confirmada pela recepção (WhatsApp e telefone), de uma **comanda** aberta por cliente onde se lançam serviços e produtos, e do **fechamento de caixa** no fim do expediente com rateio de comissões. O que torna a agenda de cabeleireiro diferente é a **pausa de química** (tempo de pose da coloração ou alisamento). Nela o profissional fica livre para atender outra cliente, e é dessa janela que nascem os encaixes e o "atendimento simultâneo". Ferramentas genéricas de agendamento muitas vezes não modelam isso.

### Cited Findings
- **Tarefas da recepção em vagas reais (2025-2026)**:
  - vagas em Cuiabá e Juiz de Fora pedem "receber comandas, realizar cobranças e efetuar abertura e fechamento de caixa" e "enviar mensagens de confirmação, relacionamento e campanhas de marketing via WhatsApp" — [InfoJobs, vaga recepcionista salão premium Cuiabá](https://www.infojobs.com.br/vaga-de-recepcionista-salao-beleza-premium-cuiaba-mt-em-mato-grosso__11867489.aspx); [InfoJobs, vagas recepcionista](https://www.infojobs.com.br/vaga-de-recepcionista-em-sao-paulo__11868732.aspx);
  - outra vaga pede "organizar e acompanhar a agenda dos profissionais; confirmar horários e manter contato com os clientes" — [Solutudo, vaga BH](https://www.solutudo.com.br/empregos/mg/belo-horizonte/recepcionista-2845906);
  - uma vaga em Curitiba põe como meta "garantindo a ocupação máxima da agenda dos profissionais", com atendimento "presencial, via WhatsApp e telefone" — [Solutudo, vaga Curitiba](https://www.solutudo.com.br/empregos/pr/curitiba/recepcionista-salao-de-beleza-2792690).
- **Como é a gestão na prática em salões pequenos**: "é comum o dono do salão anotar horário em caderno, calcular comissão na calculadora e perder o controle do estoque de produto". Muitos operam "sem funcionário de apoio para cuidar da parte administrativa", e o dono acaba responsável por "agenda, caixa e compra de produto ao mesmo tempo". O artigo é patrocinado pela Belasis — [UAI/PulseBrand, 18/09/2026](https://www.uai.com.br/?p=175719).
- O cenário típico é descrito como "agenda escrita à mão, caixa controlado de cabeça e contato dos clientes guardado no WhatsApp" (conteúdo ligado à Belasis) — [UAI, "Do secador ao caixa"](https://www.uai.com.br/?p=180193); e "caderno de anotações, planilha improvisada, controle de caixa de cabeça" — [Estado de Minas, 07/2026 (patrocinado)](https://www.em.com.br/networking-e-negocios/2026/07/7467512-da-cadeira-a-gestao-como-a-tecnologia-forma-donos-de-salao-empreendedores.html).
- **Tamanho típico**: no Data Sebrae-SP 2025, quase metade dos negócios (47%) trabalha com **duas pessoas, incluindo o proprietário**. 23% funcionam **em casa**, 28% em sala comercial e 27% em loja de rua. Salão de beleza é 46% da amostra, contra 29% de clínicas de estética e 12% de esmalterias — [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).
- **Pausa de química e atendimento simultâneo**:
  - fornecedores de agenda descrevem o caso clássico: durante o tempo de exposição da coloração o cabeleireiro fica livre para atender outra cliente, e por isso o sistema precisa de "agendamentos paralelos" ou "split appointments" — [Wix Suporte, pedido de agendamentos paralelos](https://support.wix.com/pt/article/pedido-wix-bookings-fazer-agendamentos-paralelos); [Schedulista, Split appointments](https://support.schedulista.com/en/articles/397485-split-appointments);
  - **o Wix Bookings não permite** agendamento paralelo com o mesmo profissional; o recurso ainda estava "em votação" — [Wix Suporte](https://support.wix.com/pt/article/pedido-wix-bookings-fazer-agendamentos-paralelos);
  - na comunidade do Square, cabeleireiros relatam fazer "double booking" durante a coloração e pedem que o sistema modele o "processing time" — [Square Seller Community, Processing time / Double booking](https://www.sellercommunity.com/t5/Questions-How-To/Processing-time-Double-Booking-Questions/m-p/183934);
  - um fornecedor sugere definir a duração do serviço separando tempo ativo e tempo de processamento, "para liberar membros da equipe para atender outros clientes enquanto o tratamento ocorre" — [Zenoti ES, hair salon software](https://www.zenoti.com/es/salon-management-software/hair-salon-software).
- **Tempo de pausa varia por cliente**: a Wella diz que pontas de cabelo longo "tendem a absorver mais cor" e por isso "o tempo de pausa pode ser diferente para as pontas". Cabelos grossos pedem mais tempo, e química prévia aumenta a porosidade. A orientação é contar o tempo "assim que terminar de aplicar" e definir alarme conforme a embalagem e o teste de mecha — [Wella Brasil](https://www.wella.com/br/veja-8-perguntas-sobre-cuidados-antes-de-pintar-o-cabelo).
- **Fechamento de caixa**: a recomendação geral é fechar diariamente, no fim do expediente, e não misturar dinheiro pessoal e da empresa (fontes de ERPs genéricos, não específicas de salão) — [Bling blog](https://blog.bling.com.br/?p=13632); [Jornal Contábil, 5 erros de fechamento](https://jornalcontabil.com.br/noticia/os-5-erros-de-um-fechamento-de-caixa/). A Trinks é associada a "comandas digitais e ferramentas para o fechamento de caixa" — [Mercado Pago blog](https://www.mercadopago.com.br/blog/ferramentas-automatizar-agenda-pagamento-salao).

### Inferences
- **Fluxo-padrão reconstruído.** Esta é uma síntese das fontes acima com conhecimento de domínio, sem fonte única que descreva tudo:
  1. **Abertura**: abrir caixa com fundo de troco; conferir a agenda do dia e confirmações pendentes; ver produtos críticos (oxidante, pó descolorante, tinta nos tons agendados); esterilizar materiais de manicure.
  2. **Recepção**: check-in da cliente e abertura da comanda vinculada a ela e ao profissional; oferecer café; lavatório (às vezes com assistente).
  3. **Execução**: aplicação da química → **pausa** (de 20 a 45 min na coloração; mais em descoloração e progressiva) → nessa janela, corte, escova ou finalização de outra cliente → enxágue e tratamento → finalização.
  4. **Venda adicional**: produto de home care lançado na comanda.
  5. **Checkout**: pagamento em Pix, cartão ou dinheiro, muitas vezes dividido; gorjeta; desconto; pacote ou crédito pré-pago.
  6. **Fechamento**: conferir caixa por forma de pagamento, apurar comissões por profissional (bruto ou líquido de taxas e produtos) e lançar despesas do dia.
- **Requisitos de produto que derivam disso**:
  - serviço com **fases** (ativa → pausa → ativa) em que a pausa libera o profissional mas ocupa a cadeira ou o lavatório;
  - **recursos físicos** (lavatório, cadeira, sala de manicure) como restrição da agenda;
  - **assistente** (lava, aplica, escova) que divide a comissão;
  - **encaixe** sugerido pelo próprio sistema ("buracos" de 15 a 40 min);
  - comanda com **vários profissionais** por cliente (escova com uma, mão com a manicure).
- O porte dominante (1 a 3 pessoas, dono que também atende) indica que o produto tem de funcionar **no celular, com uma mão, entre um atendimento e outro**. Uma tela de recepção cheia de etapas não serve para esse público.

### Gaps
- Não achei estudo brasileiro (Sebrae, ABSB) que descreva o fluxo diário com tempos medidos, por exemplo o tempo de recepção até a cadeira ou o percentual da agenda ocupado por pausas.
- Não achei dados sobre a proporção de salões com recepcionista dedicada versus o dono acumulando a função. O Data Sebrae-SP só dá o número de pessoas no negócio.

---

## 2. Dores do dono ou gestor

### Takeaway
As dores centrais são: (a) **gestão informal**, com caderno, calculadora e caixa "de cabeça" e menos de 30% usando sistema; (b) **equipe**, com falta de profissionais, perda para o atendimento domiciliar, profissionais que levam a carteira de clientes e conflitos de comissão no modelo "salão-parceiro"; (c) **financeiro**, com margens baixas, faturamento pequeno e mistura de contas pessoais e da empresa; (d) **no-show**; (e) **estoque desperdiçado**; (f) **sazonalidade forte**, com dezembro lotado e janeiro e fevereiro vazios.

### Cited Findings
**Informalidade e porte**
- "Menos de 30% dos estabelecimentos do setor usam algum sistema de gestão". A maioria dos salões, barbearias e clínicas fatura menos de R$ 50 mil por mês, e o setor tem mais de 1,1 milhão de pequenos negócios e cerca de 230 mil novos CNPJs por ano. Os dados são atribuídos ao Sebrae em artigo patrocinado pela Belasis, sem metodologia — [UAI, 09/2026](https://www.uai.com.br/?p=175719).
- No Data Sebrae-SP 2025 (MEIs):
  - **62% faturam até R$ 8.000/mês** e 39% entre R$ 2 mil e R$ 6 mil;
  - investimento inicial médio de **R$ 4.905,68**;
  - 42% têm de 1 a 3 anos de vida;
  - 54% eram CLT antes de empreender;
  - **"Gestão financeira"** é o segundo tema que mais querem aprender (48%), atrás de marketing digital (58%);
  - **gestão de pessoas** aparece com cerca de 31% e **estoque** com cerca de 13%;
  - apenas cerca de 20% citam "gestão eficiente do negócio (finanças, estoque, equipe)" como fator de sucesso, contra 54% que citam "atendimento de qualidade e relacionamento com o cliente".

  Fonte: [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).
- Existem mais de 500 mil salões no Brasil (Sebrae), e o setor HPPC movimenta mais de R$ 130 bi por ano (ABIHPEC) — [Estado de Minas, 07/2026](https://www.em.com.br/networking-e-negocios/2026/07/7467512-da-cadeira-a-gestao-como-a-tecnologia-forma-donos-de-salao-empreendedores.html). Cerca de 236 mil empresas de beleza se formalizaram no ano, segundo levantamento Sebrae divulgado em 01/2026, e "quase 30 salões de beleza são abertos no Brasil por hora" — [Jornal Opção](https://www.jornalopcao.com.br/ultimas-noticias/quase-30-saloes-de-beleza-sao-abertos-no-brasil-por-hora-784809/).
- **Mortalidade**: o MEI tem a maior taxa de mortalidade em 5 anos (29%) — [Agência Sebrae](https://agenciasebrae.com.br/economia-e-politica/tres-em-cada-10-mei-fecham-as-portas-em-ate-cinco-anos-de-atividade-no-brasil). O Sebrae-PR registra 51.744 empresas de beleza encerradas em 2021 e mortalidade de 29,04%, sem deixar claro o recorte — [Sebrae PR, Sebrae em dados: salões](https://sebraepr.com.br/comunidade/artigo/sebrae-em-dados-saloes-de-beleza).

**Equipe, liderança e dependência do dono**
- Consultor Sebrae-PR: "uma das maiores reclamações que ouço dos gestores e donos de salão de beleza é que os profissionais não levam o trabalho a sério", e "A equipe é um reflexo do gestor, do líder". O texto descreve salões onde "a mãe do dono do salão, ou a mãe do cabeleireiro faz o que quer no salão", que funcionam "de forma precária, informal, sem uma estrutura para o crescimento", com risco de "esquecer de pagar a conta de luz" e de "perder cliente simplesmente porque foi desorganizada" — [Sebrae PR, "Salão de beleza é uma empresa"](https://sebraepr.com.br/comunidade/artigo/salao-de-beleza-e-uma-empresa-11).
- **Falta de profissionais**: em pesquisa da ABSB (2021 vs 2019), **66%** dos donos tinham menos gente trabalhando que em 2019, e cerca de **52%** dos profissionais que atuavam em salões passaram a atender **em domicílio**. O presidente da ABSB chamou a reposição de pessoal de problema. Sebrae Nacional: o salão retém o profissional oferecendo "serviços essenciais" de agendamento, gestão financeira e tributária, estoque e manutenção de equipamentos — [Agência Sebrae, 18/02/2022](https://agenciasebrae.com.br/?p=2737). Os dados são de 2022, mas a tendência de tirar o profissional do salão aparece de novo em 2025: entre as tendências do Data Sebrae-SP está "Muitos profissionais tendem a oferecer atendimentos em casa ou em estúdios" — [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).

**Comissão e modelo salão-parceiro**
- A **Lei 13.352/2016 (Salão-Parceiro)** permite que cabeleireiros, manicures, esteticistas e maquiadores trabalhem como "profissional-parceiro", sem vínculo CLT. O contrato precisa estipular o **percentual de retenção do salão** sobre cada serviço (a cota-parte do salão remunera aluguel de bens e serviços de gestão) e a **cota-parte do profissional**. O salão é quem recebe e repassa, e retém tributos e contribuições — [Lei 13.352/2016, Câmara](https://www2.camara.leg.br/legin/fed/lei/2016/lei-13352-27-outubro-2016-783851-publicacaooriginal-151331-pl.html).
- Sebrae-PR sobre comissão: "na lei, não existe um valor ou percentual exigido pelo governo, vale o bom senso na hora da negociação". O percentual deve vir do custeio:
  - custos fixos (aluguel, luz, água, internet, tarifas, salário da recepção, pró-labore);
  - custos variáveis (impostos, **percentual pago à operadora de cartão**, produtos usados no serviço, descartáveis como palitos, lixas e luvas, esterilização);
  - rateio do custo fixo.

  Os erros comuns citados são informalidade (risco trabalhista), não mostrar os custos à equipe e **atrasar o pagamento** de comissão. Sugere uma planilha com data, hora, profissional, tipo de serviço e valor recebido, com fórmula de comissão — [Sebrae PR, Como fazer o cálculo de comissão](https://sebraepr.com.br/comunidade/artigo/como-fazer-o-calculo-de-comissao-em-um-salao).
- Guia contábil: o pagamento por comissão obriga a "acompanhar a receita individual de cada profissional e recalcular os valores a cada período de pagamento" — [Beancount PT, guia financeiro para salões (01/2026)](https://beancount.io/pt/blog/2026/01/25/hair-salon-bookkeeping-complete-financial-guide).

**No-show e atrasos**
- Números de **fornecedores**, sem metodologia verificável: salões sem lembrete automático teriam de 15% a 30% de faltas e cancelamentos — [Chatsac](https://chatsac.com/blog/whatsapp-para-salao-de-beleza/). Uma tabela de fornecedor cita de 15% a 22% caindo para 7% a 10% com lembretes — [SocialHub](https://www.socialhub.pro/blog/reduzir-no-show-whatsapp-business-estrategias/). Outra fonte diz que a confirmação bidirecional reduz faltas em 30% a 40% (citando Booker/MINDBODY) e que **exigir sinal de clientes novas** reduz faltas em até 50% — [Rework, no-show management](https://resources.rework.com/pt/libraries/beauty-center-growth/no-show-cancellation-management).
- Há modelos de **política de cancelamento** para salão (prazo, multa, sinal) em circulação — [Koalendar](https://koalendar.com/pt-br/blog/politica-de-cancelamento-para-salao-de-beleza).

**Sazonalidade**
- Dona de salão em Curitiba: "Dezembro é o mês de maior movimento nos salões"; o fluxo cresce a partir do dia 15 e os salões ficam lotados até o dia 24 — [Tribuna PR](https://www.tribunapr.com.br/noticias/parana/procura-por-saloes-de-beleza-esta-grande/).
- Projeções: agendamentos até **70%** maiores em dezembro (Pará) — [Diário do Pará](https://diariodopara.com.br/para/mercado-da-beleza-se-prepara-para-o-final-do-ano/); faturamento de dezembro/2024 50% maior (ES) — [Folha Vitória](https://www.folhavitoria.com.br/economia/saloes-de-beleza-projetam-aumento-de-ate-70-no-faturamento-no-es/).
- A demanda inclui **confraternizações empresariais e formaturas escolares**. Há salões com **lista de espera**, e os dias **30 e 31/12** são os mais disputados em Brasília. Alguns salões **abrem às segundas** (dia atípico) ou estendem o horário — [Diário do Pará](https://diariodopara.com.br/para/saloes-de-beleza-ampliam-horario-de-atendimento-neste-fim-de-ano/); [Correio Braziliense](https://www.correiobraziliense.com.br/cidades-df/2024/08/6920416-saloes-e-bufes-da-capital-estao-concorridos-para-festas-de-fim-de-ano.html).
- **Noivas**: salões pedem contato com **30 a 60 dias** de antecedência; o sinal costuma ser **50% na assinatura** do contrato e o restante no dia, ou 50% / 25% no teste / 25% no casamento — [casamentos.com.br, Salão Nei Cannizza](https://www.casamentos.com.br/beleza-noivas/salao-nei-cannizza--e173192); [casamentos.com.br, Priscilla Martillo](https://www.casamentos.com.br/beleza-noivas/priscilla-martillo-make-up--e160204); [casamentos.com.br, Linders Coiffeur](https://www.casamentos.com.br/beleza-noivas/linders-coiffeur--e131809).

**Precificação**
- Em BH, a variação de preço entre regiões passa de **800%** em corte feminino, hidratação e tintura, o que mostra precificação sem referência de custo — [Diário do Comércio / Mercado Mineiro, 10/2025](https://diariodocomercio.com.br/?p=530609). Em Campo Grande (Procon, 03/2025), o corte variou até R$ 159 entre cinco salões do centro — [Campo Grande News](https://www.campograndenews.com.br/economia/corte-de-cabelo-pode-variar-ate-r-159-revela-pesquisa-do-procon).
- 59% dos negócios usam **promoções e descontos** como forma de divulgação — [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).

**Risco de química (responsabilidade civil)**
- Há casos noticiados de clientes com **queimaduras no couro cabeludo** em salão, o que reforça a necessidade de registrar teste de mecha, anamnese e consentimento — [DOL, Belém](https://dol.com.br/noticias/para/684814/cliente-sofre-queimaduras-na-cabeca-em-salao-de-belem); [Consumidor Moderno, deveres dos salões](https://consumidormoderno.com.br/saloes-de-beleza-deveres-e-os-direitos-do-consumidor/).

### Inferences
- **"Profissionais que levam clientes embora"** é uma dor estrutural: o modelo salão-parceiro torna o cabeleireiro um prestador autônomo, 52% migraram para o domicílio e o contato da cliente fica no WhatsApp pessoal do profissional (ver seção 3). Sem um **CRM do salão** com histórico, ficha técnica, fotos e WhatsApp do salão, o ativo "carteira de clientes" pertence ao profissional. O SaaS pode tornar o salão dono do relacionamento, com WhatsApp centralizado, histórico e lembretes enviados pelo salão, sem prender o profissional (a lei não permite exclusividade abusiva, e o produto não deve prometer isso).
- **Comissão** é a dor mais propensa a conflito. As variáveis que um motor de comissão precisa suportar:
  - percentual diferente por serviço e por profissional;
  - base bruta ou líquida (desconto da taxa de cartão, do custo de produto ou "taxa de química", do desconto concedido à cliente);
  - divisão com assistente;
  - comissão sobre venda de produto;
  - vales e adiantamentos;
  - regras do contrato de parceria (retenção do salão, tributos do MEI parceiro).

  As fontes confirmam taxa de cartão, produtos e descartáveis como deduções discutidas (Sebrae-PR). Os percentuais típicos (de 40% a 60% para o profissional) são conhecimento de mercado **não verificado nesta pesquisa**.
- A **dependência do dono** aparece no porte (47% com 2 pessoas) e no acúmulo de papéis (dono que corta, compra, cobra e fecha caixa). O produto deve permitir **delegar** (perfis de recepção e profissional com permissões) e dar ao dono um **painel resumido no celular**.
- **Sazonalidade**: dezembro pede lista de espera, abertura de horários extras (segundas), sinal obrigatório nas datas de pico e pacotes de noiva e formatura com contrato e parcelas. Janeiro e fevereiro pedem campanhas de reativação.

### Gaps
- Não achei pesquisa recente (2025-2026) com **taxa de rotatividade** de profissionais em salões brasileiros nem quantificação de "profissional que sai e leva clientes"; a busca não retornou relatos.
- Não achei **percentual médio de comissão** de fonte confiável (Sebrae diz que não há percentual legal).
- Não há taxa de no-show brasileira de fonte independente; todos os números são de fornecedores de software.
- Faltam dados sobre **margem líquida** típica de salão no Brasil.

---

## 3. Dores do cabeleireiro e do profissional

### Takeaway
O profissional quer saber **quanto vai receber** (comissão transparente e em dia), ter **agenda organizada** (sem encaixes que atrasam tudo), **guardar o histórico técnico** da cliente (fórmula de cor, fotos) e **divulgar o trabalho no Instagram**, a principal vitrine do setor. Hoje o contato das clientes mora no **WhatsApp pessoal** dele, o que vira vulnerabilidade tanto para o profissional (golpes, perda do número) quanto para o salão (perda da cliente).

### Cited Findings
- **Comissão em dia** é um ponto de atrito: o Sebrae recomenda "pagar em dia" para manter a equipe comprometida e mostrar aos profissionais os custos que compõem o percentual — [Sebrae PR, cálculo de comissão](https://sebraepr.com.br/comunidade/artigo/como-fazer-o-calculo-de-comissao-em-um-salao).
- **WhatsApp como ferramenta única**: uma cabeleireira de Curitiba teve o WhatsApp invadido por golpistas, perdeu mais de R$ 3,5 mil e ficou **sem trabalhar**, porque o contato com as clientes e o agendamento passavam pelo app — [Band B](https://www.bandab.com.br/seguranca/whatsapp-invadido-cabeleireira-golpe-curitiba/).
- **Instagram como canal principal**: 87% divulgam por redes sociais, 79% usam Instagram, 53% Facebook, 35% TikTok e 26% citam o WhatsApp como rede; 50% contam com o boca a boca; 58% querem aprender marketing digital — [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).
- **Profissional sobrecarregado com o administrativo quando sai do salão**: a Sebrae Nacional diz que profissionais independentes muitas vezes ficam "sobrecarregados com tarefas administrativas", por isso agenda, gestão financeira e estoque são o que o salão pode oferecer — [Agência Sebrae](https://agenciasebrae.com.br/?p=2737).
- **Tendências técnicas que mudam o cardápio**: "menos química, mais cuidado com a saúde do couro cabeludo" (33%), valorização de cabelos crespos, cacheados e grisalhos (32%) e terapias capilares como ozônio, argila e LED (32%) — [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).
- **"Ser bom com as mãos deixou de ser suficiente"** (artigo patrocinado) — [Estado de Minas](https://www.em.com.br/networking-e-negocios/2026/07/7467512-da-cadeira-a-gestao-como-a-tecnologia-forma-donos-de-salao-empreendedores.html).

### Inferences
- **"Quanto vou receber"** pede um extrato em tempo real no app do profissional: serviços do dia, base de cálculo, deduções (taxa de cartão, produto) e vales, com a mesma lógica que o dono usa no fechamento. É isso que reduz a desconfiança.
- **Fotos de antes e depois** ligadas à ficha da cliente cumprem duas funções: registro técnico (comparar tom, provar resultado em caso de reclamação) e **conteúdo para o Instagram**, com autorização de uso de imagem. Um botão "compartilhar no Instagram com marca d'água ou @ do salão" responde à dor de divulgação.
- A briga sobre **WhatsApp pessoal versus do salão** é delicada. O profissional parceiro (autônomo) tende a preferir o número próprio. Uma solução de equilíbrio é WhatsApp central do salão para confirmação e lembretes, com o histórico da cliente no sistema e o profissional vendo a agenda no app dele.
- **Agenda bagunçada**: encaixes feitos pela recepção sem considerar a pausa real da química geram atraso em cascata. O profissional precisa poder **bloquear e liberar janelas** e marcar "pausa iniciada", e o sistema deve recalcular.

### Gaps
- Não achei depoimentos em primeira pessoa de cabeleireiros brasileiros sobre comissão ou agenda (Reddit e fóruns não retornaram nada). Grupos de Facebook e comentários de YouTube e Instagram não são indexáveis por busca.
- Não achei dados sobre quantos profissionais usam o WhatsApp pessoal versus o do salão.

---

## 4. Dores da recepção

### Takeaway
A recepção é uma central de WhatsApp e telefone: agenda, confirma, remarca, cobra sinal, recebe comandas e abre e fecha o caixa, com a meta de "ocupação máxima da agenda". Os gargalos são o volume de mensagens, as remarcações, a lista de espera e a cobrança de sinal, que quase não aparece documentada no varejo de salão, exceto para noivas.

### Cited Findings
- Funções e metas da recepcionista: confirmação por WhatsApp, cobrança, comandas, abertura e fechamento de caixa e ocupação máxima da agenda — [InfoJobs Cuiabá](https://www.infojobs.com.br/vaga-de-recepcionista-salao-beleza-premium-cuiaba-mt-em-mato-grosso__11867489.aspx); [Solutudo Curitiba](https://www.solutudo.com.br/empregos/pr/curitiba/recepcionista-salao-de-beleza-2792690); [Solutudo BH](https://www.solutudo.com.br/empregos/mg/belo-horizonte/recepcionista-2845906).
- Roteiro de **remarcação** recomendado: "Quer remarcar para a próxima semana ou prefere entrar na **lista de espera** para um horário hoje?" — [Chatsac](https://chatsac.com/blog/whatsapp-para-salao-de-beleza/).
- **Confirmação 24 h antes** por WhatsApp automático e **sinal para clientes novas** são as práticas mais recomendadas (fornecedores) — [Rework](https://resources.rework.com/pt/libraries/beauty-center-growth/no-show-cancellation-management); [Aurora Inbox, guia 2026](https://www.aurorainbox.com/pt/2026/05/03/sistema-de-agendamento-via-whatsapp-para-barbearias-e-saloes-de-beleza/).
- Já há ferramentas que cobram **sinal pelo link de agendamento** para reduzir ausências — [Belasis, funções indispensáveis](https://www.belasis.com.br/en/softwares-para-salao-de-beleza-funcoes-indispensaveis); um artigo de automação com n8n descreve lembrete e confirmação ou cancelamento automáticos — [Hora de Codar](https://horadecodar.com.br/automacoes-n8n-salao-cabeleireiro/).
- Um artigo sobre agendamento por chat manual argumenta que isso "segura" o negócio (fornecedor) — [Dealism](https://dealism.ai/pt/user-stories/hair-salon-scheduling-why-manual-chat-booking-is-holding-your-business-back).

### Inferences
- Em salão de 1 a 3 pessoas **não há recepcionista**: o profissional responde WhatsApp com a mão enluvada, entre clientes. Por isso **autoagendamento** (link ou Instagram), **confirmação automática** e um **bot no WhatsApp** que entende "remarcar" e "cancelar" têm valor muito alto nesse segmento.
- A **cobrança de sinal** via Pix com prazo é a ferramenta natural no Brasil, e o sinal precisa entrar no caixa e abater na comanda. É especialmente importante em química longa (progressiva, mechas), noivas, dezembro e clientes com histórico de falta (o sistema pode marcar "cliente com N faltas").
- A **lista de espera** com aviso automático quando surge vaga resolve o pico de dezembro e os buracos de cancelamento.
- **Duração variável por cliente**: mechas em cabelo longo e grosso duram mais. A recepção precisa de duração sugerida pelo histórico da cliente, não só pela tabela de serviços.

### Gaps
- Não achei valor típico de sinal (% ou R$) para serviços comuns fora do segmento de noivas, nem prazo típico de cancelamento.
- Não achei dados de volume (mensagens por dia, tempo de resposta) da recepção de salão brasileiro.

---

## 5. Ficha técnica de química e coloração: o que se registra e por quê

### Takeaway
A ficha técnica guarda o que é necessário para **reproduzir** o resultado (marca, tom, proporção, volume do oxidante, tempo de pausa por região) e para **proteger** cliente e salão (teste de mecha e de sensibilidade com data, alergias, química anterior). Ela também é o ativo técnico que mais prende a cliente ao salão.

### Cited Findings
- **Teste de mecha** confirma o tempo necessário para atingir a cor. O tempo muda entre raiz e pontas, com a espessura do fio e com a química prévia (permanente e relaxamento deixam o fio mais poroso) — [Wella Brasil](https://www.wella.com/br/veja-8-perguntas-sobre-cuidados-antes-de-pintar-o-cabelo).
- **Prova de toque (teste de alergia)** antes da aplicação é exigência de bula de vários fabricantes. O tempo de pausa recomendado deve ser respeitado — [Drogaraia, Salon Line, bula de tonalizante](https://www.drogaraia.com.br/tonalizante-color-express-fun-fancy-red-salon-line-100ml-862668.html).
- **Padrão de formação profissional** (Espanha, usado aqui como referência de boas práticas): o oxidante deve ser escolhido conforme as características da cliente, do cabelo e o tipo de coloração, e deve-se "registrar na ficha técnica o resultado da prova de tolerância... incluindo a data de realização" — [INCUAL, UC0348_2](https://incual.educacion.gob.es/documents/20195/1873867/UC0348_2+-+A_CA_+Documento+publicado/60ae13b8-0c12-413a-8714-387d3c4d8dc2); [Comunidad de Madrid, exame 2025](https://www.comunidad.madrid/docs/assets/2025/06/30/rh03_257_2025_exam_598007.pdf).
- **Proporção de mistura** varia por linha: coloração permanente vem com oxidante de 20 volumes em kits como 60 g de tinta para 90 ml de oxidante (Itallian Color 6.31) — [Beleza na Web](https://www.belezanaweb.com.br/mp397504-coloracao-itallian-color-6-31-louro-escuro-dourado-cinza-60g-ox-20-vol-90g).
- **Reaplicar coloração sobre fios já pigmentados** acumula produto e resseca a fibra. Recomenda-se aplicar só na raiz — [NSC Total, Rodrigo Cintra](https://www.nsctotal.com.br/?p=8011901).
- Relato de risco: queimadura química no couro cabeludo em salão — [DOL](https://dol.com.br/noticias/para/684814/cliente-sofre-queimaduras-na-cabeca-em-salao-de-belem).

### Inferences
- **Campos sugeridos para a ficha**. É uma síntese das fontes com prática de mercado; o modelo exato não foi achado em fonte brasileira.
  - **Anamnese**: alergias (PPD, amônia), gestação e amamentação, medicamentos, problemas de couro cabeludo, química prévia com tipo e data (progressiva com formol ou ácido, henna, metálicos, alisamento, descoloração) e cabelo branco (%).
  - **Diagnóstico**: altura de tom natural, fundo de clareamento, porosidade, espessura, comprimento e elasticidade.
  - **Teste de sensibilidade**: data, produto e resultado. **Teste de mecha**: data, fórmula, tempo e resultado.
  - **Fórmula**: por zona (raiz, comprimento, pontas) com marca, linha, tom ou tons e gramas de cada um, oxidante (marca e volume: 10, 20, 30 ou 40) e proporção (1:1, 1:1,5, 1:2), aditivos (plex, protetor) e **gramas totais usadas**, que alimentam o estoque e o custo.
  - **Técnica**: global, retoque de raiz, mechas, luzes, babylights, balayage ou morena iluminada; papel ou touca.
  - **Tempos**: aplicação, pausa por zona, calor sim ou não.
  - **Pós**: matização (fórmula e tempo), tratamento e produto indicado para casa.
  - **Fotos** antes e depois e assinatura ou aceite de consentimento.
  - **Próximo retorno sugerido**.
- **Por que registrar**:
  1. **reprodutibilidade**: a cliente volta em 30 a 45 dias e quer o mesmo tom, e outro profissional deve conseguir reproduzir;
  2. **segurança e responsabilidade**: provar o teste de alergia e de mecha com data;
  3. **custo real**: gramas usadas viram baixa de estoque fracionado e custo por serviço;
  4. **retenção**: a ficha pertence ao salão e reduz a perda da cliente quando o profissional sai.
- O lançamento das gramas tem de ser rápido, de preferência com **balança** ou presets ("raiz padrão = 60 g + 90 ml ox 20 vol"). Do contrário, ninguém registra.

### Gaps
- Não achei modelo brasileiro oficial de ficha técnica de coloração (Senac, ABSB ou fabricante) nem regra sanitária (Anvisa ou vigilância municipal) que obrigue o registro.
- Não achei estatística de reações alérgicas a coloração no Brasil.

---

## 6. Serviços típicos, duração, intervalo de retorno e preços (Brasil, 2025)

### Takeaway
No pequeno negócio, o faturamento vem sobretudo de **manicure e pedicure** (carro-chefe de 16%) e **alisamentos** (progressiva e botox, 15%), seguidos de corte (14%). Em salões de BH, os preços médios de 2025 eram cerca de R$ 139 para corte feminino, R$ 73 para escova, R$ 229 para progressiva, R$ 136 para tintura, R$ 142 para hidratação, R$ 34 para manicure e R$ 210 para maquiagem. A variação entre bairros chega a 800%. Os intervalos de retorno (coloração de 4 a 6 semanas, mechas de 3 a 4 meses) são a base para lembretes de recorrência.

### Cited Findings
**Mix de faturamento (MEIs SP, 2025)**
- Carro-chefe: manicure e pedicure 16%, alisamento (progressiva, botox) 15%, corte 14%, limpeza de pele e peeling cerca de 11%, coloração, luzes e mechas cerca de 10%, hidratação, nutrição e reconstrução cerca de 7%, escova e modelagem cerca de 4%, sobrancelha cerca de 4% e maquiagem cerca de 1%. Os números do meio da lista foram lidos de gráfico com rótulos embaralhados na extração do PDF; os três primeiros constam no texto-resumo.
- **76% vendem produtos**, e para quem sabe estimar, a revenda é em média **26% do faturamento**.

Fonte: [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).

**Preços médios em salões de Belo Horizonte (Mercado Mineiro, 13 a 16/10/2025)** — [Diário do Comércio](https://diariodocomercio.com.br/?p=530609)

| Serviço | Preço médio | Variação maior/menor |
|---|---|---|
| Corte feminino | R$ 139,42 | 836% |
| Escova | R$ 72,87 | 350% |
| Escova progressiva | R$ 228,97 | 245% |
| Hidratação | R$ 141,72 | 840% |
| Reconstrução | R$ 199,41 | 290% |
| Tintura | R$ 136,06 (o texto também cita R$ 130,28) | 880% |
| Manicure | R$ 34,00 | 77% |
| Pedicure | R$ 34,13 | 77% |
| Mão e pé | R$ 66,40 | 88% |
| Spa dos pés | R$ 106,73 | 122% |
| Maquiagem | R$ 209,77 | — |
| Depilação completa | R$ 203,33 | 56% |
| Corte masculino | R$ 69,12 | 400% |

**Outras referências de preço**
- Faixas indicativas nacionais: corte e manicure/pedicure por volta de R$ 50, coloração a partir de R$ 80, progressiva a partir de R$ 150 — [Cronoshare](https://www.cronoshare.com.br/quanto-custa/salao-beleza).
- Salões de bairro em SP: progressiva a R$ 97 — [Booksy, Studio Lumina SP](https://booksy.com/pt-br/383225_studio-lumina_saloes-de-beleza_1047773_sao-paulo); combo pé e mão a R$ 75 — [Booksy, FS Espaço Beleza](https://booksy.com/pt-br/249947_fs-espaco-beleza_saloes-de-beleza_944115_taboao-da-serra).
- **Noiva**: maquiagem e penteado de R$ 800 a R$ 3.000; pacote "Dia da Noiva" de R$ 1.800 a R$ 5.500, com massagem, manicure, almoço e fotos — [Cronoshare, noiva](https://www.cronoshare.com.br/quanto-custa/maquiagem-penteado-noiva). Dia de noiva simples de R$ 400 a R$ 1.000 em capitais em 2025, e o teste pode ser incluso ou cobrado à parte — [Catraca Livre](https://catracalivre.com.br/noticias/quanto-custa-realizar-o-sonho-do-dia-de-noiva-com-atendimento-no-hotel/). As faixas são inconsistentes entre as fontes.

**Intervalos de retorno**
- Cor única: retoque de raiz a cada 3 a 6 semanas — [Garnier ES](https://www.garnierusa.com/es/necesidades-de-coloracion/retoque-de-raices).
- Mechas e luzes: cada 4 a 12 semanas conforme o contraste (Garnier). Especialista recomenda "a cada 3 meses", podendo chegar a **6 meses** quando a raiz é natural — [Beleza na Web, quando retocar as luzes](https://www.belezanaweb.com.br/loucas-por-beleza/quando-retocar-as-luzes/). Colorista que faz luzes a cada quatro meses — [Metrópoles](https://www.metropoles.com/que-beleza/como-retocar-mechas-loiras-sem-detonar-o-cabelo).
- Shadow root e raiz esfumada: visitas de 4 semanas passam para 2 a 3 meses — [Beleza na Web, raiz esfumada](https://www.belezanaweb.com.br/loucas-por-beleza/raiz-esfumada-a-tecnica-ideal-para-um-visual-mais-natural/).
- Muitos brancos: há relato de retoque a cada 10 dias (caso extremo) — [Catraca Livre](https://catracalivre.com.br/saude-bem-estar/tenho-cabelo-branco-e-preciso-retoca-lo-a-cada-10-dias-para-mim-e-importante-manter-a-cor-cuidada-e-uniforme-por-isso-tento-ser-constante/).

### Inferences
- **Durações e retornos típicos.** São conhecimento de domínio **não verificado por fonte nesta pesquisa** e servem de default configurável no sistema:

| Serviço | Duração típica | Pausa de química dentro | Retorno típico |
|---|---|---|---|
| Corte feminino | 30–60 min | — | 6–10 semanas |
| Escova | 30–60 min (depende do comprimento) | — | semanal (clientes de escova fixa) |
| Hidratação, nutrição, reconstrução | 30–60 min | 10–20 min de pausa | 7–15 dias (cronograma capilar de 4 semanas) |
| Coloração global | 1h30–2h | 30–45 min | — |
| Retoque de raiz | 1h–1h30 | 30–40 min | 4–6 semanas |
| Mechas, luzes, balayage | 3–6 h | de 30 a 50 min por etapa de descoloração, mais tonalização | 3–6 meses |
| Progressiva, botox, selagem | 2–4 h | aplicação + pausa + escova e prancha | 3–4 meses |
| Manicure | 40–60 min | — | 7–15 dias |
| Pé e mão | 1h–1h30 | — | 7–15 dias |
| Sobrancelha (design ou henna) | 20–40 min | — | 15–30 dias |
| Maquiagem social | 45–60 min | — | evento |
| Dia da noiva | 4–8 h, várias profissionais e às vezes atendimento externo | — | teste 30–60 dias antes |

- **Cronograma capilar** (hidratação, nutrição e reconstrução alternadas) é um **pacote recorrente** natural para venda antecipada.
- **Recorrência é o motor**: manicure quinzenal, escova semanal e raiz mensal. O sistema deve gerar **lembrete de retorno por cliente e serviço** com base no intervalo real dela, não só no padrão.
- A precificação com variação de até 800% reforça a necessidade de uma **calculadora de preço por serviço**: custo de produto em gramas, mais tempo do profissional, mais rateio do fixo, mais taxa de cartão, mais comissão e mais margem.

### Gaps
- Não achei pesquisa de preços 2025-2026 para **mechas, luzes e balayage**, **sobrancelha** e **dia da noiva** com metodologia; só faixas de agregadores (Cronoshare, Catraca Livre).
- Não achei fonte que dê duração padrão dos serviços; a tabela acima é inferência.
- Os preços de BH são de uma cidade; faltam dados nacionais comparáveis de 2025-2026.

---

## 7. Estoque: uso interno (fracionado, por dose) versus revenda

### Takeaway
O salão tem dois estoques com lógicas diferentes. O **uso interno** (back-bar) é consumido em frações (gramas de tinta, ml de oxidante) e é onde estão o desperdício e o desvio. A **revenda** (home care) é unitária e responde por cerca de 26% do faturamento em quem vende. A maioria controla mal os dois: só descobre a falta no meio do atendimento e não sabe quanto produto cada serviço consome.

### Cited Findings
- Documento técnico do Sebrae: o estoque serve tanto ao **consumo interno** (tintura usada em mechas) quanto à **revenda**. Erro de estimativa imobiliza caixa em prateleira — [Sebrae, nota técnica](https://bibliotecas.sebrae.com.br/chronus/ARQUIVOS_CHRONUS/bds/bds.nsf/6E4121F67B0DF6978325783400495136/$File/NT0004535A.pdf).
- Sebrae-PE (material antigo): excesso de uso e desperdício são comuns e o controle do uso de material é o ponto mais fraco — [Sebrae, Boas Práticas no Segmento de Beleza](https://datasebrae.com.br/wp-content/uploads/2020/04/Boas-Práticas-no-Segmento-de-Beleza-MMP14040-2.pdf). Recomenda ficha de estoque em planilha ou sistema — [Data Sebrae, Organização e Controle de Estoque](https://datasebrae.com.br/wp-content/uploads/2024/06/Organizacao-e-Controle-de-Estoque-CS11002-3.pdf).
- Data Sebrae-SP 2025:
  - **43% dizem que "não há desperdício"**, o que é provavelmente subestimado;
  - o principal desperdício declarado é o **uso excessivo de produtos por atendimento (23%)**;
  - seguem embalagens mal aproveitadas (cerca de 22%), **compra em excesso e estoque parado** (cerca de 17%), problemas de armazenamento e **produtos vencidos** (cerca de 13%);
  - 76% vendem produtos, e a revenda é cerca de 26% do faturamento.

  Fonte: [Data Sebrae-SP 2025](https://datasebrae.com.br/wp-content/uploads/2025/11/Profissionais-de-Beleza-e-Estetica-v5.pdf).
- Pequenos salões só descobrem a falta de tinta ou esmalte **durante o atendimento** (artigo patrocinado Belasis) — [UAI](https://www.uai.com.br/?p=175719).
- Referência internacional (Salon Today, citada por fornecedor): o custo de back-bar deveria ficar em **5% a 8% da receita de serviços**, e salões sem gestão rodam com **10% a 14%**. Misturar back-bar e varejo num único "pool" impede saber se o problema é desperdício (excesso de aplicação, sem controle de porção) ou varejo. Contagem semanal leva de 15 a 30 min — [Rework, inventory management](https://resources.rework.com/pt/libraries/beauty-center-growth/inventory-management-beauty-centers).
- Sebrae-PR sugere montar **kits de home care** e promover produtos parados — [Sebrae PR, 6 dicas](https://sebraepr.com.br/comunidade/artigo/6-dicas-para-quem-tem-um-negocio-na-beleza). Há consultoria Sebraetec específica, "Gestão do Estoque no seu Salão de Beleza" — [Sebraetec BA](https://sebrae.com.br/Sebrae/Portal%20Sebrae/UFs/BA/Anexos/Lista%20de%20Solu%C3%A7%C3%B5es%20SEBRAETEC.docx).
- Planilhas gratuitas para salão só controlam quantidade, custo e preço de venda, **sem fracionamento** — [Planilha de Fluxo](https://www.planilhadefluxo.com.br/baixar/planilha-controle-financeiro-salao-beleza).
- Sistemas de ERP genéricos já suportam **saldo fracionado em gramas**, mas sem método de custeio para salão — [TOTVS TDN, estoque fracionado](https://tdn.totvs.com/download/attachments/235571271/TUZF80_SIGALOJA_ET_SUST_BRA.pdf?api=v2).

### Inferences
- **Modelo de dados**:
  - o produto tem **unidade de compra** (bisnaga de 60 g, frasco de 900 ml de oxidante, galão de 1 L de progressiva) e **unidade de consumo** (g ou ml);
  - o serviço tem uma **receita padrão** (ex.: retoque de raiz = 60 g de tinta + 90 ml de ox 20 vol + 5 ml de plex);
  - o profissional ajusta a quantidade real na ficha técnica;
  - a baixa é automática no estoque de uso interno.
- O relatório **consumo teórico vs. real** (por profissional e por serviço), cruzado com o inventário semanal, revela **desvio**: produto levado para atender em casa, uso pessoal ou excesso de aplicação. É uma dor clássica que nenhuma planilha resolve.
- **Revenda**: código de barras, comissão de venda por profissional, alerta de estoque mínimo e de **validade** (13% citam vencidos), curva ABC e kits.
- Há ainda a "**taxa de produto**" ou custo de química descontado da comissão do profissional parceiro: a ficha com gramas permite calcular isso de forma justa por atendimento, em vez de usar um percentual fixo.

### Gaps
- Não achei fonte brasileira com método de custeio por grama nem percentual de back-bar sobre a receita de salões brasileiros; o benchmark de 5% a 8% é norte-americano (Salon Today, via fornecedor).
- Não achei dados sobre desvio ou furto de produtos em salões brasileiros.

---

## 8. Citações e reclamações reais de donos e profissionais

### Takeaway
Encontrei poucas citações em primeira pessoa indexáveis. As melhores vêm de consultores e associações (Sebrae, ABSB) e de reportagens regionais. Fóruns como Reddit, grupos de Facebook e comentários de YouTube e Instagram não apareceram nas buscas e precisariam de pesquisa manual ou entrevistas.

### Cited Findings
- "uma das maiores reclamações que ouço dos gestores e donos de salão de beleza é que os profissionais não levam o trabalho a sério" (consultor) — [Sebrae PR](https://sebraepr.com.br/comunidade/artigo/salao-de-beleza-e-uma-empresa-11).
- "a mãe do dono do salão, ou a mãe do cabeleireiro faz o que quer no salão?" (mesmo texto, sobre falta de regras) — [Sebrae PR](https://sebraepr.com.br/comunidade/artigo/salao-de-beleza-e-uma-empresa-11).
- O presidente da ABSB, José Augusto Nascimento, chama a reposição de profissionais de problema que prejudica o salão e o profissional, que fica "desassistido" — [Agência Sebrae](https://agenciasebrae.com.br/?p=2737).
- "Dezembro é o mês de maior movimento nos salões" (proprietária, Curitiba) — [Tribuna PR](https://www.tribunapr.com.br/noticias/parana/procura-por-saloes-de-beleza-esta-grande/).
- Recomendação de "Comece a contar o tempo de pausa assim que terminar de aplicar a coloração" — [Wella](https://www.wella.com/br/veja-8-perguntas-sobre-cuidados-antes-de-pintar-o-cabelo).
- Uma cabeleireira de Curitiba teve o WhatsApp sequestrado e ficou sem trabalhar porque toda a agenda passava pelo app — [Band B](https://www.bandab.com.br/seguranca/whatsapp-invadido-cabeleireira-golpe-curitiba/).
- Cabeleireiros (EUA, Square) pedem que o sistema modele o tempo de processamento para permitir double booking na coloração — [Square Seller Community](https://www.sellercommunity.com/t5/Questions-How-To/Processing-time-Double-Booking-Questions/m-p/183934).

### Inferences
- A falta de vozes em fóruns abertos é coerente com o perfil do público, que se comunica em Instagram, WhatsApp e grupos fechados de Facebook. Para validar o produto, **entrevistas diretas** com 10 a 20 donos e profissionais e escuta de grupos como "Donos de Salão" no Facebook e cursos de gestão (Hotmart, ex.: "Gestão e alta performance para salão de beleza" — [Hotmart](https://hotmart.com/pt-br/marketplace/produtos/gestao-e-alta-performance-para-salao-de-beleza/X99556276E)) devem render mais que a busca na web.
- Reviews de concorrentes (Trinks, Avec, Belasis, Booksy, Salão99) na Play Store, App Store, Capterra e Reclame Aqui são uma fonte de dores provavelmente rica e não explorada aqui. Há página da Trinks no Capterra — [Capterra, Trinks](https://www.capterra.com/p/252863/Trinks/).

### Gaps
- Não houve resultado em Reddit (r/brasil, r/desabafos) para cabeleireiros e comissão.
- Não houve relatos indexados de "profissional saiu e levou as clientes".
- Comentários de YouTube e Instagram de educadores de gestão de salão não foram acessíveis por busca.
- Não consultei reviews de apps concorrentes (Play Store, Reclame Aqui), recomendados como próxima etapa.
- Não encontrei conteúdo da revista Cabelos & Cia nem dados da ABIHPEC específicos de salão.
