# Testar o WhatsApp sem conta na Meta

Serve para ver o robô de agendamento e os lembretes funcionando **antes** de ter CNPJ, app na Meta ou número. Nada sai para a internet: o robô "responde", e a resposta aparece na tela **Conversas**, como apareceria para a equipe.

## 1. Preparar (uma vez)

No `.env.local`, além das chaves do Supabase de teste:

```
SUPABASE_SERVICE_ROLE_KEY=...        # o servidor precisa dela para tratar as mensagens
META_APP_SECRET=qualquer-texto-longo # no teste, vale qualquer texto; o script usa o mesmo para assinar
WHATSAPP_SIMULAR=1
```

Suba o sistema (`npm run dev`), entre como administrador e abra **WhatsApp** no menu. Preencha:

- **ID do número:** qualquer sequência de dígitos, por exemplo `100000000000001` (guarde, você vai usar abaixo)
- **Token:** qualquer texto com 20 caracteres ou mais

No modo simulado, o sistema não consulta a Meta, então a conexão é aceita.

## 2. Simular a cliente escrevendo

Em outro terminal, na pasta do projeto:

```
node --env-file=.env.local scripts/simular-whatsapp.mjs --phone-id 100000000000001 --de 5511999990001 --texto "oi"
```

Abra **Conversas**: a mensagem do cliente e a resposta do robô estão lá. Para continuar a conversa, repita o comando com a resposta. Quando o robô mostrar botões, simule o toque pelo `id` do botão (em listas, como a de serviços e horários, use `--lista` no lugar de `--botao`):

```
node --env-file=.env.local scripts/simular-whatsapp.mjs --phone-id 100000000000001 --de 5511999990001 --botao "ID-DO-BOTAO" --titulo "Texto do botão"
```

(Os ids aparecem no log do servidor, na linha `[whatsapp:simulado] enviaria`.) Use `--nome "Maria"` para mudar o nome do contato e outro `--de` para simular outro cliente.

## 3. Lembretes, retorno e lista de espera

Com o modo simulado ligado, os lembretes, os convites de retorno e os avisos de vaga também "enviam" só para o histórico. Para disparar a rotina agora:

```
curl -H "Authorization: Bearer $CRON_SECRET" http://localhost:3000/api/cron/lembretes
```

## O que este teste NÃO cobre

- Entrega real pela Meta, aprovação dos modelos de mensagem e regras da janela de 24 horas.
- Mensagens de áudio, imagem etc. (o script só envia texto e toque em botão).

Esses pontos só se testam com o número de teste da Meta, quando o app for criado. Nesse caso o servidor precisa de um endereço público (um túnel gratuito resolve) para a Meta chamar o webhook.

## Segurança

`WHATSAPP_SIMULAR` é ignorado quando `NODE_ENV=production`. Não use dados reais de clientes nesse ambiente de teste.
