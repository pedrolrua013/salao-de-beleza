# Usabilidade: requisito e roteiro de teste

## Requisito (vale para toda tela nova)

O Belezando precisa ser **intuitivo**: uma recepcionista que nunca viu o sistema agenda uma consulta sem treinamento e sem manual.

Regras de projeto:

1. **Uma ação principal por tela**, com o botão em destaque e um verbo claro ("Novo agendamento", não "Enviar").
2. **Palavras do consultório**, não do sistema: "cliente", "consulta", "retorno". Nada de "registro", "entidade", "status".
3. **O caminho aparece sozinho**: quando falta algo (nenhum cliente, WhatsApp desconectado), a tela diz o que fazer e leva até lá.
4. **Estados vazios ensinam**: dizem o que a tela é e como começar.
5. **Erro diz o que houve e como resolver**, nunca só "erro".
6. **Ações destrutivas pedem confirmação** e dizem o efeito.
7. **Funciona no celular e por teclado** (alvos de toque de 44px, foco visível).
8. **Ajuda ao alcance**: item "Ajuda" no menu e link nos primeiros passos.

Já implementado: checklist "Primeiros passos" na tela Hoje (administrador), página Ajuda por papel, cartão "Ainda sem confirmação", estados vazios com ação.

## Roteiro de teste (fazer com 3 a 5 pessoas reais antes do lançamento)

Pessoas: 2 recepcionistas e 2 cabeleireiros que nunca viram o Belezando. Não explique nada. Peça para pensarem em voz alta. Anote onde hesitam, clicam errado ou pedem ajuda.

| # | Tarefa dita ao participante | Sucesso | Meta |
| --- | --- | --- | --- |
| 1 | "Você acabou de criar o salão. Cadastre uma cliente chamada Marina." | Cliente salva | menos de 1 min |
| 2 | "Marque uma limpeza para a Marina amanhã às 14h." | Consulta aparece na agenda | menos de 2 min |
| 3 | "A Marina ligou: confirmou a consulta." | Situação vira Confirmado | menos de 30 s |
| 4 | "Ela pediu para cancelar." | Consulta cancelada | menos de 30 s |
| 5 | "Veja quem ainda não confirmou para amanhã." | Acha o cartão em Hoje | menos de 30 s |
| 6 | "(Cabeleireiro) Inicie e conclua o atendimento da cliente na agenda." | Horário marcado como concluído | menos de 1 min |
| 7 | "Convide uma recepcionista para a equipe." | Convite criado | menos de 1 min |

Critério de aprovação: pelo menos 80% das tarefas feitas sem ajuda e dentro da meta. O que falhar vira ajuste de tela ou de texto, e o teste se repete com outras pessoas.

Ao final, duas perguntas: "O que foi mais confuso?" e "O que você esperava achar e não achou?".
