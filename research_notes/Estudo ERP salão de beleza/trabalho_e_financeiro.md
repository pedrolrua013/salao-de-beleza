# Modelos de trabalho, regras legais/tributárias e operação financeira de salões de beleza no Brasil (para ERP)

> Notas de pesquisa (out/2026). Fontes primárias consultadas: planalto.gov.br (Lei 13.352/2016), acórdão ADI 5625 (STF), CCT RJ 2023/2024. Grande parte do restante vem de blogs de contabilidade, de software de salão e de provedores de pagamento: são fontes comerciais e estão sinalizadas assim. Itens marcados com **[REFORMA]** mudam com a Reforma Tributária.

## 1. Lei do Salão Parceiro (Lei 13.352/2016): funcionamento, contrato, cota-parte, tributos, NF, homologação, riscos

### Takeaway
A Lei 13.352/2016 inseriu os arts. 1º-A a 1º-D na Lei 12.592/2012. O salão-parceiro **centraliza todos os recebimentos** do cliente, **retém sua cota-parte** e **retém e recolhe os tributos e contribuições** devidos pelo profissional-parceiro sobre a cota dele. A cota-parte do profissional **não integra a receita bruta do salão**, mesmo com documento fiscal unificado ao consumidor. O contrato precisa ser escrito, ter duas testemunhas e ser homologado no sindicato (ou, na falta dele, no órgão local do Ministério do Trabalho). O STF declarou o modelo constitucional (ADI 5625, 2021), mas o contrato é nulo quando mascara relação de emprego. Para o ERP, o que precisa sair certo é: o split da comanda em cota salão × cota profissional, a retenção e a NF/ISS apenas sobre a cota do salão.

