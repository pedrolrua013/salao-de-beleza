# Inventário de funcionalidades dos sistemas brasileiros de gestão de salão (2025-2026)

> Escopo: Trinks, Avec (inclui Salão VIP / Beleza Soft), Belasis, Gendo, AppBarber/AppBeleza, Booksy Brasil, Fresha, Simples Agenda, Cash Barber, AgendaPro, Minha Agenda. Foco em COMO os recursos funcionam. A Trinks tem a central de ajuda pública mais detalhada (ajuda.trinks.com) e por isso é a referência mais profunda deste documento. Pesquisa feita em out/2026.

## 1. Comanda / checkout / caixa / maquininha / Pix

### Takeaway
A Trinks tem o fluxo de comanda/fechamento mais documentado: comanda numerada (faixa configurável), fechamento com cliente + débito/crédito + serviços/produtos/pacotes/vale-presente/cupom + "produtos usados no serviço", "pagar depois" (dívida), Pix integrado com QR Code e integração Stone. A Avec diferencia-se pelo split na maquininha própria (Avec Pay) com liquidação diária na conta do profissional; a Booksy tem checkout na agenda, Tap to Pay, gorjeta por profissional e caixa diário.

### Cited Findings
**Trinks – comanda**
- Habilitação em Configurações > Configurações gerais: "Meu estabelecimento trabalha com controle de comandas" + faixa de numeração (ex.: 1 a 500). Só perfis administrador e recepção abrem comanda; em Agenda > Agenda por Cliente > "Abrir/Lançar Comanda" o sistema mostra o 1º número livre, o maior aberto e o último usado no dia; clicar no card de agendamento confirmado também abre a comanda; comanda só de produtos pode ser aberta sem nome do cliente — [Trinks Ajuda – Comandas](https://ajuda.trinks.com/comandas)
- Opções: alerta que impede fechar conta com serviço não "Finalizado"; notificação se novos serviços forem lançados durante o fechamento; impressão automática "ao abrir comanda"; impressão detalhada com valores dos produtos usados em cada serviço; cancelar comanda libera o número mas mantém os serviços; "Relatório de Cliente em Débito" lista comandas abertas; busca por número da comanda — [Trinks Ajuda – Comandas](https://ajuda.trinks.com/comandas)

**Trinks – tela de fechamento de conta**
- Cabeçalho do cliente: nome, CPF, etiquetas, telefones, e-mail, nº comanda, aniversário, ano de cadastro, última visita, total de visitas, gasto médio e pontos de fidelidade ("Carregar pontos"/"Adicionar pontos") — [Trinks Ajuda – Fechar conta](https://ajuda.trinks.com/como-fechar-a-conta-dos-clientes)
- Indicadores "Valor em Débito" (vermelho, dívida; abre histórico) e "Valor em Crédito" (azul, pago e não consumido) — [Trinks Ajuda – Fechar conta](https://ajuda.trinks.com/como-fechar-a-conta-dos-clientes)
- Botões: Pagar dívidas (total ou parcial), Serviços (com "+" para incluir assistente), Produtos (lista de "Ações Rápidas" ao passar o mouse), Pacotes (mostra pacotes já comprados para consumir ou "Vender pacote cadastrado"), Vales presente, Cupom (código aplica % cadastrado). Preço editável clicando no valor; "Desconto" com valor + motivo e opção "Replicar para todos" (apenas o mesmo tipo de item) — [Trinks Ajuda – Fechar conta](https://ajuda.trinks.com/como-fechar-a-conta-dos-clientes)
- Menu de três pontinhos do serviço: editar serviço, editar baixa automática, retirar deste fechamento, retirar e cancelar serviço; "Produtos usados nos serviços" mostra uso interno + baixa automática — [Trinks Ajuda – Fechar conta](https://ajuda.trinks.com/como-fechar-a-conta-dos-clientes)
- "Pagar depois": quando fica saldo em dívida, a comissão é gerada sobre o valor total do agendamento, independentemente do valor pago — [Trinks Ajuda – Pagar depois](https://ajuda.trinks.com/pagar-depois); [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao)
- Pix Integrado (mar/2026): opção "Pix (Integrado)" no fechamento gera QR Code com validade de 5 min e confirma pagamento em tempo real; vale para serviços, produtos, pacotes e crédito de cliente; estorno via integração Pagar.me; chave Pix pode ser enviada por WhatsApp — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Integração Stone: aba "Transação (Stone)" na Agenda de Recebíveis mostra cada venda da maquininha para conciliação (jan/2026); aba "Transferência" para contas Connect Pagar.me permite solicitar transferência do saldo (fev/2026) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Autoatendimento: o cliente visualiza e paga produtos avulsos lançados na comanda junto com os serviços (fev/2026) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Proteção: nova permissão impede estorno de fechamentos com NFS-e pendente/emitida/rejeitada; status da nota aparece em "Ver fechamento" (out/2026) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- "Taxa da Comanda": valor fixo descontado do fechamento após o cálculo da comissão, para cobrir custos operacionais (set/2026) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Webhook de Fechamento de Conta com valores, descontos, formas de pagamento e totais; API pública com endpoints de Profissionais, Clientes e Comissões — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)

**Avec**
- Caixa: Financeiro > "Caixas Abertos" > botão "Sangria" > valor, data e motivo; conforme o motivo escolhe "Registrar saída no financeiro" ou "Registrar desconto para Profissional" (sangria vira vale do profissional) — [Central de Ajuda Avec – Sangria](https://sites.google.com/hyperlocal.com.br/central-de-ajuda-avec/financeiro/caixas/como-adiciono-uma-sangria-ao-caixa)
- Avec Pay: recebe por maquininha, conta digital e cartão, com conciliação no mesmo sistema; split no momento do pagamento na maquininha — [Avec Negócios](https://negocios.avec.app/); [Avec Split](https://negocios.avec.app/split-de-pagamentos-para-salao-e-clinica)

**AppBarber/AppBeleza**
- Cada agendamento gera uma comanda onde se acrescentam serviços e produtos; comanda só de produtos é possível; descontos, divisão de pagamento, parcelamento e escolha da forma de pagamento; pagamento online pelo app do cliente — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)

**Booksy**
- Checkout direto da agenda; pagamentos online, Tap to Pay no celular ou Booksy Card Reader; caixa calcula totais do dia, entradas, retiradas e formas de pagamento; repasse grátis no próximo dia útil ou em até 30 min com Fast Payouts; gorjeta no checkout com taxas padrão ajustáveis por profissional; processamento e hardware não inclusos na assinatura — [Booksy Biz Features](https://biz.booksy.com/features)

**Simples Agenda**
- Vendas geradas a partir do cadastro do cliente; formas: boleto, crédito, débito, dinheiro, cheque; emissão de boletos (paga-se só pelos boletos pagos), carnê de pagamento, NFS-e — [Simples Agenda Funcionalidades](https://www.simplesagenda.com.br/site/Funcionalidades/)

### Inferences
- Padrão de mercado: comanda nasce do agendamento; fechamento consolida dívida/crédito do cliente; pagamentos múltiplos por comanda. Diferencial possível: Pix QR dinâmico nativo + conciliação automática (Trinks só lançou em 2026, sinal de que é demanda recente).
- O conceito de "crédito do cliente" (saldo pré-pago) e "dívida" (fiado) é central no Brasil e deve ser nativo no modelo de dados.
- Sangria que pode virar "desconto para profissional" (Avec) é um atalho útil de operação.

### Gaps
- Não encontrei documentação de como a Trinks lida com gorjeta e split de formas de pagamento no fechamento (a página não cobre). Abertura/fechamento de caixa da Trinks e AppBarber não documentados nas fontes lidas.
- Fresha no Brasil: não achei confirmação de Pix nem regras locais; a central de ajuda internacional diz que depósitos podem ser % ou valor fixo, com janela de reembolso configurável e cancelamento automático se o depósito não for pago — [Fresha Help](https://www.fresha.com/help-center/knowledge-base/payments/101660-set-up-payment-policies) (não confirmado para BR).

## 2. Comissões, vales, adiantamentos e Salão Parceiro

### Takeaway
A Trinks tem o motor de comissão mais completo publicamente documentado: % por serviço×profissional, % de revenda por produto, % de venda de pacote, assistente em linha separada, desconto da taxa de cartão com 4 modos de rateio, custo operacional antes ou depois da comissão, taxa administrativa, recebíveis/abatimentos adicionais, adiantamento com nova data de liberação, e extrato com assinatura. A Avec leva comissão ao extremo com split na maquininha e "Vale Rápido" (antecipação pedida pelo app do profissional).

### Cited Findings
**Trinks**
- Configuração em Financeiro > Pagamento de Profissionais > Configurações adicionais de comissões: nomenclatura personalizável (o termo aparece no App Pro); comissão liberada na data do fechamento ou na data prevista de recebimento; desconto da taxa da operadora; custo operacional com 2 métodos (abater antes ou depois de calcular a comissão; não se aplica a assistentes); recebíveis adicionais (bônus) e abatimentos adicionais; resumo impresso com campo de assinatura e mensagem personalizada, cópia ao responsável financeiro — [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao)
- Regras: % por serviço na tela de Serviços (ícone de profissional) ou na aba "Serviços" do cadastro do profissional; % de comissão de revenda no produto; % sobre venda no pacote (comissionado na hora da venda) — [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao); [Trinks – Comissionamento de Pacote](https://ajuda.trinks.com/comissionamento-de-pacotes)
- Assistente: serviço aparece duas vezes no relatório (profissional e assistente), cada um com sua comissão — [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao)
- Taxa da Operadora (jan/2026): rateio da taxa do cartão entre profissional, assistente e estabelecimento — proporcional, tudo dos profissionais/assistentes, dividir igualmente ou personalizado; integrado à calculadora, relatório e App Pro — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Taxa Administrativa (jun/2026): desconto antes do cálculo, reduz a base; Taxa da Comanda (set/2026): valor fixo após cálculo — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Adiantamento: Financeiro > Pagamento de Profissionais > Adiantamento de comissões > seleciona profissional e itens > "Adiantar Comissões Selecionadas" > define nova data de liberação e % de desconto opcional (cobrança pelo adiantamento) — [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao)
- Vales: produtos comprados pelo profissional com desconto em comissão e abatimentos aparecem como descontos — [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao)
- Relatório de Comissões (colunas): Valor, Desconto Cliente, Desconto Operadora, Custo Operacional (produtos baixados e descartáveis), Valor Base Comissão, % Comissão, Valor Comissão, Recebíveis adicionais, Descontos, Total a Pagar; descontos podem ser configurados para não impactar a comissão — [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao)
- Exportação ganhou coluna "Custo de produtos (baixa)" separada (out/2026); API GET /v1/comissoes (filtros por data de liberação, atendimento/venda, pagamento/estorno, status) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Fechamento Mensal para profissionais com salário fixo; valores do mês ficam congelados — [Trinks – Fechamento Mensal](https://ajuda.trinks.com/fechamento-mensal); [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- "Profissional-Parceiro" aparece ligado à emissão de NF no ajuda Trinks, mas não achei artigo específico de comissão de parceiro — [busca ajuda.trinks.com](https://ajuda.trinks.com/comissao)

**Avec**
- Split na maquininha Avec Pay: divide estabelecimento × profissional imediatamente após a transação, inclusive vendas com vários profissionais e pagamentos mistos (dinheiro + cartão); taxas repassadas conforme % de comissão; liquidação ao fim do dia na "Avec Conta" de cada profissional, já líquida; profissional notificado no app Avec PRO — [Avec Split](https://negocios.avec.app/split-de-pagamentos-para-salao-e-clinica)
- Apresentado como desenhado para a Lei do Salão-Parceiro; afirma que o salão tributa e emite NF só sobre sua cota-parte — [Avec Split](https://negocios.avec.app/split-de-pagamentos-para-salao-e-clinica). Atenção: fontes jurídicas dizem que o salão emite documento fiscal unificado ao consumidor discriminando as cotas-parte, e o profissional emite nota ao salão pela sua cota — [Sebrae](https://sebrae.com.br/sites/PortalSebrae/semanadomei2019/conteudos/salao-parceiro-tire-suas-duvidas,f2ff103bc7d1b610VgnVCM1000004c00210aRCRD); [Meu Contador Online](https://www.meucontadoronline.com.br/blog/salao-parceiro-o-que-e-como-formalizar-o-seu-negocio/)
- Vale Rápido: profissional solicita antecipação de ganhos pelo app Avec PRO — [Avec Esmalteria](https://negocios.avec.app/avec-esmalteria)

**Outros**
- AppBarber: comissão por serviço e/ou produto, vales e "comandas de consumo de profissionais" — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/); comissões específicas para serviços do clube de assinatura — [AppBarber Zendesk](https://appbarber-appbeleza.zendesk.com/hc/pt-br/articles/7293049272845-Comiss%C3%B5es-do-clube-de-assinatura-Como-configurar)
- AgendaPro: relatórios de comissão automáticos para profissionais — [AgendaPro](https://agendapro.com/en/beauty/beauty-salon-software)
- Gendo: comissão automática a partir do plano Essencial (R$ 69,90/mês) — [Gendo Planos](https://www.gendo.app/br/planos)
- Contexto legal Salão Parceiro: contrato escrito homologado por sindicato/órgão do trabalho, com % de cada parte; salão retém e recolhe tributos do parceiro; cota-parte do parceiro não compõe a receita bruta do salão; regras de NFS-e variam por município (ex.: Jundiaí permite NFS-e única por parceiro em regime especial; SP IN SF/SUREM 11/2025 exige CNPJ do profissional e valor repassado na discriminação) — [Econet](https://blog.econeteditora.com.br/trabalhista-salao-parceiro); [Prefeitura Jundiaí](https://jundiai.sp.gov.br/casa-civil/wp-content/uploads/sites/6/2021/08/29-648.pdf); [LegisWeb](https://www.legisweb.com.br/noticia/?id=31450); [Portal Contábil SC](https://portalcontabilsc.com.br/artigos/controversia-envolvendo-tributacao-pelo-iss-no-contexto-da-lei-dos-saloes-parceiros/)

### Inferences
- O "motor de comissão" precisa de: base (bruto/líquido), ordem dos descontos (taxa adm → custo produtos → taxa cartão), rateio da taxa do cartão, assistente, data de liberação (fechamento vs. recebimento), vales/adiantamentos com taxa. Isso é tabela de regras, não um único %.
- Oportunidade: Salão Parceiro "fim a fim" (gerar contrato, cota-parte, NFS-e unificada por município, nota do parceiro, recolhimento) — nenhuma fonte encontrada mostra um concorrente fazendo tudo isso de forma documentada.

### Gaps
- Não encontrei geração de contrato de parceria em nenhum produto. Detalhes de NF do Profissional-Parceiro na Trinks não lidos (artigo não localizado). Regras de comissão da Avec além do split não documentadas publicamente.

## 3. Ficha da cliente / anamnese / ficha técnica / fotos / consentimento

### Takeaway
É a área menos documentada pelos grandes. Simples Agenda tem modelos editáveis de anamnese/evolução com assinatura eletrônica e fotos antes/depois (página de estética). Não encontrei ficha técnica de química (fórmula/oxidante/tempo) documentada em Trinks, Avec, Belasis ou Gendo — lacuna clara.

### Cited Findings
- Simples Agenda: modelos prontos de Anamnese, Diagnóstico, Evolução e Exame Físico, editáveis (incluir/excluir itens) — [Simples Agenda Funcionalidades](https://www.simplesagenda.com.br/site/Funcionalidades/); anamnese digital com assinatura eletrônica e anexo de fotos antes/depois, histórico por sessão (página de clínica de estética) — [Simples Agenda Estética](https://www.simplesagenda.com.br/site/novo-sistema-clinica-de-estetica.php); FAQ sobre anamnese preenchida e assinada eletronicamente pela cliente — [Simples Agenda FAQ](https://www.simplesagenda.com.br/site/FAQ/index.php?cod_faq=76)
- Belasis: blog fala em anamnese digital preenchida antes/no início do atendimento — conforme resumo de busca; concorrente (Relinq) afirma que o Belasis não tem anamnese nativa — [Relinq](https://relinqbeauty.com.br/alternativa-ao-belasis) (fonte interessada; não verificado)
- Trinks: cadastro do cliente no fechamento mostra etiquetas, CPF, aniversário, última visita, total de visitas, gasto médio e pontos — [Trinks Ajuda – Fechar conta](https://ajuda.trinks.com/como-fechar-a-conta-dos-clientes)
- AppBarber: "rede social" no app do cliente para fotos antes/depois e selfies integradas ao Facebook — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)
- Um produto menor ("Meu Salão", meusalaoon.com.br) aparece em resumo de busca como registrando fórmula, oxidante e tempo por atendimento, anamnese antes da química e fotos com consentimento registrado, mas a página buscada não exibiu o conteúdo — [Meu Salão](https://meusalaoon.com.br/) (não verificado)

### Inferences
- Ficha técnica de química estruturada (marca/linha/nuance, gramas, oxidante em volumes, tempo de pausa, teste de mecha, alergias) + consentimento LGPD para fotos + linha do tempo visual é um diferencial real para salões de cor.

### Gaps
- Não encontrei documentação de anamnese/ficha técnica na Trinks, Avec, Gendo, Booksy ou AppBarber.

## 4. Estoque (uso interno × revenda, fracionado, baixa automática)

### Takeaway
A Trinks tem estoque fracionado completo: produto com unidade de consumo (un, cm, dose, g, mL), doses por unidade e preço por dose; baixa automática por serviço editável no fechamento; custo médio ponderado; inventário importável por CSV; custo da baixa descontado da comissão.

### Cited Findings
- Cadastro de produto fracionado: escolher consumo (unidade, cm, dose, grama ou mL), quantas doses cabem em uma unidade e preço por dose; baixa e valor cobrado dependem disso — [Trinks – Produto fracionado](https://ajuda.trinks.com/cadastro-de-produto-fracionado)
- Baixa automática editável por cliente no fechamento (menu três pontinhos > "editar baixa automática") para refletir a quantidade real usada — [Trinks – Editar baixa automática](https://ajuda.trinks.com/como-editar-baixa-autom%C3%A1tica-do-estoque-central-de-ajuda-do-trinks); [Trinks Ajuda – Fechar conta](https://ajuda.trinks.com/como-fechar-a-conta-dos-clientes)
- Configuração de saída automática: exibir valor cobrado do cliente, desconto da comissão, ambos ou nenhum (jul/2026) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Custo médio ponderado recalculado a cada compra de fornecedor (ago/2026); importação de inventário CSV que separa unidades inteiras e resto fracionado (mai/2026) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026); [Trinks – Inventário](https://ajuda.trinks.com/mas-primeiro-por-que-fazer-invent%C3%A1rio)
- Custo dos produtos baixados entra como "Custo Operacional" no cálculo da comissão; App Pro mostra desconto de produtos usados só se o salão usa baixa automática — [Trinks Ajuda – Comissão](https://ajuda.trinks.com/comissao); [Trinks – App Profissional](https://ajuda.trinks.com/entenda-sua-comissao-rateio-no-aplicativo-trinks-profissional)
- Código de barras suportado — [Trinks – Código de barras](https://ajuda.trinks.com/codigo-de-barras-na-trinks)
- AppBarber: saldo, histórico de entradas/saídas, custo e lucro por produto, validade, valor do estoque, alerta de estoque baixo — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)
- Booksy: níveis, uso e localização de produtos, alertas de reposição — [Booksy Biz Features](https://biz.booksy.com/features)
- Gendo: estoque a partir do Essencial — [Gendo Planos](https://www.gendo.app/br/planos)

### Inferences
- Modelo vencedor: produto com dupla natureza (revenda e/ou uso interno), unidade de consumo fracionada, "ficha de consumo" padrão por serviço, ajuste real no fechamento, e custo repassado à comissão de forma transparente.

### Gaps
- Belasis e Avec não detalham fracionado publicamente.

## 5. Agendamento online, marketplace, Google/Instagram, sinal via Pix, cancelamento, lista de espera

### Takeaway
Sinal/pagamento antecipado virou padrão em 2026 (Trinks: 100% ou 10/20/30/50% via Pix ou cartão, agendamento só criado após aprovação; Booksy: depósito % por serviço e taxa de no-show com cartão; Belasis Pay e Gendo também). Google Reserve e botão do Instagram são comuns. Lista de espera automática existe em Booksy, AppBarber, Gendo, Minha Agenda.

### Cited Findings
- Trinks: pagamento antecipado obrigatório (100%) ou sinal de 10/20/30/50%, restante no local; agendamento só criado após aprovação de Pix ou cartão; em cancelamento, estorno ou conversão em crédito; antecedência mínima configurável (30 min a 2 dias) para hotsite, portal, app, framebusca e Google Reserve; dashboard de Pagamentos Online (faturamento, ticket médio, taxa de no-show) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Trinks + Google (jun/2026): serviços, preços, duração e horários no Google; horário chega pré-selecionado no fluxo — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Trinks Agenda Offline (agendaoffline.trinks.com, PWA instalável) consulta horários, clientes, status e lista de espera sem internet; confirmação em lote de até 10 agendamentos do mesmo cliente no dia; visibilidade de agendas por profissional/assistente — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Booksy: agendamento via perfil, Instagram ("Book Now"), Google (Reserve with Google), Facebook, QR Code, widget; regras de antecedência; lista de espera automatizada por janela de horário; tempo de processamento (ex.: coloração) e atendimento paralelo; importação de calendários Google/Apple; depósito com % por serviço; política de cancelamento publicada no perfil; taxa de cancelamento/no-show com cartão cadastrado — [Booksy Biz Features](https://biz.booksy.com/features)
- Booksy Brasil: termos preveem cancelamento com ≥4 horas úteis; alguns estabelecimentos exigem cartão para garantir horário — [Booksy Termos BR](https://booksy.com.br/termos-de-servico/); Boost = 30% da primeira visita de cliente novo vindo do marketplace, sem mensalidade extra — [Booksy Biz Google Play](https://play.google.com/store/apps/details?id=net.booksy.business&hl=en_US); assinatura citada a R$ 99/mês e queda de ~25% em desistências atribuída à multa por no-show — [Cardoso Adv. (reprodução de reportagem)](https://cardosoadv.com.br/com-aporte-de-us-70-mi-americana-booksy-planeja-dobrar-operacao-no-brasil/)
- Gendo: pagamento parcial ou total para confirmar o agendamento; link de agendamento personalizado; app próprio do cliente; fila de espera que avisa automaticamente (a partir do plano Avançado); Pix a partir do Essencial — [Gendo LP](https://lp.gendo.com.br/sistema-de-agendamento); [Gendo Planos](https://www.gendo.app/br/planos)
- Belasis Pay: pagamento por sinal, cobrança recorrente, antecipação de recebíveis — [Belasis](https://www.belasis.com.br/sistema-para-barbearia)
- AppBarber: agendamento embutido no site/Facebook; site do estabelecimento indexável; lista de espera por dia com notificação — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)
- Salão VIP: portal/marketplace onde clientes consultam agenda de salões parceiros e marcam; ligado ao ecossistema Avec (Avec Pay, Hair Solution) — [Gazeta do Povo](https://www.gazetadopovo.com.br/economia/empreender-pme/aos-27-anos-empresaria-a-frente-da-beauty-week-fatura-milhoes-no-setor-de-beleza-acek2rpzoeiqohlk4hr5uwoy3/); Beleza Soft agora é Avec — [Beleza Soft](https://belezasoft.com/)
- Minha Agenda: agendamento online, expediente especial, turnos, lista de espera, agendamento de pacote multi-serviço — [App Store](https://apps.apple.com/BR/app/id1485713642)

### Inferences
- Sinal com Pix + conversão em crédito no cancelamento é o padrão a copiar; dashboard de no-show prova o ROI ao dono.

### Gaps
- Fresha Brasil: não confirmei Pix/depósito no BR. Site salaovip.com.br não carregou (erro de certificado).

## 6. WhatsApp: lembretes, confirmação, campanhas, aniversário, retorno, IA

### Takeaway
Trinks usa "Rotina de mensagens" (confirmação 24h antes, lembrete 1h antes, avaliação após fechamento, convite de retorno configurável, aniversário) consumindo créditos; IA conversacional é via parceiros (NeoHug, Lucy.IA). Avec (Avec IA), Gendo (Gendo Zap/GAIA), Cash Barber (Cash.IA) e Belasis já vendem IA própria no WhatsApp que agenda/remarca.

### Cited Findings
- Trinks Rotina de mensagens: confirmação, lembrete e avaliação; envia só para agendamentos já na agenda antes do horário da rotina; confirmação 24h antes, lembrete 1h antes; status de confirmação aparece no card; o WhatsApp da Trinks não recebe agendamentos — [Trinks – Rotina](https://ajuda.trinks.com/o-que-%C3%A9-a-rotina-de-mensagens); [Trinks FAQ Rotina](https://ajuda.trinks.com/faq-rotina-de-mensagens-central-de-ajuda-do-trinks)
- 2026: avaliação no fechamento da conta, máx. 1 por cliente/dia, rotina consome 1 crédito por cliente por dia; cada mensagem ativável separadamente — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Convite de retorno com critérios (ex.: sem agendar há 45 dias; fez corte nos últimos 90 dias e não voltou), por e-mail/SMS/WhatsApp; pesquisa de satisfação com estrelas e comentários em relatório; mensagem de aniversário e "Lembrete Premium" — [Trinks Comunicação](https://negocios.trinks.com/solucoes/comunicacao-para-ir-alem/)
- Relatório de clientes que não retornaram (filtro por status do serviço) — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- IA via parceiros Trinks: NeoHug (CRM com IA que marca/remarca), Lucy.IA (recepcionista que agenda, confirma, pede avaliações no Google) — [Trinks de Vantagens](https://sistema.trinks.com/trinks-de-vantagens/parceiros); [Recepção Automática blog](https://blog.recepcaoautomatica.com.br/post/ia-no-whatsapp-trinks-ferramenta-automatiza-salao)
- Avec IA: clientes agendam/remarcam/cancelam pelo WhatsApp; IA confirma, reorganiza a agenda, preenche horários vagos, 24h, personalizada ao salão; também "Marketing IA" — [Avec Negócios](https://negocios.avec.app/)
- Gendo: lembretes por WhatsApp com franquia por plano (100/300/500/1.200 por mês) e pacotes extras; Gendo Zap (IA no WhatsApp que faz agendamentos) como adicional pago; IA "GAIA" e "Gendo no ChatGPT e no Claude" nos planos Avançado+ — [Gendo Planos](https://www.gendo.app/br/planos); [Gendo LP](https://lp.gendo.com.br/sistema-de-agendamento)
- Cash Barber: Cash.IA no WhatsApp para confirmações, lembretes, pedidos de avaliação e lembretes de retorno; alertas de clientes que param de voltar — [Cash.IA](https://cashia.cashbarber.com.br/); [Cash Barber](https://sistemacashbarber.com.br/)
- Belasis: IA integrada aos envios de mensagens para recuperar clientes; "CRM para Chrome" centralizando conversas — [Belasis](https://www.belasis.com.br/sistema-para-barbearia)
- AgendaPro: lembretes 1, 2 ou 3 dias antes por WhatsApp/SMS/e-mail; cliente confirma ou cancela por botão e a agenda atualiza; 50 lembretes/mês no plano de entrada — [AgendaPro](https://agendapro.com/en/beauty/beauty-salon-software)
- AppBarber: push + e-mail de lembrete, SMS; mensagens automáticas de retorno X dias após um serviço; notícias/promoções com rastreio de quem leu — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)
- Minha Agenda: WhatsApp para lembretes, confirmações, aniversário, lembrete de todos os agendamentos do dia — [App Store](https://apps.apple.com/BR/app/id1485713642)
- Booksy: lembretes ilimitados; campanhas prontas; envio em massa por e-mail/SMS segmentado por tags; Flash Sales, Happy Hours, descontos de última hora; criador de posts para redes — [Booksy Biz Features](https://biz.booksy.com/features)

### Inferences
- Precificação por crédito/franquia de WhatsApp é o padrão (custo da API Meta). IA que agenda pelo WhatsApp é o principal campo de batalha 2025-2026; Trinks ainda terceiriza.
- "Retorno por serviço" (ex.: corte a cada 30 dias, coloração a cada 45) é melhor que regra genérica de 45 dias.

### Gaps
- Não encontrei detalhes de como Avec IA lida com handoff humano, nem preços dos módulos de IA.

## 7. Pacotes, assinaturas/clube, fidelidade/cashback, vale-presente

### Takeaway
Clube de assinatura com cobrança recorrente no cartão é padrão (Trinks, AppBarber, Avec, Belasis, Gendo, Cash Barber). Trinks tem gestão de clube madura (status, indicador colorido na agenda/comanda). Fidelidade por pontos existe (Trinks, AppBarber, Minha Agenda); cashback quase não aparece documentado.

### Cited Findings
- Trinks Clube: plano com página própria; benefícios podem ser serviços, produtos e pacotes; permissão para criar/editar/inativar; abas "Venda e renovação" e "Todas as assinaturas" com filtros (status, canal, tipo de venda, próximo pagamento hoje/semana/mês) e export Excel; status "Com pendências"/"Bloqueada para edições" (bloqueio de 30 dias após alteração); indicador do Clube na Agenda e na Comanda: verde (ativa), amarelo (atrasada), cinza (cancelada/benefícios esgotados), clicando mostra benefícios e consumo — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026); exemplo de plano "2 cortes + 1 barba/mês" — [Trinks Comunicação](https://negocios.trinks.com/solucoes/comunicacao-para-ir-alem/)
- Trinks Pacotes: consumo no fechamento; pacotes personalizados compartilháveis entre unidades da franquia (consumo, comissão e financeiro seguem a unidade do atendimento); comissão de pacote na venda — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026); [Trinks – Comissionamento de Pacote](https://ajuda.trinks.com/comissionamento-de-pacotes)
- Trinks: vale-presente e cupom no fechamento; pontos de fidelidade no cadastro — [Trinks Ajuda – Fechar conta](https://ajuda.trinks.com/como-fechar-a-conta-dos-clientes)
- AppBarber: Clube de Assinaturas (Cadastros > Clubes de Assinatura) com cobrança recorrente no cartão, associado automaticamente à comanda; Clube de Clientes (desconto fixo por grupo aplicado no agendamento); cliente só participa de UM benefício por vez (clube de clientes, assinatura ou pacote); não retroativo — [AppBarber – Clube de Clientes](https://appbarber-appbeleza.zendesk.com/hc/pt-br/articles/360016053671-Como-funciona-o-Clube-de-Clientes); [AppBarber – Clube de Assinaturas](https://appbarber-appbeleza.zendesk.com/hc/pt-br/articles/360006756552-Como-funciona-o-Clube-de-Assinaturas); programa de pontos com resgate pelo app; pacotes com controle de sessões usadas — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)
- Cash Barber: foco em barbearia por assinatura ("corte ilimitado"), gerador de preço de assinatura, controle de frequência do clube, dashboards de retenção/ticket/frequência; a partir de R$ 300/mês com cursos e mentoria — [Cash Barber](https://sistemacashbarber.com.br/); [LP Cash Barber](https://lp-aws.sistemacashbarber.com.br/); reclamações sobre cancelamento/cobranças extras, 78,3% de resolução — [Reclame Aqui](https://www.reclameaqui.com.br/empresa/cash-barber/)
- Gendo: clube de assinatura "sem taxa da Gendo" a partir do Essencial; pacotes — [Gendo Planos](https://www.gendo.app/br/planos)
- Booksy: memberships com visitas ilimitadas e serviços incluídos; pacotes multi-sessão; vale-presente vendido online com saldo aplicado no checkout — [Booksy Biz Features](https://biz.booksy.com/features)
- Avec: Clube de assinaturas e Fidelidade listados sem detalhe — [Avec Negócios](https://negocios.avec.app/)
- Minha Agenda: cartões fidelidade com desconto — [App Store](https://apps.apple.com/BR/app/id1485713642)

### Inferences
- Cashback nativo é lacuna visível no mercado de software de salão BR (redes como Unhas Cariocas fazem via app próprio).
- Regra "um benefício por vez" do AppBarber mostra a complexidade de empilhar descontos — definir política de precedência desde o início.

### Gaps
- Não encontrei documentação de cashback em nenhum dos produtos principais.

## 8. Relatórios / dashboards / KPIs da home

### Takeaway
Home da Trinks (jan/2026) tem cards de resumo da agenda, resumo financeiro, principais despesas e métricas do Clube, com versão específica para barbearia. Cash Barber foca retenção, ticket médio e frequência. Booksy tem 16 relatórios de vendas + performance da equipe.

### Cited Findings
- Trinks Nova Home: cards de agenda, financeiro, principais despesas, métricas do Clube; versão para barbearias — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Trinks Dashboard de Pagamentos Online: faturamento, ticket médio, taxa de no-show — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Cash Barber: retenção, ticket médio, frequência, alertas de clientes sumidos — [Cash Barber](https://sistemacashbarber.com.br/)
- AppBarber: agendamentos por dia da semana, faixa horária, plataforma de origem, mês — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)
- Booksy: 16 relatórios de receita/fluxo de caixa; performance por profissional — [Booksy Biz Features](https://biz.booksy.com/features)
- Avec: "Mapa de Calor", "Avec Lake" (base de dados inteligente), relatórios e indicadores — [Avec Negócios](https://negocios.avec.app/)
- Simples Agenda: vendas por cliente com soma por forma de pagamento e "Top 20 Clientes" — [Simples Agenda Funcionalidades](https://www.simplesagenda.com.br/site/Funcionalidades/)
- Minha Agenda: performance diária/mensal/anual, metas financeiras — [App Store](https://apps.apple.com/BR/app/id1485713642)

### Inferences
- KPIs mínimos da home: faturamento do dia/mês vs. meta, ocupação da agenda (mapa de calor), ticket médio, no-show, clientes novos vs. recorrentes, clientes sumidos, MRR do clube, comissões a pagar.

### Gaps
- Não encontrei a lista exata de KPIs da home da Avec ou Belasis.

## 9. App do profissional

### Takeaway
O App Trinks Profissional é o mais documentado: extrato diário/mensal com bruto, descontos, taxa, custo, %, líquido; datas de pagamento; lançamentos (gorjetas, bonificações, vales, split); produtos que comprou; gráfico de distribuição. Avec PRO mostra comissão em tempo real e permite pedir Vale Rápido.

### Cited Findings
- Trinks App Pro – Comissão/Rateio (se o salão habilitar): total do período; histórico diário por item (bruto, desconto cliente, taxa da forma de pagamento, custo de execução, %, total, data, nome do cliente); quadro de datas previstas de pagamento e parcelas; comissões manuais; indicador de split; visão mensal; "Total a receber" líquido de vales, split e produtos para uso próprio; "Ver lançamentos" (comissões, bonificações, gorjetas, produtos comprados, split, vales); "Produtos que você comprou"; gráfico serviços × produtos × pacotes — [Trinks – App Profissional](https://ajuda.trinks.com/entenda-sua-comissao-rateio-no-aplicativo-trinks-profissional)
- Trinks: profissionais podem excluir ausências pelo App Pro (iOS); salão pode remover dos profissionais o botão "Finalizar" atendimento — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- Avec PRO: notificação do split, histórico de serviços e saldo de comissões em tempo real, pedido de Vale Rápido — [Avec Split](https://negocios.avec.app/split-de-pagamentos-para-salao-e-clinica); [Avec Esmalteria](https://negocios.avec.app/avec-esmalteria)
- Booksy Biz: cada profissional vê e gerencia os próprios agendamentos; widget iOS com próximos agendamentos — [Booksy Biz Features](https://biz.booksy.com/features)

### Inferences
- Transparência total do cálculo (linha a linha) reduz conflito salão × profissional; antecipação self-service é monetizável (fintech).

### Gaps
- Telas de agenda/clientes do App Trinks Pro e do AppBarber profissional não documentadas nas fontes lidas.

## 10. Diferenciais / inovações observadas

### Takeaway
Principais ideias para copiar: split na maquininha com liquidação D+0 por profissional (Avec), antecipação de comissão pelo app (Avec Vale Rápido; Trinks com % de desconto), Pix QR integrado com estorno (Trinks), agenda offline PWA (Trinks), Gendo dentro do ChatGPT/Claude, API pública + webhooks (Trinks), Google Reserve com horário pré-selecionado, IA no WhatsApp que agenda (Avec, Gendo, Cash Barber).

### Cited Findings
- Agenda Offline PWA; API pública (Profissionais, Clientes com etiquetas, Comissões); webhook de fechamento — [Trinks Novidades 2026](https://ajuda.trinks.com/novidades-2026)
- "Gendo no ChatGPT e no Claude" nos planos Avançado/Profissional; app próprio da marca como adicional — [Gendo Planos](https://www.gendo.app/br/planos)
- Avec: +40 mil negócios; App Próprio White Label "em breve"; gestão de franquias multiunidade — [Avec Negócios](https://negocios.avec.app/)
- Belasis: CRM no Chrome para conversas; gerente de contas dedicado; importação assistida; suporte 24x7 — [Belasis](https://www.belasis.com.br/sistema-para-barbearia)
- AppBarber: rede social interna no app do cliente; pesquisa de satisfação pós-serviço — [AppBarber Funcionalidades](https://www.appbarber.com.br/funcionalidades/)
- Booksy: Flash Sales/Happy Hours para horários ociosos; criação de posts no app — [Booksy Biz Features](https://biz.booksy.com/features)
- Preços de referência: Gendo R$ 39,90 / 69,90 / 124,90 por mês (1, 1-2, 3-6 profissionais) — [Gendo Planos](https://www.gendo.app/br/planos); Minha Agenda R$ 22,90 a R$ 649,90 (periodicidade não informada), 4,9★ com ~22 mil avaliações — [App Store](https://apps.apple.com/BR/app/id1485713642); Booksy R$ 99/mês — [Cardoso Adv.](https://cardosoadv.com.br/com-aporte-de-us-70-mi-americana-booksy-planeja-dobrar-operacao-no-brasil/)

### Inferences
- Combinação ainda não vista documentada em um só produto: Salão Parceiro fiscal completo + ficha técnica de química + cashback + IA WhatsApp nativa.

### Gaps
- Não pesquisados por limite de tempo: BeautyApp, Agende-me, GENDA, Tua Agenda, Fresha Brasil (detalhes locais), AppBarber (central de ajuda retornou 403 em alguns artigos), Salão VIP (site com erro de certificado). AgendaPro: só páginas LATAM/EN, sem confirmação de plano BR.