### Cited Findings
**Texto legal (Lei 12.592/2012, com os arts. 1º-A a 1º-D incluídos pela Lei 13.352/2016)**
- Salões podem firmar contratos de parceria, por escrito, com cabeleireiros, barbeiros, esteticistas, manicures, pedicures, depiladores e maquiadores. O estabelecimento passa a se chamar "salão-parceiro" e o trabalhador, "profissional-parceiro" — [Planalto, Lei 13.352/2016](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- O salão-parceiro centraliza os pagamentos e recebimentos de todos os serviços prestados pelo profissional-parceiro. Retém a cota-parte percentual fixada em contrato e também os valores de tributos e contribuições sociais e previdenciárias devidos pelo profissional-parceiro — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- Natureza das cotas: a cota-parte do salão remunera o aluguel de bens móveis e utensílios e os serviços de gestão, apoio administrativo, escritório, cobrança e recebimento. A cota do profissional remunera os serviços de beleza — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- A cota-parte destinada ao profissional-parceiro **não integra a receita bruta do salão-parceiro**, ainda que adotado sistema de emissão de nota fiscal unificada ao consumidor (art. 1º-A, §5º) — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm); [Kontae (paráfrase do §5º)](https://www.kontae.com.br/blog/mei/faturamento-profissional-parceiro-mei)
- O profissional-parceiro não assume as responsabilidades e obrigações administrativas, contábeis, fiscais, trabalhistas e previdenciárias do salão — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- Formalidades: contrato escrito, assinado por duas testemunhas e homologado pelo sindicato da categoria profissional e laboral. Na ausência de sindicato, a homologação é feita pelo órgão local competente do Ministério do Trabalho, perante duas testemunhas — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- Cláusulas obrigatórias:
  - percentual das retenções do salão;
  - obrigação de o salão reter e recolher os tributos do profissional;
  - condições e periodicidade do pagamento, por tipo de serviço;
  - direitos de uso de bens e acesso ao espaço;
  - rescisão unilateral com aviso prévio mínimo de 30 dias;
  - responsabilidades com manutenção e higiene;
  - obrigação do profissional de manter a regularidade de sua inscrição perante as autoridades fazendárias.

  Fonte: [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- Enquanto vigente a parceria, não há relação de emprego nem de sociedade entre as partes — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- Art. 1º-B: o salão deve manter condições de trabalho e equipamentos adequados e cumprir as normas de saúde e segurança do art. 4º — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- **Art. 1º-C: configura-se vínculo empregatício** (i) se não houver contrato de parceria formalizado nos termos da lei, ou (ii) se o profissional-parceiro exercer funções diferentes das descritas no contrato — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)
- Art. 1º-D: a fiscalização e as multas seguem o Título VII da CLT — [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2016/lei/l13352.htm)

**Simples Nacional / receita bruta do salão-parceiro**
- A Resolução CGSN 140/2018 desconsidera, na receita bruta do salão-parceiro, os valores repassados ao profissional-parceiro, **desde que este esteja devidamente inscrito no CNPJ**. O dispositivo é citado como art. 2º, §5º, VI (ou art. 2º, II e §5º); há também a Solução de Consulta Disit/SRRF 5.004/2019 — [Fazenda Niterói, PA 023917.19](https://www.fazenda.niteroi.rj.gov.br/site/wp-content/uploads/2024/02/PA-023917.19-FLS.-210-A-217-E-2085-A-2108.pdf); [NetCPA – parcelas que não compõem a receita bruta](https://netcpa.com.br/colunas/simples-nacional-parcelas-que-nao-compoem-a-receita-bruta/6058)
- Pareceres municipais apontam que a dedução só passou a ser aceita no Simples após a LC 155/2016 alterar a LC 123/2006. O dispositivo da LC 123 é citado de forma inconsistente nas fontes (art. 13, §1º-A ou §5º), então a numeração precisa ser conferida — [Fazenda Niterói, PA 023918.19](https://www.fazenda.niteroi.rj.gov.br/site/wp-content/uploads/2024/02/PA-023918.19-FLS.-249-A-298.pdf)
- Goiânia (resolução municipal de 2025): os salões-parceiros são tributados na forma do Anexo III da Resolução CGSN 140/2018 — [Goiânia, ato 2025](https://www.goiania.go.gov.br/html/gabinete_civil/sileg/dados/legis/2025/dc_20250825_000002824_ane_000000002.pdf)
- A cota-parte destinada ao profissional-parceiro não integra a base de cálculo do ISS do salão — [Bahia Notícias, coluna tributária](https://www.bahianoticias.com.br/justica/coluna/834-tributo-em-pauta-o-iss-na-parceria-entre-saloes-de-beleza-e-profissionais)
- Os municípios fiscalizam a comprovação dos repasses. Em Niterói, houve autuações de ISS sobre salões que não comprovaram valores repassados nem a inscrição dos parceiros no CNPJ — [Fazenda Niterói, PA 023917.19](https://www.fazenda.niteroi.rj.gov.br/site/wp-content/uploads/2024/02/PA-023917.19-FLS.-210-A-217-E-2085-A-2108.pdf)

**Emissão de nota fiscal**
- Minas Gerais (Portaria SEF 58/2022, art. 4º): o profissional-parceiro deve emitir NFS-e destinada ao salão-parceiro, referente à cota-parte recebida — [LegisWeb, Portaria SEF 58/2022](https://www.legisweb.com.br/legislacao/?id=439324)
- Prática descrita por contabilidades: o salão emite documento unificado ao cliente, discriminando as parcelas, e o profissional emite o documento correspondente à sua parte. As fontes divergem quanto a quem é o tomador da nota do profissional (o salão ou o cliente) — [Kontae](https://www.kontae.com.br/blog/mei/faturamento-profissional-parceiro-mei); [Meu Contador Online](https://www.meucontadoronline.com.br/blog/salao-parceiro-o-que-e-como-formalizar-o-seu-negocio/)

**Homologação sindical: exemplo concreto (CCT Rio de Janeiro 2023/2024, MTE RJ000267/2024)**
- Cláusula 18ª: contratos de parceria homologados nos dois sindicatos (patronal e laboral), com **percentual mínimo de 20% sobre o serviço** para o profissional — [CCT RJ 2023/2024 (Law Insider)](https://lawinsider.com/pt/contracts/prPCokpf2V)
- §1º: validade de **1 ano**, sob pena de nulidade se não houver renovação. Taxa de **R$ 150,00 por sindicato** para registro; renovação em até 30 dias após o vencimento custa R$ 100,00 — [CCT RJ](https://lawinsider.com/pt/contracts/prPCokpf2V)
- §7º: o salão deve reter e repassar as contribuições sindicais do profissional-parceiro. Em caso de atraso, há juros de 2% e correção de 1% ao mês — [CCT RJ](https://lawinsider.com/pt/contracts/prPCokpf2V)
- §10º: a homologação é preferencialmente digital. §11º e cl. 17ª: o profissional-parceiro deve comprovar capacitação técnica por certificado — [CCT RJ](https://lawinsider.com/pt/contracts/prPCokpf2V)

**Jurisprudência**
- STF, **ADI 5625** (julgada em 28/10/2021, ajuizada pela Contratuh): a parceria é constitucional. São nulos, porém, os contratos que dissimulem relação de emprego (primazia da realidade, art. 9º CLT), e o vínculo é reconhecido caso a caso — [Acórdão ADI 5625 (TRT3)](https://portal.trt3.jus.br/internet/jurisprudencia/repercussao-geral-e-controle-concentrado-adi-adc-e-adpf-stf/downloads/controle-concentrado-adi/Acordao_ADI_5625.pdf); [Conexão Trabalho/CNI](https://conexaotrabalho.portaldaindustria.com.br/noticias/detalhe/trabalhista/-geral/stf-e-constitucional-lei-que-cria-o-contrato-de-parceria-entre-saloes-e-profissionais-de-beleza)
- TRT-MG (2025): validou parceria de cabeleireira com contrato homologado no sindicato e afastou o vínculo. O critério foi a ausência de subordinação, de horários impostos e de dependência econômica exclusiva — [Contadores.cnt.br, jul/2025](https://contadores.cnt.br/projetos/43/noticias/tecnicas/2025/07/23/contrato-de-parceria-afasta-vinculo-empregaticio-decide-trt.html); [COAD – Sete Lagoas](https://www.coad.com.br/home/noticias-detalhe/132914/justica-do-trabalho-reconhece-validade-do-contrato-de-parceria-entre-cabeleireira-e-salao-de-beleza-em-sete-lagoas)

### Inferences
- **Requisitos para o ERP (modelo parceria):**
  1. Cadastro do profissional-parceiro com CNPJ (MEI ou ME), número/validade do contrato, data de homologação e sindicato. Alertar no vencimento, pois no RJ a validade é de 1 ano.
  2. Regra de cota-parte **por serviço** (a lei exige "condições e periodicidade de pagamento por tipo de serviço"), respeitando pisos de CCT, como o mínimo de 20% no RJ.
  3. Ledger separado: receita do salão = só a cota-salão. A cota do profissional é passivo/repasse, não receita.
  4. Relatórios de comprovação dos repasses por profissional e período, para defesa em fiscalização de ISS e Simples.
  5. Controle de retenções (tributos e contribuição sindical, quando houver).
- O bloqueio de agenda e as escalas fixas impostas pelo salão são indícios de subordinação. Convém o ERP permitir que o próprio profissional gerencie sua agenda e disponibilidade no modelo parceria, para não produzir evidência contra o salão.
- Na prática, para profissional MEI, a "retenção de tributos" costuma ser zero (o MEI recolhe o DAS fixo), mas o salão continua responsável pela retenção quando cabível. Isto é uma inferência: não encontrei fonte oficial detalhando a retenção para MEI.

### Gaps
- Numeração exata do dispositivo da LC 123/2006 (alterada pela LC 155/2016) que exclui a cota-parte: as fontes citam art. 13 §1º-A, art. 13 §5º e art. 18, de forma inconsistente.
- Se as Resoluções CGSN 190 e 191 (ago/2026) alteraram a regra do salão-parceiro na Res. 140: os resultados não detalham — [contadores.cnt.br](https://www.contadores.cnt.br/legislacoes/resolucao-cgsn%20no%20140-%20de%2022-de-maio-de-2018.html)
- Jurisprudência do TST de 2024–2026 especificamente sobre salão-parceiro: não localizada nesta pesquisa.
- Leiaute municipal para "nota unificada" com discriminação de cotas: varia por município e não foi levantado.

## 2. Outros modelos: CLT com comissão, MEI, aluguel de cadeira, diária; percentuais típicos; descontos; vales

### Takeaway
No CLT comissionado vale a CCT local. A do RJ, por exemplo, fixa comissão mínima de 20%, piso de R$ 1.571,27 e **proíbe descontar produtos, insumos e taxa de cartão dos empregados**. O mercado pratica de 30% a 50% de comissão (ou cota) para cabeleireiros, com percentual menor em química. O desconto de taxa de cartão e de produto é uma escolha contratual no modelo parceria, mas é vedado para empregados em pelo menos uma CCT. O profissional-parceiro MEI tem como receita só a sua cota-parte.

### Cited Findings
- **CLT/RJ (CCT 2023/2024):**
  - mínimo de 20% de comissão sobre a mão de obra para cabelo, unha e estética;
  - remuneração mensal nunca inferior ao piso de R$ 1.571,27;
  - piso de R$ 1.515,42 para auxiliar de cabeleireiro;
  - para sobrancelha, cílios, micropigmentação, depilação e laser: piso mais comissão mínima de 5%;
  - tabela de remuneração fixa por faixa de produção (8 faixas, de R$ 1.571,27 a R$ 3.658,15).

  Fonte: [CCT RJ 2023/2024](https://lawinsider.com/pt/contracts/prPCokpf2V)
- **Cláusula 4ª da CCT RJ:** "Fica vedado as empresas, o desconto de produtos, insumos, e taxa de cartão de crédito dos funcionários" — [CCT RJ](https://lawinsider.com/pt/contracts/prPCokpf2V)
- Cláusula 6ª da CCT RJ: gorjetas espontâneas não sofrem ingerência da empresa. Cláusula 8ª: auxílio-alimentação de R$ 23,22 por dia trabalhado, com desconto permitido de 1% a 10% para que o benefício não tenha natureza salarial — [CCT RJ](https://lawinsider.com/pt/contracts/prPCokpf2V)
- Faixas de mercado:
  - 30% a 40% do preço do serviço quando o produto é do salão; 50% a 60% quando o profissional traz o produto;
  - média de 30% a 50% para cabeleireiros;
  - sugestão de 40% para corte, escova e penteado, com percentual menor para química e coloração (margem menor por causa do insumo).

  Fontes: [Belio – como calcular comissão](https://blog.belio.com.br/artigos/como-calcular-comissao-cabeleireiro/); [Gendo](https://www.gendo.com.br/en-us/blog-post/comissao-de-cabeleireiro-como-calcular-o-que-evitar-e-quanto-pagar); [Criadores de Imagem](https://cursos.criadoresdeimagem.com.br/como-calcular-comissao-de-cabeleireiro/); [Blog Trinks](https://blog.trinks.com/saiba-como-calcular-a-comissao-de-um-profissional-de-beleza/). Todas são fontes comerciais.
- Taxa de cartão: há dois critérios no mercado. A comissão pode ser calculada sobre o **valor bruto** (o salão absorve a taxa) ou sobre o **líquido** (a taxa é descontada antes) — [BarberPRO](https://barberpro.net.br/blog/comissao-barbeiro); [Graces](https://graces.com.br/blog/gestao/calculo-de-comissao/)
- **MEI:**
  - limite de R$ 81 mil/ano;
  - cabeleireiro, manicure e barbeiro podem ser MEI (CNAE 9602-5/01);
  - "cabeleireiro independente" consta do Anexo XI da Res. CGSN 140/2018, com limite de 1 empregado.

  Fontes: [Hopecont](https://hopecont.com/blog/dono-de-salao-pode-ser-mei/); [Contabilidade.com – CNAE 9602-5/01](https://contabilidade.com/blog/cnae-9602501-cabeleireiro-pode-ser-mei-quanto-paga-e-quando-desenquadrar-do-mei/). Fontes comerciais.
- Receita bruta do profissional-parceiro MEI = a **totalidade da cota-parte recebida do salão-parceiro** (Res. CGSN 140/2018, art. 100, §6º, conforme citado). Uma fonte (irrivio) diverge parcialmente na redação, mas converge em que a cota-parte conta para o limite — [Kontae](https://www.kontae.com.br/blog/mei/faturamento-profissional-parceiro-mei); [Irrivio](https://irrivio.com/blog/mei-cabeleireiro-barbeiro-manicure)

### Inferences
- **O motor de comissão do ERP precisa parametrizar:**
  - % por serviço e profissional, com override;
  - base bruta ou líquida (taxa de cartão);
  - desconto de produto/insumo em química, por valor fixo ou por custo real consumido;
  - descontos/cupons concedidos ao cliente, rateados ou absorvidos pelo salão;
  - piso mínimo da CCT e travas por modelo de vínculo. Para CLT em locais com cláusula como a do RJ, bloquear o desconto de taxa e de produto.
- Vales/adiantamentos: devem ser lançados como crédito contra comissões futuras, com abatimento no fechamento do período. Para CLT, aplicam-se os limites de desconto do art. 462 da CLT (inferência, não verificada nesta pesquisa).
- Para o profissional MEI, o ERP pode alertar quando a soma da cota-parte se aproximar de R$ 81 mil/ano.

### Gaps
- Aluguel de cadeira/bancada e "diária": não encontrei fontes confiáveis sobre a regulamentação. São contratos civis de locação, com alto risco de vínculo se houver subordinação, e não se enquadram na Lei 13.352 (que exige cota-parte percentual). Isto precisa ser validado com advogado.
- Percentuais típicos de manicure: não houve dado confiável específico. O piso de 20% da CCT RJ cobre unhas.
- Não foram levantadas CCTs de outras praças (SP, MG etc.). Os pisos e as vedações variam por sindicato.

## 3. Reforma Tributária (CBS/IBS) e Simples Nacional para salões **[REFORMA]**

### Takeaway
2026 é ano-teste: CBS de 0,9% e IBS de 0,1%, com carga efetiva idêntica à de 2025. A CBS plena entra em 2027 e o ISS é extinto em 2033. O Simples Nacional foi preservado. Não encontrei nenhuma regra específica da LC 214/2025 para o modelo salão-parceiro. A base de cálculo geral do IBS/CBS é o valor da operação.

### Cited Findings
- 2026: CBS 0,9% e IBS 0,1% como teste. CBS plena em 2027; ICMS e ISS extintos em 2033. "Em 2026, a carga tributária será idêntica à de 2025" — [Migalhas – "IBS/CBS em 2026: nós não vamos pagar nada"](https://www.migalhas.com.br/depeso/432732/reforma-tributaria-ibscbs-em-2026-nos-nao-vamos-pagar-nada); [CompanyHero](https://www.companyhero.com/blog/reforma-tributaria-cbs-ibs)
- A EC 132/2023 e a LC 214/2025 preservaram o Simples Nacional — [Apresentação Reforma Tributária (Migalhas, nov/2025)](https://www.migalhas.com.br/arquivos/2025/11/102751CE4246D1_Apresentacao-ReformaTributaria.pdf)
- A LC 227/2026 alterou dezenas de artigos da LC 214. A CBS foi regulamentada pelo Decreto 12.955/2026 e o IBS pela Resolução CGIBS 6/2026 — [Barbieri Advogados – guia LC 214](https://www.barbieriadvogados.com/lc-214/)
- Base de cálculo do IBS/CBS: valor da operação (art. 12 LC 214), salvo regimes específicos — [Revista PGE-SP](https://revistas.pge.sp.gov.br/revistapegesp/article/download/1689/1732); [Planalto, LC 214](https://www.planalto.gov.br/ccivil_03/leis/lcp/lcp214.htm)
- A Lei do Salão Parceiro segue em vigor em 2026/2027, segundo blog contábil (fonte comercial) — [eSimples Auditoria](https://blog.esimplesauditoria.com.br/saloes-de-beleza-simples-nacional/)
- Simples Nacional, serviços (Anexo III): alíquotas nominais de 6% a 33%. Para atividades sujeitas ao Fator R, folha de 28% ou mais leva ao Anexo III e abaixo disso ao Anexo V. Os salões-parceiros são citados como tributados pelo Anexo III — [Trivium Contábil – Anexo III](https://triviumcontabil.com.br/anexo-iii-simples-nacional/); [Goiânia](https://www.goiania.go.gov.br/html/gabinete_civil/sileg/dados/legis/2025/dc_20250825_000002824_ane_000000002.pdf)
- A Resolução CGSN 183/2025 e as Resoluções CGSN 190/191 (2026) introduziram mudanças no Simples ligadas à reforma — [BMA Law](https://www.bmalaw.com.br/conteudo/direito-tributario/reforma-tributaria/reforma-tributaria-resolucoes-promovem-mudancas-significativas-no-simples-nacional/pdf); [Res. CGSN 183/2025](https://www.reformatributaria.com/wp-content/uploads/2025/11/RESOLUCAO-CGSN-No-183-DE-26-DE-SETEMBRO-DE-2025.pdf)

### Inferences
- Como a LC 214 não traz regra própria para o salão-parceiro, a exclusão da cota-parte da receita deve continuar a operar pela Lei 13.352 e pela LC 123/CGSN enquanto o salão estiver no Simples. Para salões fora do Simples (regime regular de IBS/CBS), a forma de tratar a cota-parte (base reduzida ou intermediação) é **incerta** e é ponto de risco a validar.
- O ERP deve ter campos de IBS/CBS (cClassTrib, alíquotas de teste) nos documentos fiscais desde 2026, mesmo sem recolhimento efetivo.

### Gaps
- Tratamento específico do salão-parceiro no IBS/CBS (regime regular): não encontrado em nenhuma fonte.
- Detalhe da opção do optante do Simples por recolher IBS/CBS "por fora" a partir de 2027, que permite gerar crédito ao tomador PJ: não verificado em fonte desta pesquisa. É pouco relevante para o salão B2C, mas relevante para a nota do profissional-parceiro emitida contra o salão.
- Serviços de beleza não foram identificados em nenhuma lista de alíquota reduzida, mas também não há fonte confirmando isso.

## 4. Split de pagamento (Stone/Trinks, Asaas, Pagar.me, Mercado Pago, PagBank, Cielo, Pix)

### Takeaway
O caso mais maduro no setor é Trinks + Stone (maquininha "Belezinha"). O split é feito no momento da venda, por percentual, valor fixo ou serviço, e cada profissional tem conta/Stone Code próprio. Em APIs genéricas (Asaas, Pagar.me, Mercado Pago), o desenho exige definir quem absorve a taxa do cartão e quem responde pelo chargeback. O split é revertido no chargeback.

### Cited Findings
- **Trinks + Stone:** o split divide o pagamento entre o estabelecimento e o profissional no ato. Exemplo: comanda de R$ 200 = corte R$ 80 (profissional A) + coloração R$ 120 (profissional B), e cada valor vai para a conta do respectivo profissional. Pode ser usado com profissional-parceiro. A regra pode ser por percentual, valor fixo ou serviço — [Blog Trinks – split](https://blog.trinks.com/split-de-pagamentos-o-que-e-e-como-fazer-no-seu-negocio-de-beleza/)
- "Com a Belezinha Stone com Split de Pagamento, o sistema calcula e repassa automaticamente a comissão dos profissionais" — [Trinks – Belezinha Connect Stone](https://blog.trinks.com/como-funciona-a-belezinha-trinks-com-connect-stone/)
- Cadastro na Trinks:
  - marcar no profissional que ele usa split;
  - quem nunca usou split na Stone informa conta bancária, não Stone Code;
  - o Stone Code de split leva de 24 a 72h para ser liberado;
  - Stone Code de "Link de Pagamento" não serve para split.

  Fonte: [Ajuda Trinks](https://ajuda.trinks.com/como-cadastrar-meus-profissionais-para-split-de-pagamento-central-de-ajuda-do-trinks)
- O blog da Trinks não informa prazos de liquidação (D+1/D+30), taxas, nem se Pix pode ser splitado — [Blog Trinks](https://blog.trinks.com/split-de-pagamentos-o-que-e-e-como-fazer-no-seu-negocio-de-beleza/)
- Relato isolado (Reclame Aqui) de profissional sem máquina Stone, só com conta, cujo split não chegou como esperado — [Reclame Aqui](https://www.reclameaqui.com.br/stone/stone-e-trinks-confiscaram-meu-pagamento_6GKsy4KFcboPV1Uc/)
- **Pagar.me:** split por `flat` ou `percentage`. Ao menos um recebedor deve ser marcado como responsável por chargeback (`liable`). Há flags para definir quem paga a taxa de processamento e quem recebe o resto — [Docs Pagar.me – split](https://docs.pagar.me/reference/split-1)
- **Asaas:** em chargeback o split é revertido e as transferências às contas que receberam são estornadas. Split por percentual ou valor fixo, também usável sem API — [Asaas docs – split overview](https://docs.asaas.com/docs/payment-split-overview); [Asaas – split sem API](https://docs.asaas.com/docs/usando-o-split-sem-api)
- **Mercado Pago (split 1:N):** só o vendedor principal gerencia o chargeback. Os secundários não são notificados e o valor contestado fica retido até a resolução — [Mercado Pago Developers – chargebacks split](https://omega.mercadopago.com.ar/developers/en/docs/split-payments-1-n/payments-management/chargebacks)

### Inferences
- **Desenho para o ERP:**
  - o split deve ser gerado a partir da comanda: linha de serviço → profissional → % cota;
  - produtos vendidos ficam 100% com o salão;
  - a taxa de cartão é atribuída conforme o contrato (bruto/líquido).

  No modelo parceria, o split na adquirente materializa o fluxo "salão centraliza recebimento e repassa cota". Mesmo assim, o salão precisa registrar a retenção de tributos e manter a prova de repasse.
- Pagamentos parcelados, estornos e chargebacks precisam reverter a comissão ou cota do profissional. As APIs fazem isso de formas diferentes: o Asaas reverte automaticamente, enquanto no Mercado Pago o principal absorve.

### Gaps
- PagBank/PagSeguro, Cielo e Pix com split no contexto de salões: não encontrei documentação nesta pesquisa.
- Avec (e "Avec Pay"): documentação sobre split não localizada.
- Taxas e prazos de liquidação por provedor: não publicados nas fontes encontradas.

## 5. Comanda, fechamento de caixa, formas de pagamento, gorjeta, sinal/no-show, pacotes, vale-presente

### Takeaway
Há pouca fonte brasileira específica. Para gorjeta, a Lei 13.419/2017 define que ela não é receita própria do empregador e se destina aos trabalhadores. A CCT RJ reforça que a empresa não interfere na gorjeta espontânea. Para pacotes pré-pagos e vale-presente, a lógica contábil é passivo (receita diferida) até a execução do serviço, mas só achei fontes estrangeiras/análogas.

### Cited Findings
- Lei 13.419/2017: a gorjeta não é receita própria do empregador e destina-se aos trabalhadores, com rateio por critérios de convenção/acordo coletivo. As fontes tratam do contexto de bares e restaurantes — [Senado Notícias](https://www12.senado.leg.br/noticias/materias/2017/03/14/lei-sancionada-regulamenta-rateio-de-gorjeta-e-taxa-de-servico); [Jornal Contábil](https://jornalcontabil.com.br/noticia/o-que-muda-para-o-empresario-com-regulamentacao-da-gorjeta/)
- CCT RJ (salões), cl. 6ª: gorjetas espontâneas do cliente ao funcionário não sofrem ingerência da empresa — [CCT RJ](https://lawinsider.com/pt/contracts/prPCokpf2V)
- Pacotes e gift cards (referência dos EUA, análoga): o valor pré-pago entra como passivo e a receita é reconhecida por sessão executada. Exemplo: pacote de 6 sessões por $200 reconhece cerca de $33,33 por visita. O breakage (saldo não utilizado) é questão de política separada — [Beancount – med spa deferred revenue](https://beancount.io/pt/blog/2026/07/16/med-spa-bookkeeping-deferred-revenue-packages-gift-cards-memberships-guide)

### Inferences
- **ERP:**
  - **Gorjeta** como linha separada da comanda, fora da receita e da base de comissão, repassada 100% ao profissional (inclusive via split). Não emitir NF sobre ela, mas confirmar com contador.
  - **Pacote pré-pago** como crédito do cliente (passivo). A cada sessão consumida, reconhecer a receita proporcional e liberar a comissão ou cota naquele momento, não na venda.
  - **Vale-presente** como passivo até o resgate.
  - **Sinal/pré-pagamento antinoshow** como adiantamento de cliente, abatido na comanda. A retenção por no-show deve estar prevista em política informada previamente ao cliente (CDC), o que é uma inferência.
  - **Fechamento de caixa:**
    - conferência por forma de pagamento (dinheiro, débito, crédito à vista/parcelado, Pix, voucher, crédito de pacote);
    - suprimento/sangria;
    - conciliação com o extrato da adquirente.
- O momento da NF de pacotes (na venda ou no consumo) depende da legislação municipal do ISS. É um ponto a validar.

### Gaps
- Aplicação expressa da Lei 13.419/2017 a salões de beleza: as fontes encontradas não confirmam.
- Norma brasileira (CPC 47) aplicada a pacotes e vale-presente em salões, tratamento tributário de sinal retido por no-show e de breakage: não encontrado.

## 6. NFS-e (padrão nacional) para salões **[REFORMA]**

### Takeaway
Desde 1º/01/2026 os municípios são obrigados a aderir ao padrão nacional da NFS-e (LC 214/2025, art. 62, §1º), seja usando o emissor nacional, seja compartilhando dados a partir de sistema próprio. O MEI já emite no padrão nacional desde 2023. Para optantes do Simples, fontes indicam emissão obrigatória no padrão nacional a partir de 1º/09/2026 (Res. CGSN 189/2026), o que ainda precisa ser confirmado em fonte oficial.

### Cited Findings
- Os municípios devem adotar o padrão nacional desde 1º/01/2026 (LC 214, art. 62, §1º), via sistema próprio integrado ou emissor nacional. A não adesão leva à suspensão de transferências voluntárias — [Trivium Contábil – NFS-e Nacional](https://triviumcontabil.com.br/?p=17554); [NetCPA](https://netcpa.com.br/colunas/municipios-terao-que-adotar-nfs-e-nacional-ate-2026-sob-pena-de-sancoes/26043); [Jornal Contábil](https://jornalcontabil.com.br/noticia/nfs-e-padrao-nacional-passa-a-ser-uma-obrigacao-em-2026/)
- O MEI emite no padrão nacional desde 2023 — [Trivium](https://triviumcontabil.com.br/?p=17554)
- Optantes do Simples: emissão no padrão nacional obrigatória a partir de 1º/09/2026 (Res. CGSN 189/2026), segundo fontes contábeis não oficiais — [Meu Contador Online](https://www.meucontadoronline.com.br/blog/nfs-e-nacional-2026-mudancas/)
- Exemplos de prefeituras com decreto exigindo o padrão nacional a partir de 2026 — [Carnaúba dos Dantas/RN, Decreto 022/2025](https://www.carnaubadosdantas.rn.gov.br/wp-content/uploads/2025/11/Decreto-022.2025.pdf); [DF – comunicado](https://static.fazenda.df.gov.br/arquivos/servico-1202/comunicado_NFSe_padrao_nacional_04-11-2025.pdf)

### Inferences
- O ERP deve integrar com a API do emissor nacional (Sefin/ADN) e manter fallback para webservices municipais onde o município usa sistema próprio integrado.
- No modelo parceria, o ERP gera:
  1. a NFS-e do salão sobre a cota-salão, ou a nota unificada discriminando as cotas, conforme o município;
  2. a NFS-e do profissional-parceiro (MEI pelo emissor nacional), referente à cota-parte e tendo o salão como tomador nas praças que exigem isso (ex.: MG).
- Desde 2026, os campos de IBS/CBS precisam constar no leiaute nacional.

### Gaps
- Texto oficial da Resolução CGSN 189/2026 e eventual prorrogação: não confirmados.
- Leiaute/campos específicos para identificar a operação de salão-parceiro na NFS-e nacional: não encontrados.

## 7. KPIs financeiros para salões

### Takeaway
Não encontrei fontes autoritativas (Sebrae etc.) com definições e benchmarks nesta pesquisa. As definições abaixo são padrão de mercado e estão registradas como inferência.

### Cited Findings
- Nenhuma fonte primária obtida especificamente sobre KPIs de salões. A única referência (estrangeira) cita "revenue per chair" como KPI — [Beancount – nail salon KPI guide](https://beancount.io/pt/blog/2026/06/03/independent-nail-salon-mobile-manicure-bookkeeping-asc-606-section-45b-fica-tip-credit-obbba-2026-mma-ban-state-cosmetology-section-179-bonus-depreciation-abc-test-revenue-per-chair-kpi-guide)

### Inferences
- Definições sugeridas para o ERP (padrão de mercado, sem fonte):
  - **ticket médio** = faturamento ÷ nº de comandas (ou de clientes atendidos);
  - **taxa de ocupação** = horas agendadas/atendidas ÷ horas disponíveis na agenda, por profissional;
  - **faturamento por profissional** = bruto e cota-salão (no modelo parceria, a métrica relevante para o salão é a cota-salão);
  - **taxa de retorno/retenção** = % de clientes que voltam em X dias;
  - **CMV de produtos** = custo dos produtos vendidos ÷ receita de produtos, com custo de insumos de química por serviço separado;
  - **no-show rate**;
  - **receita por cadeira**.
- Com split e parceria, os relatórios devem distinguir "faturamento total do salão (GMV)" de "receita do salão (cota-salão + produtos)". Só a segunda é base do Simples e do ISS.

### Gaps
- Benchmarks brasileiros (ex.: ticket médio, ocupação ideal, retenção) por porte de salão: não encontrados. Vale buscar em Sebrae/ABIHPEC ou em relatórios Trinks/Avec.
