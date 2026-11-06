-- Testes de isolamento, papéis, conflito de horário, auditoria e WhatsApp.
\set ON_ERROR_STOP on
create schema if not exists t;
create or replace function t.ok(cond boolean, msg text) returns void language plpgsql as
$$ begin if not coalesce(cond, false) then raise exception 'FALHOU: %', msg; end if; raise notice 'ok  - %', msg; end $$;
-- executa sql e confere o SQLSTATE esperado
create or replace function t.erro(q text, esperado text, msg text) returns void language plpgsql as
$$ declare got text := 'nenhum'; begin
  begin execute q; exception when others then got := sqlstate; end;
  if got <> esperado then raise exception 'FALHOU: % (esperado %, veio %)', msg, esperado, got; end if;
  raise notice 'ok  - %', msg;
end $$;
grant usage on schema t to anon, authenticated, service_role;
grant execute on all functions in schema t to anon, authenticated, service_role;

-- usuários
insert into auth.users (id) values
  ('a0000000-0000-0000-0000-000000000001'), -- admin A
  ('a0000000-0000-0000-0000-000000000002'), -- profissional A
  ('a0000000-0000-0000-0000-000000000003'), -- recepção A
  ('b0000000-0000-0000-0000-000000000001'); -- admin B

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select criar_salao('Studio Bela', 'sorriso', 'Ana') as salao_a \gset
reset role;
update saloes set antecedencia_max_dias = 365 where id = :'salao_a';  -- os testes marcam a até 3 meses
insert into membros (user_id, salao_id, papel, nome) values
  ('a0000000-0000-0000-0000-000000000002', :'salao_a', 'profissional', 'Bruno'),
  ('a0000000-0000-0000-0000-000000000003', :'salao_a', 'recepcao', 'Carla');

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select criar_salao('Espaço Luz', 'espacoluz', 'Dr. Luiz') as salao_b \gset
reset role;

-- horários: segunda-feira daqui a ~2 semanas, 10:00 no fuso do salão
select ((date_trunc('week', now() + interval '14 days')::date + time '10:00') at time zone 'America/Sao_Paulo') as seg10 \gset

-- 1) criar_salao semeou os serviços
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from servicos) = 8, 'salão nasce com 8 serviços (com Barba masculina)');
select t.erro($$select criar_salao('Outra', 'outra', 'Ana')$$, '23505', 'usuário não cria segundo salão');

-- 2) clientes e agenda do salão A
insert into clientes (nome, telefone) values ('Marina Silva', '11999990001') returning id as pac_a \gset
select id as srv_a from servicos where nome = 'Escova' \gset
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim)
  values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg10', :'seg10'::timestamptz + interval '45 min')
  returning id as ag1 \gset
select t.erro(format($q$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim)
  values (%L, 'a0000000-0000-0000-0000-000000000002', %L, %L::timestamptz + interval '30 min', %L::timestamptz + interval '90 min')$q$,
  :'pac_a', :'srv_a', :'seg10', :'seg10'), '23P01', 'dois horários sobrepostos do mesmo profissional são bloqueados');
update agendamentos set status = 'cancelado' where id = :'ag1';
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim)
  values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg10', :'seg10'::timestamptz + interval '45 min')
  returning id as ag2 \gset
select t.ok(true, 'cancelar libera o horário para outro agendamento');
reset role;

-- 3) isolamento: admin B não vê nem mexe em A
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from clientes) = 0, 'salão B não enxerga clientes da A');
select t.ok((select count(*) from agendamentos) = 0, 'salão B não enxerga agenda da A');
select t.ok((select count(*) from saloes) = 1, 'salão B enxerga só a próprio salão');
select t.erro(format($q$insert into clientes (salao_id, nome) values (%L, 'Intruso')$q$, :'salao_a'), '42501', 'B não cria cliente dentro da A');
with u as (update clientes set nome = 'Hack' where id = :'pac_a' returning 1) select t.ok((select count(*) from u) = 0, 'B não altera cliente da A');
insert into clientes (nome) values ('Cliente B') returning id as pac_b \gset
select t.erro(format($q$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim)
  values (%L, 'b0000000-0000-0000-0000-000000000001', (select id from servicos limit 1), now() + interval '30 days', now() + interval '30 days 1 hour')$q$, :'pac_a'),
  '23503', 'B não agenda com cliente da A (chave composta)');
reset role;

-- 4) recepção
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok((select count(*) from clientes) = 1, 'recepção vê clientes');
update agendamentos set status = 'confirmado' where id = :'ag2';
select t.ok((select status from agendamentos where id = :'ag2') = 'confirmado', 'recepção confirma agendamento');
with u as (update servicos set nome = 'x' returning 1) select t.ok((select count(*) from u) = 0, 'recepção não edita catálogo de serviços');
reset role;

-- 5) profissional: inicia e conclui o atendimento pela agenda
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
update agendamentos set status = 'em_atendimento' where id = :'ag2';
select t.ok((select status from agendamentos where id = :'ag2') = 'em_atendimento', 'profissional inicia o atendimento');
update agendamentos set status = 'concluido' where id = :'ag2';
select t.ok((select status from agendamentos where id = :'ag2') = 'concluido', 'profissional conclui o atendimento');
reset role;

-- 6) outro salão não lê a auditoria
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from log_auditoria where salao_id = :'salao_a') = 0, 'outro salão não lê auditoria');
reset role;

-- 7) auditoria
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from log_auditoria where tabela = 'agendamentos') >= 3, 'admin vê auditoria da agenda');
select t.ok((select count(*) from log_auditoria where tabela = 'clientes' and acao = 'insert') >= 1, 'cadastro de cliente foi auditado');
select t.ok(exists (select 1 from log_auditoria where tabela = 'agendamentos' and acao = 'update' and campos_alterados @> array['status']), 'auditoria registra o campo alterado');
select t.ok(not exists (select 1 from log_auditoria l where l::text like '%Marina%'), 'auditoria não copia o conteúdo dos registros');
select t.erro($$insert into log_auditoria (salao_id, tabela, acao) values (gen_random_uuid(), 'x', 'insert')$$, '42501', 'ninguém grava no log pelo app');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from log_auditoria) = 0, 'profissional não lê auditoria');
reset role;

-- 8) anônimo não acessa nada
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select t.erro($$select * from clientes$$, '42501', 'anônimo não lê clientes');
select t.erro($$select * from agendamentos$$, '42501', 'anônimo não lê agenda');
select t.erro($$select criar_salao('X','x-1','Y')$$, '42501', 'anônimo não executa funções do app');
reset role;


-- 9) WhatsApp
select t.ok(tel_nacional('5511988887777') = '11988887777', 'telefone: tira o 55');
select t.ok(tel_nacional('551188887777') = '11988887777', 'telefone: acrescenta o 9 omitido');
select t.ok(tel_nacional('(11) 98888-7777') = '11988887777', 'telefone: ignora máscara');
select t.ok(tel_nacional('551133334444') = '1133334444', 'telefone: fixo não ganha 9');

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro($$select * from whatsapp_contas$$, '42501', 'usuário logado não lê credenciais do WhatsApp');
select t.erro($$select receber_mensagem(gen_random_uuid(), '5511999990001', 'x', 'w', 'texto', 'oi')$$, '42501', 'usuário logado não executa funções do robô');
reset role;

set role service_role;
select (receber_mensagem(:'salao_a', '5511999990001', 'Marina', 'wamid.1', 'texto', 'oi') ->> 'conversa_id') as conv_a \gset
select t.ok((select cliente_id is not null from conversas where id = :'conv_a'), 'conversa nova liga ao cliente pelo telefone');
select t.ok((receber_mensagem(:'salao_a', '5511999990001', 'Marina', 'wamid.1', 'texto', 'oi') ->> 'nova')::boolean, 'reenvio de mensagem ainda não tratada é reprocessado');
update mensagens set processada_em = now() where wa_msg_id = 'wamid.1';
select t.ok((receber_mensagem(:'salao_a', '5511999990001', 'Marina', 'wamid.1', 'texto', 'oi') ->> 'nova')::boolean = false, 'webhook repetido não duplica mensagem');
select t.ok((select count(*) from mensagens where conversa_id = :'conv_a') = 1 and (select nao_lidas from conversas where id = :'conv_a') = 1, 'uma mensagem e uma não lida');

-- sem consentimento prévio, o robô precisa receber o aceite
select t.erro(format($q$select agendar_whatsapp(%L, %L, %L, 'a0000000-0000-0000-0000-000000000002', %L, null, false)$q$, :'salao_a', :'conv_a', :'srv_a', :'seg10'::timestamptz + interval '4 hours'), '22023', 'whatsapp: sem consentimento é recusado');
select agendar_whatsapp(:'salao_a', :'conv_a', :'srv_a', 'a0000000-0000-0000-0000-000000000002', :'seg10'::timestamptz + interval '4 hours', null, true) as ag_w \gset
select t.ok((select origem = 'whatsapp' and status = 'confirmado' from agendamentos where id = :'ag_w'), 'whatsapp: agendamento do robô nasce confirmado, com origem whatsapp');
select t.ok((select consentimento_em is not null from clientes where id = :'pac_a'), 'whatsapp: aceite registrado no cliente');
select t.erro(format($q$select agendar_whatsapp(%L, %L, %L, 'a0000000-0000-0000-0000-000000000002', %L, null, true)$q$, :'salao_a', :'conv_a', :'srv_a', :'seg10'::timestamptz + interval '4 hours 15 minutes'), '22023', 'whatsapp: horário ocupado é recusado');
select t.erro(format($q$select agendar_whatsapp(%L, %L, %L, 'a0000000-0000-0000-0000-000000000002', %L, null, true)$q$, :'salao_a', :'conv_a', :'srv_a', :'seg10'::timestamptz + interval '9 hours'), '22023', 'whatsapp: fora do expediente é recusado');
select t.erro(format($q$select agendar_whatsapp(%L, %L, %L, 'a0000000-0000-0000-0000-000000000002', now() - interval '1 day', null, true)$q$, :'salao_a', :'conv_a', :'srv_a'), '22023', 'whatsapp: horário passado é recusado');
select t.erro(format($q$select agendar_whatsapp(%L, %L, %L, 'b0000000-0000-0000-0000-000000000001', %L, null, true)$q$, :'salao_a', :'conv_a', :'srv_a', :'seg10'::timestamptz + interval '5 hours'), '22023', 'whatsapp: profissional de outro salão é recusado');

-- número novo: cria o cliente, exige nome e aceite
select (receber_mensagem(:'salao_a', '5511977776666', 'Joana', 'wamid.2', 'texto', 'quero marcar') ->> 'conversa_id') as conv_j \gset
select t.erro(format($q$select agendar_whatsapp(%L, %L, %L, 'a0000000-0000-0000-0000-000000000002', %L, 'Joana Lima', false)$q$, :'salao_a', :'conv_j', :'srv_a', :'seg10'::timestamptz + interval '5 hours'), '22023', 'whatsapp: cliente novo sem aceite é recusado');
select agendar_whatsapp(:'salao_a', :'conv_j', :'srv_a', 'a0000000-0000-0000-0000-000000000002', :'seg10'::timestamptz + interval '5 hours', 'Joana Lima', true) as ag_j \gset
select t.ok((select nome = 'Joana Lima' and telefone = '11977776666' from clientes where id = (select cliente_id from conversas where id = :'conv_j')), 'whatsapp: cliente novo criado com telefone normalizado');

-- listar e cancelar só o que é da própria conversa
select t.ok((select count(*) from agendamentos_whatsapp(:'salao_a', :'conv_a')) = 1, 'whatsapp: lista só os agendamentos do próprio cliente');
select t.ok(cancelar_whatsapp(:'salao_a', :'conv_a', :'ag_j') = false, 'whatsapp: não cancela agendamento de outro cliente');
select t.ok(cancelar_whatsapp(:'salao_a', :'conv_a', :'ag_w') = true, 'whatsapp: cancela o próprio agendamento');
select t.ok(cancelar_whatsapp(:'salao_a', :'conv_a', :'ag_w') = false, 'whatsapp: cancelar de novo não faz nada');
reset role;

-- isolamento e permissões das conversas
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok((select count(*) from conversas) = 2 and (select count(*) from mensagens) = 2, 'recepção lê as conversas da próprio salão');
update conversas set nao_lidas = 0 where id = :'conv_a';
select t.ok((select nao_lidas from conversas where id = :'conv_a') = 0, 'recepção marca conversa como lida');
update conversas set bot_ativo = false where id = :'conv_a';
select t.ok((select not bot_ativo from conversas where id = :'conv_a'), 'recepção assume a conversa (pausa o robô)');
select t.erro($$update conversas set estado = '{"x":1}'$$, '42501', 'ninguém altera o estado do robô pelo app');
select t.erro($$insert into mensagens (salao_id, conversa_id, direcao, autor, corpo) select salao_id, id, 'saida', 'equipe', 'x' from conversas limit 1$$, '42501', 'ninguém grava mensagem pelo app');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from conversas) = 0 and (select count(*) from mensagens) = 0, 'outro salão não vê conversas nem mensagens');
reset role;
set role anon;
select t.erro($$select * from conversas$$, '42501', 'anônimo não lê conversas');
reset role;

-- 10) Lembretes
-- (a) cliente sem aceite não gera lembrete; com aceite, gera véspera e segundo aviso
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update saloes set lembrete_hora = '10:00' where id = :'salao_a';
insert into clientes (nome, telefone) values ('Carlos Sem Aceite', '11955550001') returning id as pac_sa \gset
insert into clientes (nome, telefone) values ('Ana Com Aceite', '11955550002') returning id as pac_ca \gset
select registrar_aceite_contato(:'pac_ca') as aceite_ca \gset
reset role;
select ((date_trunc('week', now() + interval '21 days')::date + time '14:00') at time zone 'America/Sao_Paulo') as seg14 \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim, origem)
  values (:'pac_sa', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg14'::timestamptz + interval '5 hours', :'seg14'::timestamptz + interval '5 hours 45 minutes', 'interno') returning id as ag_sa \gset
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim, origem)
  values (:'pac_ca', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg14', :'seg14'::timestamptz + interval '1 hour 30 minutes', 'interno') returning id as ag_ca \gset
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_sa') = 0, 'sem aceite: nenhum lembrete');
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_ca' and estado = 'pendente') = 2, 'com aceite: véspera e segundo aviso programados');
select t.ok((select ((enviar_em at time zone 'America/Sao_Paulo')::time = time '10:00' and (enviar_em at time zone 'America/Sao_Paulo')::date = (:'seg14'::timestamptz at time zone 'America/Sao_Paulo')::date - 1) from lembretes where agendamento_id = :'ag_ca' and tipo = 'vespera'), 'véspera sai às 10h do dia anterior, no horário do salão');
select t.ok((select enviar_em = :'seg14'::timestamptz - interval '3 hours' from lembretes where agendamento_id = :'ag_ca' and tipo = 'mesmo_dia'), 'segundo aviso sai 3 horas antes');
reset role;

select t.ok((select count(*) from lembretes where agendamento_id = :'ag_w') = 0, 'agendamento feito pelo robô não gera lembrete duplicado');

-- (b) mudar o horário refaz os lembretes pendentes
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update agendamentos set inicio = :'seg14'::timestamptz + interval '1 day', fim = :'seg14'::timestamptz + interval '1 day 45 minutes' where id = :'ag_ca';
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_ca' and estado = 'pendente') = 2 and (select count(*) from lembretes where agendamento_id = :'ag_ca' and estado = 'cancelado') = 2, 'remarcar cancela os antigos e cria novos');
-- (c) confirmar na agenda cancela o que ainda não saiu
update agendamentos set status = 'confirmado' where id = :'ag_ca';
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_ca' and estado = 'pendente') = 0, 'consulta confirmada: lembretes pendentes cancelados');
update agendamentos set status = 'agendado' where id = :'ag_ca';
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_ca' and estado = 'pendente') = 2, 'voltou a aguardando: lembretes voltam');
reset role;

-- (d) envio: reserva na hora, nunca duas vezes
update lembretes set enviar_em = now() - interval '1 minute' where agendamento_id = :'ag_ca' and tipo = 'vespera';
set role service_role;
select t.ok((select count(*) from reservar_lembretes(10)) = 1, 'reserva o lembrete que está na hora');
select t.ok((select count(*) from reservar_lembretes(10)) = 0, 'segunda execução não pega o mesmo lembrete');
select id as lem_v from lembretes where agendamento_id = :'ag_ca' and tipo = 'vespera' and estado = 'enviando' \gset
select concluir_lembrete(:'lem_v', false, null, 'Meta 131000: falha temporária', false);
select t.ok((select estado = 'pendente' and tentativas = 1 and enviar_em > now() from lembretes where id = :'lem_v'), 'falha temporária: tenta de novo mais tarde');
update lembretes set enviar_em = now() - interval '1 minute' where id = :'lem_v';
select count(*) from reservar_lembretes(10) \gset
select concluir_lembrete(:'lem_v', true, 'wamid.LEM1', null, false);
select t.ok((select estado = 'enviado' and wa_msg_id = 'wamid.LEM1' and enviado_em is not null from lembretes where id = :'lem_v'), 'envio concluído fica registrado');
reset role;

-- (e) respostas
set role service_role;
select t.ok((responder_lembrete(:'salao_a', '5511888880000', :'lem_v', 'confirmou') ->> 'motivo') = 'telefone_diferente', 'resposta de outro telefone é recusada');
select t.ok((select status = 'agendado' from agendamentos where id = :'ag_ca'), 'e não muda a consulta');
select t.ok(lembrete_aberto(:'salao_a', '5511955550002') = :'lem_v', 'lembrete aberto é encontrado pelo telefone');
select t.ok((responder_lembrete(:'salao_a', '5511955550002', :'lem_v', 'confirmou') ->> 'ok')::boolean, 'cliente confirma pelo botão');
select t.ok((select status = 'confirmado' from agendamentos where id = :'ag_ca'), 'consulta fica confirmada');
select t.ok((responder_lembrete(:'salao_a', '5511955550002', :'lem_v', 'cancelou') ->> 'repetida')::boolean, 'segundo toque não desfaz a confirmação');
select t.ok((select status = 'confirmado' from agendamentos where id = :'ag_ca'), 'consulta continua confirmada');
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_ca' and estado = 'pendente') = 0, 'confirmou: o segundo aviso não será enviado');
reset role;

-- (f) cancelar e remarcar
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into clientes (nome, telefone) values ('Bia Remarca', '11955550003') returning id as pac_b \gset
select registrar_aceite_contato(:'pac_b') as aceite_b \gset
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim, origem)
  values (:'pac_b', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg14'::timestamptz + interval '2 days', :'seg14'::timestamptz + interval '2 days 45 minutes', 'interno') returning id as ag_b \gset
reset role;
update lembretes set enviar_em = now() - interval '1 minute' where agendamento_id = :'ag_b' and tipo = 'vespera';
set role service_role;
select count(*) from reservar_lembretes(10) \gset
select id as lem_b from lembretes where agendamento_id = :'ag_b' and tipo = 'vespera' and estado = 'enviando' \gset
select concluir_lembrete(:'lem_b', true, 'wamid.LEM2', null, false);
select t.ok((responder_lembrete(:'salao_a', '5511955550003', :'lem_b', 'remarcar') ->> 'acao') = 'remarcar', 'pedido de remarcar é registrado');
select t.ok((select status = 'agendado' from agendamentos where id = :'ag_b'), 'remarcar não cancela sozinho');
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_b' and tipo = 'mesmo_dia' and estado = 'pendente') = 1, 'segundo aviso continua na fila (será ignorado por já ter resposta)');
reset role;

-- (g) PARAR
set role service_role;
select t.ok(recusar_lembretes(:'salao_a', '5511955550003'), 'cliente pede para parar');
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_b' and estado = 'pendente') = 0, 'parar cancela lembretes pendentes');
reset role;

-- (h) desligar no salão
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into clientes (nome, telefone) values ('Duda Desligado', '11955550004') returning id as pac_d \gset
select registrar_aceite_contato(:'pac_d') as aceite_d \gset
update saloes set lembretes_ativos = false where id = :'salao_a';
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, fim, origem)
  values (:'pac_d', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg14'::timestamptz + interval '3 days', :'seg14'::timestamptz + interval '3 days 45 minutes', 'interno') returning id as ag_d \gset
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_d') = 0, 'salão com lembretes desligados não programa nada');
update saloes set lembretes_ativos = true where id = :'salao_a';
select t.ok((select count(*) from lembretes where agendamento_id = :'ag_d' and estado = 'pendente') = 2, 'religar programa as consultas futuras');
reset role;

-- (i) isolamento e permissões
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from lembretes) = 0, 'outro salão não vê lembretes');
select t.erro($$insert into lembretes (salao_id, agendamento_id, tipo, inicio_ref, enviar_em) values (gen_random_uuid(), gen_random_uuid(), 'vespera', now(), now())$$, '42501', 'ninguém grava lembrete pelo app');
select t.erro($$select reservar_lembretes(5)$$, '42501', 'usuário logado não executa o envio');
reset role;
set role anon;
select t.erro($$select * from lembretes$$, '42501', 'anônimo não lê lembretes');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok((select count(*) from lembretes) > 0, 'recepção vê o estado dos lembretes');
reset role;

-- 11) Endurecimento (0004)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro($$insert into clientes (nome, consentimento_em) values ('Forjado', now())$$, '42501', 'ninguém grava aceite direto no cliente');
select t.erro(format($q$update clientes set consentimento_em = now() where id = %L$q$, :'pac_sa'), '42501', 'ninguém altera o aceite pela API');
select t.erro(format($q$update clientes set recusou_lembretes_em = null where id = %L$q$, :'pac_b'), '42501', 'ninguém desfaz o PARAR do cliente pela API');
select t.erro($$update saloes set slug = 'outro-endereco'$$, '42501', 'admin não troca o slug pela API');
select t.erro($$update membros set salao_id = gen_random_uuid()$$, '42501', 'admin não troca o salão de um membro');
select t.ok(registrar_aceite_contato(:'pac_sa'), 'equipe registra o aceite pela função');
select t.ok((select consentimento_em is not null from clientes where id = :'pac_sa'), 'aceite fica gravado');
select t.ok(not registrar_aceite_contato(:'pac_sa'), 'registrar de novo não muda nada');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok(not registrar_aceite_contato(:'pac_ca'), 'outro salão não registra aceite de cliente alheio');
reset role;
set role anon;
select t.erro($$select tel_nacional('11999990000')$$, '42501', 'anônimo não executa funções públicas');
select t.erro($$select registrar_aceite_contato(gen_random_uuid())$$, '42501', 'anônimo não registra aceite');
reset role;
select t.ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prosecdef and not coalesce(p.proconfig, '{}') @> array['search_path=public, pg_temp']), 'toda função definer fixa o search_path com pg_temp');

-- teto de consultas futuras marcadas pelo robô
insert into clientes (salao_id, nome, telefone, consentimento_em) values (:'salao_a', 'Zeca Spammer', '11955550009', now()) returning id as pac_z \gset
insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fim, origem) select :'salao_a', :'pac_z', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg14'::timestamptz + (n || ' days')::interval + interval '1 hour', :'seg14'::timestamptz + (n || ' days')::interval + interval '1 hour 45 minutes', 'whatsapp' from generate_series(11, 13) n;
select t.erro(format($q$insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fim, origem) values (%L, %L, 'a0000000-0000-0000-0000-000000000002', %L, %L::timestamptz + interval '14 days 1 hour', %L::timestamptz + interval '14 days 1 hour 45 minutes', 'whatsapp')$q$, :'salao_a', :'pac_z', :'srv_a', :'seg14', :'seg14'), '22023', 'robô não marca a 4ª consulta futura do mesmo cliente');

-- mensagem não tratada tem no máximo 3 reenvios; excesso de mensagens vira "limitado"
set role service_role;
select receber_mensagem(:'salao_a', '5511977770001', 'Teste', 'wamid.RETRY', 'texto', 'oi') as r0 \gset
select t.ok((receber_mensagem(:'salao_a', '5511977770001', 'Teste', 'wamid.RETRY', 'texto', 'oi') ->> 'nova')::boolean, 'reenvio 1 é reprocessado');
select t.ok((receber_mensagem(:'salao_a', '5511977770001', 'Teste', 'wamid.RETRY', 'texto', 'oi') ->> 'nova')::boolean, 'reenvio 2 é reprocessado');
select t.ok((receber_mensagem(:'salao_a', '5511977770001', 'Teste', 'wamid.RETRY', 'texto', 'oi') ->> 'nova')::boolean, 'reenvio 3 é reprocessado');
select t.ok((receber_mensagem(:'salao_a', '5511977770001', 'Teste', 'wamid.RETRY', 'texto', 'oi') ->> 'nova')::boolean = false, 'depois de 3 reenvios desiste');
select count(*) from (select receber_mensagem(:'salao_a', '5511977770002', 'Flood', 'wamid.F' || n, 'texto', 'x') from generate_series(1, 31) n) q \gset
select t.ok((receber_mensagem(:'salao_a', '5511977770002', 'Flood', 'wamid.F99', 'texto', 'x') ->> 'limitado')::boolean, 'mais de 30 mensagens em 10 minutos ficam limitadas');
select t.ok(not (receber_mensagem(:'salao_a', '5511977770001', 'Teste', 'wamid.OK1', 'texto', 'oi') ->> 'limitado')::boolean, 'conversa normal não é limitada');
reset role;

-- 12) Agenda de salão (0007): fases, encaixe na pausa, bloqueios e jornada
select (date_trunc('week', now() + interval '35 days 5 hours')::date) as segd \gset
select ((:'segd'::date + time '10:00') at time zone 'America/Sao_Paulo') as d0 \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select id as srv_cor from servicos where nome = 'Coloração' \gset
select id as srv_cm from servicos where nome = 'Corte masculino' \gset
select t.ok((select duracao_min = 120 and jsonb_array_length(fases) = 3 from servicos where id = :'srv_cor'), 'coloração nasce com aplicação, pausa e finalização');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio)
  values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cor', :'d0') returning id as ag_cor \gset
select t.ok((select fim from agendamentos where id = :'ag_cor') = :'d0'::timestamptz + interval '120 minutes', 'o fim sai da soma das fases');
select t.ok((select a.fases = s.fases from agendamentos a join servicos s on s.id = a.servico_id where a.id = :'ag_cor'), 'o agendamento guarda as fases do serviço');
select t.ok((select count(*) from ocupacoes where agendamento_id = :'ag_cor') = 2, 'só as fases de trabalho ocupam o profissional');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio)
  values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'d0'::timestamptz + interval '45 minutes') returning id as ag_enc \gset
select t.ok(true, 'encaixe na pausa da química é aceito');
select t.erro(format($q$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (%L, 'a0000000-0000-0000-0000-000000000002', %L, %L::timestamptz + interval '20 minutes')$q$, :'pac_a', :'srv_cm', :'d0'),
  '23P01', 'não encaixa durante a aplicação');
select t.erro(format($q$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (%L, 'a0000000-0000-0000-0000-000000000002', %L, %L::timestamptz + interval '60 minutes')$q$, :'pac_a', :'srv_a', :'d0'),
  '23P01', 'serviço que invade a finalização é recusado');
update agendamentos set status = 'cancelado' where id = :'ag_enc';
select t.ok((select count(*) from ocupacoes where agendamento_id = :'ag_enc') = 0, 'cancelar libera as ocupações');
update agendamentos set inicio = inicio + interval '1 day' where id = :'ag_cor';
select t.ok((select min(lower(periodo)) from ocupacoes where agendamento_id = :'ag_cor') = :'d0'::timestamptz + interval '1 day', 'remarcar move as ocupações');
select t.ok((select fim from agendamentos where id = :'ag_cor') = :'d0'::timestamptz + interval '1 day 120 minutes', 'remarcar recalcula o fim');
select t.erro($$update servicos set fases = '[{"tipo":"pausa","min":10}]' where nome = 'Escova'$$, '23514', 'serviço não começa com pausa');
select t.erro($$update servicos set fases = '[{"tipo":"trabalho","min":10},{"tipo":"pausa","min":10}]' where nome = 'Escova'$$, '23514', 'serviço não termina em pausa');
select t.erro($$update servicos set fases = '[{"tipo":"trabalho","min":10},{"tipo":"pausa","min":10},{"tipo":"pausa","min":10},{"tipo":"trabalho","min":10}]' where nome = 'Escova'$$, '23514', 'duas pausas seguidas são recusadas');
select t.erro($$update servicos set fases = '[{"tipo":"trabalho","min":"x"}]' where nome = 'Escova'$$, '23514', 'minutos precisam ser número');
update servicos set fases = '[{"tipo":"trabalho","min":20},{"tipo":"pausa","min":30},{"tipo":"trabalho","min":10}]' where nome = 'Hidratação';
select t.ok((select duracao_min from servicos where nome = 'Hidratação') = 60, 'a duração vira a soma das fases');
update servicos set duracao_min = 50 where nome = 'Escova';
select t.ok((select fases from servicos where nome = 'Escova') = '[{"tipo":"trabalho","min":50}]'::jsonb, 'mudar só a duração vira uma fase única');
select t.ok((select fases from agendamentos where id = :'ag_cor') -> 0 ->> 'min' = '40', 'mudar o catálogo não mexe no que já está marcado');
select t.erro($$insert into ocupacoes (salao_id, profissional_id, bloqueio_id, periodo) values (meu_salao(), auth.uid(), gen_random_uuid(), tstzrange(now(), now() + interval '1 hour'))$$, '42501', 'ninguém grava ocupação pelo app');
reset role;

-- bloqueios
select ((:'segd'::date + 3 + time '10:00') at time zone 'America/Sao_Paulo') as d3 \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
insert into bloqueios (profissional_id, inicio, fim, motivo)
  values ('a0000000-0000-0000-0000-000000000002', :'d3', :'d3'::timestamptz + interval '2 hours', 'Curso') returning id as bloq \gset
select t.ok((select count(*) from ocupacoes where bloqueio_id = :'bloq') = 1, 'profissional bloqueia a própria agenda');
select t.erro(format($q$insert into bloqueios (profissional_id, inicio, fim) values ('a0000000-0000-0000-0000-000000000001', %L, %L::timestamptz + interval '1 hour')$q$, :'d3', :'d3'),
  '42501', 'profissional não bloqueia a agenda do colega');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro(format($q$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (%L, 'a0000000-0000-0000-0000-000000000002', %L, %L::timestamptz + interval '30 minutes')$q$, :'pac_a', :'srv_cm', :'d3'),
  '23P01', 'não agenda em cima de um bloqueio');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio)
  values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'d3'::timestamptz + interval '3 hours') returning id as ag_d3 \gset
select t.erro(format($q$insert into bloqueios (profissional_id, inicio, fim) values ('a0000000-0000-0000-0000-000000000002', %L::timestamptz + interval '3 hours', %L::timestamptz + interval '4 hours')$q$, :'d3', :'d3'),
  '23P01', 'não bloqueia em cima de horário marcado');
insert into bloqueios (profissional_id, inicio, fim) values ('a0000000-0000-0000-0000-000000000001', :'d3', :'d3'::timestamptz + interval '1 hour');
select t.ok(true, 'recepção bloqueia a agenda de qualquer profissional');
delete from bloqueios where id = :'bloq';
select t.ok((select count(*) from ocupacoes where bloqueio_id = :'bloq') = 0, 'apagar o bloqueio libera o horário');
select t.erro(format($q$update bloqueios set fim = fim + interval '1 day' where id = %L$q$, :'bloq'), '42501', 'bloqueio não é editado, só apagado');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from bloqueios) = 0 and (select count(*) from ocupacoes) = 0, 'outro salão não vê bloqueios nem ocupações');
select t.erro(format($q$insert into bloqueios (salao_id, profissional_id, inicio, fim) values (%L, 'a0000000-0000-0000-0000-000000000002', now() + interval '50 days', now() + interval '51 days')$q$, :'salao_a'), '42501', 'outro salão não bloqueia a agenda alheia');
reset role;

-- jornada: almoço, folga semanal e expediente próprio
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
with u as (update membros set almoco_inicio = '12:00', almoco_fim = '12:40' where user_id = auth.uid() returning 1) select t.ok((select count(*) from u) = 0, 'profissional não muda a própria jornada');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update membros set almoco_inicio = '12:00', almoco_fim = '12:40' where user_id = 'a0000000-0000-0000-0000-000000000002';
select t.erro($$update membros set almoco_inicio = '13:00', almoco_fim = null where user_id = 'a0000000-0000-0000-0000-000000000002'$$, '23514', 'almoço precisa de início e fim');
reset role;
set role service_role;
select t.ok(not cabe_na_jornada(:'salao_a', 'a0000000-0000-0000-0000-000000000002', (:'segd'::date + time '12:10') at time zone 'America/Sao_Paulo', (select fases from servicos where id = :'srv_cm')), 'robô não marca corte no almoço');
select t.ok(cabe_na_jornada(:'salao_a', 'a0000000-0000-0000-0000-000000000002', (:'segd'::date + time '11:20') at time zone 'America/Sao_Paulo', (select fases from servicos where id = :'srv_cor')), 'a pausa da química pode cair no almoço');
select t.ok(not cabe_na_jornada(:'salao_a', 'a0000000-0000-0000-0000-000000000002', (:'segd'::date + time '11:40') at time zone 'America/Sao_Paulo', (select fases from servicos where id = :'srv_cor')), 'mas a aplicação não');
reset role;
update membros set dias_semana = '{2,3,4,5,6}', entrada = '09:00', saida = '17:00' where user_id = 'a0000000-0000-0000-0000-000000000002';
set role service_role;
select t.ok(not cabe_na_jornada(:'salao_a', 'a0000000-0000-0000-0000-000000000002', (:'segd'::date + time '10:00') at time zone 'America/Sao_Paulo', (select fases from servicos where id = :'srv_cm')), 'robô respeita a folga semanal do profissional');
select t.ok(cabe_na_jornada(:'salao_a', 'a0000000-0000-0000-0000-000000000002', (:'segd'::date + 1 + time '09:00') at time zone 'America/Sao_Paulo', (select fases from servicos where id = :'srv_cm')), 'robô marca dentro do expediente do profissional');
select t.ok(not cabe_na_jornada(:'salao_a', 'a0000000-0000-0000-0000-000000000002', (:'segd'::date + 1 + time '16:45') at time zone 'America/Sao_Paulo', (select fases from servicos where id = :'srv_cm')), 'robô não passa da saída do profissional');
reset role;
set role anon;
select t.erro($$select cabe_na_jornada(gen_random_uuid(), gen_random_uuid(), now(), '[]')$$, '42501', 'anônimo não consulta a jornada');
reset role;

-- 13) Comanda e caixa (0008)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update servicos set preco_centavos = 5000 where nome = 'Escova';
insert into produtos (nome, preco_centavos) values ('Shampoo', 4000) returning id as prod \gset
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro($$insert into produtos (nome, preco_centavos) values ('X', 1)$$, '42501', 'recepção não cadastra produto');
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
select t.erro(format($q$select fechar_comanda(%L)$q$, :'cmd'), '55000', 'sem caixa aberto a comanda não fecha');
insert into caixas (troco_inicial_centavos) values (10000) returning id as cx \gset
select t.erro($$insert into caixas (troco_inicial_centavos) values (0)$$, '23505', 'só um caixa aberto por salão');
insert into comanda_itens (comanda_id, tipo, produto_id, descricao, profissional_id, preco_centavos) values (:'cmd', 'produto', :'prod', 'Shampoo', 'a0000000-0000-0000-0000-000000000002', 4000);
insert into comanda_itens (comanda_id, tipo, descricao, profissional_id, preco_centavos) values (:'cmd', 'gorjeta', 'Gorjeta', 'a0000000-0000-0000-0000-000000000002', 1000);
select t.erro(format($q$insert into comanda_itens (comanda_id, tipo, descricao, preco_centavos) values (%L, 'servico', 'x', 100)$q$, :'cmd'), '23514', 'serviço exige serviço e profissional');
update comandas set desconto_centavos = 500 where id = :'cmd';
select t.ok((select total = 9500 and receita = 8500 and gorjetas = 1000 and pago = 0 from total_comanda(:'cmd')), 'total soma itens, gorjeta e desconto');
select t.erro(format($q$select fechar_comanda(%L)$q$, :'cmd'), '22023', 'não fecha sem pagar o total');
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd', 'pix', 5000), (:'cmd', 'dinheiro', 4500);
select t.erro(format($q$insert into comanda_pagamentos (comanda_id, forma, valor_centavos, parcelas) values (%L, 'pix', 1, 3)$q$, :'cmd'), '23514', 'só crédito parcela');
select t.erro(format($q$update comandas set status = 'fechada' where id = %L$q$, :'cmd'), '42501', 'comanda só fecha pela função');
select fechar_comanda(:'cmd');
select t.ok((select status = 'fechada' and caixa_id = :'cx'::uuid from comandas where id = :'cmd'), 'comanda fecha no caixa aberto');
select t.erro(format($q$insert into comanda_itens (comanda_id, tipo, descricao, profissional_id, preco_centavos) values (%L, 'gorjeta', 'x', 'a0000000-0000-0000-0000-000000000002', 100)$q$, :'cmd'), '55000', 'comanda fechada não recebe item');
select t.erro(format($q$delete from comanda_pagamentos where comanda_id = %L$q$, :'cmd'), '55000', 'pagamento de comanda fechada não some');
select t.erro(format($q$update comandas set desconto_centavos = 0 where id = %L$q$, :'cmd'), '55000', 'comanda fechada não muda');
select t.erro(format($q$select reabrir_comanda(%L)$q$, :'cmd'), '42501', 'recepção não reabre comanda');
-- comanda ligada a um horário conclui o horário
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'d0'::timestamptz + interval '2 days') returning id as ag_cmd \gset
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd2 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, agendamento_id, descricao, profissional_id, preco_centavos) values (:'cmd2', 'servico', :'srv_a', :'ag_cmd', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd2', 'credito', 5000);
select fechar_comanda(:'cmd2');
select t.ok((select status from agendamentos where id = :'ag_cmd') = 'concluido', 'fechar a comanda conclui o horário');
-- cancelar
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd3 \gset
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd3', 'pix', 100);
select t.erro(format($q$update comandas set status = 'cancelada' where id = %L$q$, :'cmd3'), '42501', 'recepção não cancela comanda com pagamento');
insert into caixa_movimentos (caixa_id, tipo, valor_centavos, motivo) values (:'cx', 'sangria', 2000, 'Depósito');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro(format($q$insert into caixa_movimentos (caixa_id, tipo, valor_centavos) values (%L, 'sangria', 100)$q$, :'cx'), '42501', 'profissional não faz sangria');
select t.erro(format($q$select fechar_caixa(%L, '{}', null)$q$, :'cx'), '42501', 'profissional não fecha o caixa');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update comandas set status = 'cancelada' where id = :'cmd3';
select t.ok((select status from comandas where id = :'cmd3') = 'cancelada', 'administrador cancela comanda com pagamento');
select reabrir_comanda(:'cmd');
select t.ok((select status = 'aberta' and caixa_id is null from comandas where id = :'cmd'), 'administrador reabre comanda do caixa aberto');
select fechar_comanda(:'cmd');
select resumo_caixa(:'cx') as res \gset
select t.ok((:'res'::jsonb -> 'formas' ->> 'pix')::int = 5000 and (:'res'::jsonb -> 'formas' ->> 'dinheiro')::int = 4500 and (:'res'::jsonb -> 'formas' ->> 'credito')::int = 5000, 'resumo por forma de pagamento');
select t.ok((:'res'::jsonb ->> 'dinheiro_esperado')::int = 12500, 'dinheiro esperado = troco + dinheiro − sangria');
select t.ok((:'res'::jsonb ->> 'receita')::int = 13500 and (:'res'::jsonb ->> 'gorjetas')::int = 1000 and (:'res'::jsonb ->> 'comandas')::int = 2, 'receita sem gorjeta e comandas cancelada fora');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from comandas) = 0 and (select count(*) from comanda_itens) = 0 and (select count(*) from caixas) = 0, 'outro salão não vê comandas nem caixa');
select t.ok(resumo_caixa(:'cx') is null, 'outro salão não lê o resumo do caixa alheio');
select t.erro(format($q$select fechar_comanda(%L)$q$, :'cmd3'), 'P0002', 'outro salão não fecha comanda alheia');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select fechar_caixa(:'cx', '{"dinheiro": 12000}', 'faltaram 5 reais') as fech \gset
select t.ok((select fechado_em is not null and (contado ->> 'dinheiro')::int = 12000 and (esperado ->> 'dinheiro_esperado')::int = 12500 from caixas where id = :'cx'), 'fechamento guarda contado e esperado');
select t.erro(format($q$insert into caixa_movimentos (caixa_id, tipo, valor_centavos) values (%L, 'suprimento', 100)$q$, :'cx'), '55000', 'caixa fechado não recebe movimento');
select t.erro(format($q$select reabrir_comanda(%L)$q$, :'cmd'), '42501', 'recepção não reabre');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro(format($q$select reabrir_comanda(%L)$q$, :'cmd'), '55000', 'comanda de caixa fechado não reabre');
insert into caixas (troco_inicial_centavos) values (0);
select t.ok(true, 'novo caixa abre depois do fechamento');
reset role;
set role anon;
select t.erro(format($q$select fechar_comanda(%L)$q$, :'cmd'), '42501', 'anônimo não fecha comanda');
reset role;

-- 14) Comissão, vales, pagamento e Salão Parceiro (0009)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from regras_comissao) = 2, 'salão nasce com regra padrão de serviço e de produto');
select t.ok((select vinculo from membros where user_id = auth.uid()) = 'socio', 'quem criou o salão é sócio');
select t.ok((select vinculo from membros where user_id = 'a0000000-0000-0000-0000-000000000002') = 'parceiro', 'profissional nasce como parceiro');
reset role;
-- comandas da seção 13: escova 5000 e shampoo 4000 com desconto 500 na comanda, gorjeta 1000; escova 5000 no crédito
select t.ok((select sum(valor_centavos) from comissoes where profissional_id = 'a0000000-0000-0000-0000-000000000002' and papel = 'profissional') = 1889 + 2000, 'comissão de 40% sobre o serviço já com a parte do desconto da comanda');
select t.ok((select valor_centavos from comissoes where papel = 'vendedor') = 378, 'comissão de 10% na venda de produto');
select t.ok((select valor_centavos from comissoes where papel = 'gorjeta') = 1000, 'gorjeta vai inteira para o profissional');
select t.ok((select count(*) from comissoes where comanda_id = :'cmd') = 3, 'reabrir e fechar de novo não duplica comissões');

insert into auth.users (id) values ('a0000000-0000-0000-0000-000000000005');
insert into membros (user_id, salao_id, papel, nome, vinculo) values ('a0000000-0000-0000-0000-000000000005', :'salao_a', 'profissional', 'Lia', 'clt');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update saloes set taxa_credito = 5, comissao_desconta_taxa = true, comissao_desconta_custo = true;
update servicos set custo_produto_centavos = 500 where id = :'srv_a';
insert into regras_comissao (tipo, profissional_id, servico_id, percentual, assistente_percentual) values ('servico', 'a0000000-0000-0000-0000-000000000002', :'srv_a', 50, 10);
select t.erro($$insert into regras_comissao (tipo, percentual) values ('servico', 30)$$, '23505', 'uma regra por combinação');
select t.erro($$insert into regras_comissao (tipo, percentual, assistente_percentual) values ('produto', 10, 5)$$, '23514', 'produto não tem assistente');
-- parceiro com assistente, pago no crédito: base = 10000 − 500 de taxa − 500 de custo
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd4 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, assistente_id, preco_centavos) values (:'cmd4', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000005', 10000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd4', 'credito', 10000);
select fechar_comanda(:'cmd4');
select t.ok((select base_centavos = 9000 and taxa_centavos = 500 and custo_centavos = 500 and valor_centavos = 4500 from comissoes where comanda_id = :'cmd4' and papel = 'profissional'), 'regra do profissional no serviço vence e desconta taxa e custo');
select t.ok((select valor_centavos from comissoes where comanda_id = :'cmd4' and papel = 'assistente') = 1000, 'assistente CLT recebe a parte dela sem desconto de taxa nem produto');
-- CLT: nem taxa nem custo saem da base
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd5 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd5', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000005', 10000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd5', 'credito', 10000);
select fechar_comanda(:'cmd5');
select t.ok((select base_centavos = 10000 and taxa_centavos = 0 and custo_centavos = 0 and valor_centavos = 4000 from comissoes where comanda_id = :'cmd5'), 'CLT nunca tem taxa do cartão nem produto descontados');
-- sócio não gera comissão
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd6 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd6', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000001', 5000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd6', 'pix', 5000);
select fechar_comanda(:'cmd6');
select t.ok((select count(*) from comissoes where comanda_id = :'cmd6') = 0, 'sócio não recebe comissão');
reset role;

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from comissoes where profissional_id <> auth.uid()) = 0 and (select count(*) from comissoes) > 0, 'profissional vê só as próprias comissões');
select t.erro($$insert into regras_comissao (tipo, percentual, profissional_id) values ('servico', 90, auth.uid())$$, '42501', 'profissional não muda a própria regra');
select t.erro($$insert into vales (profissional_id, valor_centavos) values (auth.uid(), 100)$$, '42501', 'profissional não lança vale');
select t.erro($$select pagar_profissional(auth.uid(), current_date - 1, current_date + 1, 'pix')$$, '42501', 'profissional não registra pagamento');
select t.ok((select count(*) from relatorio_parceria(current_date - 30, current_date + 1)) = 0, 'profissional não lê o relatório da parceria');
with u as (update membros set vinculo = 'clt' where user_id = auth.uid() returning 1) select t.ok((select count(*) from u) = 0, 'profissional não muda o próprio vínculo');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok((select count(*) from comissoes) = 0, 'recepção não vê comissões');
insert into vales (profissional_id, valor_centavos, motivo) values ('a0000000-0000-0000-0000-000000000002', 1000, 'Adiantamento');
select t.ok(true, 'recepção lança vale');
reset role;

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select sum(valor_centavos) filter (where papel <> 'gorjeta') as a_com, sum(valor_centavos) filter (where papel = 'gorjeta') as a_gor
  from comissoes where profissional_id = 'a0000000-0000-0000-0000-000000000002' \gset
select (select cota_salao_centavos from relatorio_parceria(current_date - 1, current_date + 1) where profissional_id = 'a0000000-0000-0000-0000-000000000002') as cota_salao \gset
select t.ok((select servicos_centavos - cota_profissional_centavos + (select sum(valor_centavos) from comissoes where papel = 'vendedor') from relatorio_parceria(current_date - 1, current_date + 1) where profissional_id = 'a0000000-0000-0000-0000-000000000002') = :'cota_salao'::int, 'relatório separa cota do salão e cota do parceiro');
select t.ok((select count(*) from relatorio_parceria(current_date - 1, current_date + 1)) = 1, 'relatório só lista parceiros (não CLT nem sócio)');
select pagar_profissional('a0000000-0000-0000-0000-000000000002', current_date - 1, current_date + 1, 'pix') as fech \gset
select t.ok((select pago_centavos = :'a_com'::int + :'a_gor'::int - 1000 and vales_centavos = 1000 from fechamentos_comissao where id = :'fech'), 'pagamento = comissões + gorjetas − vales');
select t.ok((select count(*) from comissoes where profissional_id = 'a0000000-0000-0000-0000-000000000002' and fechamento_id is null) = 0, 'comissões pagas ficam ligadas ao pagamento');
select t.erro($$select pagar_profissional('a0000000-0000-0000-0000-000000000002', current_date - 1, current_date + 1, 'pix')$$, '22023', 'não paga duas vezes');
select t.erro(format($q$select reabrir_comanda(%L)$q$, :'cmd4'), '55000', 'comanda com comissão paga não reabre');
with d as (delete from vales where fechamento_id = :'fech' returning 1) select t.ok((select count(*) from d) = 0, 'vale descontado não é apagado');
select t.ok((select count(*) from vales where fechamento_id = :'fech') = 1, 'vale continua lá');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from comissoes) = 0 and (select count(*) from vales) = 0 and (select count(*) from fechamentos_comissao) = 0, 'outro salão não vê dinheiro alheio');
select t.erro($$select pagar_profissional('a0000000-0000-0000-0000-000000000002', current_date - 1, current_date + 1, 'pix')$$, 'P0002', 'outro salão não paga profissional alheio');
reset role;

-- 15) Ficha da cliente (0010)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
update clientes set alergias = 'amônia', tipo_cabelo = 'cacheado', origem = 'instagram' where id = :'pac_a';
select t.erro(format($q$update clientes set tipo_cabelo = 'roxo' where id = %L$q$, :'pac_a'), '23514', 'tipo de cabelo fora da lista é recusado');
insert into fichas_tecnicas (cliente_id, servico, tecnica, formula, pausa_min, resultado)
  values (:'pac_a', 'Coloração', 'Retoque de raiz', '[{"zona":"raiz","produto":"7.1","gramas":30,"oxidante":20,"oxidante_gramas":45}]', 35, 'Cobriu bem os brancos')
  returning id as ficha \gset
select t.ok((select formula -> 0 ->> 'produto' from fichas_tecnicas where id = :'ficha') = '7.1', 'profissional registra a fórmula');
select t.erro(format($q$insert into fichas_tecnicas (cliente_id, servico, formula) values (%L, 'Cor', '[{"gramas": 10}]')$q$, :'pac_a'), '23514', 'item da fórmula sem produto é recusado');
insert into testes_cliente (cliente_id, tipo, produto, resultado) values (:'pac_a', 'alergia', 'Koleston', 'sem_reacao');
select t.erro(format($q$update testes_cliente set resultado = 'reacao' where cliente_id = %L$q$, :'pac_a'), '42501', 'teste registrado não muda');
select t.erro(format($q$delete from testes_cliente where cliente_id = %L$q$, :'pac_a'), '42501', 'teste registrado não some');
insert into fotos_cliente (cliente_id, ficha_id, momento, caminho) values (:'pac_a', :'ficha', 'depois', :'salao_a' || '/x/depois.jpg');
select t.erro(format($q$insert into fotos_cliente (cliente_id, momento, caminho) values (%L, 'antes', 'outro-salao/foto.jpg')$q$, :'pac_a'), '42501', 'foto fora da pasta do salão é recusada');
select t.erro(format($q$update clientes set consentimento_imagem_em = now() where id = %L$q$, :'pac_a'), '42501', 'aceite de imagem não é gravado direto');
select registrar_aceite_imagem(:'pac_a', true);
select t.ok((select consentimento_imagem_em is not null from clientes where id = :'pac_a'), 'aceite de imagem pela função');
with d as (delete from fichas_tecnicas where id = :'ficha' returning 1) select t.ok((select count(*) from d) = 0, 'profissional não apaga ficha');
select t.erro(format($q$select unir_clientes(%L, %L)$q$, :'pac_a', :'pac_a'), '42501', 'profissional não une cadastros');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok((select count(*) from fichas_tecnicas where cliente_id = :'pac_a') = 1, 'recepção lê a ficha técnica');
with u as (update fichas_tecnicas set resultado = 'x' where id = :'ficha' returning 1) select t.ok((select count(*) from u) = 0, 'recepção não altera ficha de outro');
-- cadastro duplicado da mesma cliente (veio pelo WhatsApp)
insert into clientes (nome, telefone, email) values ('Marina S.', '11999990077', 'marina@exemplo.com') returning id as dup \gset
insert into testes_cliente (cliente_id, tipo, produto, resultado) values (:'dup', 'mecha', 'Descolorante', 'aprovado');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'dup', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'d0'::timestamptz + interval '9 days') returning id as ag_dup \gset
select unir_clientes(:'pac_a', :'dup');
select t.ok(not exists (select 1 from clientes where id = :'dup'), 'duplicado some depois de unir');
select t.ok((select cliente_id from agendamentos where id = :'ag_dup') = :'pac_a'::uuid, 'horários do duplicado passam para o cadastro que fica');
select t.ok((select count(*) from testes_cliente where cliente_id = :'pac_a') = 2, 'testes do duplicado passam junto');
select t.ok((select email from clientes where id = :'pac_a') = 'marina@exemplo.com', 'dados que faltavam vêm do duplicado');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from fichas_tecnicas) = 0 and (select count(*) from testes_cliente) = 0 and (select count(*) from fotos_cliente) = 0, 'outro salão não vê fichas, testes nem fotos');
select t.erro(format($q$select unir_clientes(%L, %L)$q$, :'pac_b', :'pac_a'), 'P0002', 'outro salão não une cadastro alheio');
select t.erro(format($q$select registrar_aceite_imagem(%L, true)$q$, :'pac_a'), 'P0002', 'outro salão não registra aceite alheio');
reset role;

-- 16) Agendamento online e sinal via Pix (0011)
update saloes set pix_chave = 'pix@studiobela.com', pix_nome = 'Studio Bela', pix_cidade = 'Sao Paulo' where slug = 'sorriso';
update servicos set preco_centavos = 20000, sinal_percentual = 30 where id = :'srv_cor';
select ((:'segd'::date + 2 + time '14:00') at time zone 'America/Sao_Paulo') as qua14 \gset
select ((:'segd'::date + 3 + time '14:00') at time zone 'America/Sao_Paulo') as qui14 \gset
select ((:'segd'::date + 4 + time '14:00') at time zone 'America/Sao_Paulo') as sex14 \gset
set role anon;
select t.erro(format($q$select agendar_online('sorriso', %L, 'a0000000-0000-0000-0000-000000000002', %L, 'Ana', '11988887777', true, '1.2.3.4', 'teste')$q$, :'srv_cor', :'qua14'), '42501', 'anônimo não chama a função direto (só o servidor)');
reset role;
set role service_role;
select agendar_online('sorriso', :'srv_cor', 'a0000000-0000-0000-0000-000000000002', :'qua14', 'Ana Paula', '(11) 98888-7777', true, '1.2.3.4', 'Mozilla') as r1 \gset
select (:'r1'::jsonb ->> 'agendamento_id') as ag_on, (:'r1'::jsonb ->> 'token') as tok_on \gset
select t.ok((:'r1'::jsonb ->> 'sinal_centavos')::int = 6000, 'sinal de 30% do preço');
select t.ok((select status = 'agendado' and origem = 'online' from agendamentos where id = :'ag_on'), 'horário com sinal fica aguardando o pagamento');
select t.ok((select status = 'pendente' and modo = 'pix_manual' from sinais where agendamento_id = :'ag_on'), 'sinal nasce pendente no Pix manual');
select t.ok((select texto like '%24 horas%' and ip = '1.2.3.4' and agente = 'Mozilla' from aceites_politica where agendamento_id = :'ag_on'), 'aceite da política guardado com texto, IP e aparelho');
select t.ok((select telefone = '11988887777' and consentimento_em is not null from clientes c join agendamentos a on a.cliente_id = c.id where a.id = :'ag_on'), 'cliente nova nasce com telefone e aceite');
select t.ok((horario_publico(:'tok_on') ->> 'servico') = 'Coloração' and (horario_publico(:'tok_on') -> 'sinal' ->> 'valor')::int = 6000, 'cliente vê o próprio horário pelo token');
select t.erro(format($q$select agendar_online('sorriso', %L, 'a0000000-0000-0000-0000-000000000002', %L, 'Outra', '11977776666', true, null, null)$q$, :'srv_cor', :'qua14'), '22023', 'horário ocupado é recusado');
select t.erro(format($q$select agendar_online('sorriso', %L, 'a0000000-0000-0000-0000-000000000002', %L, 'Outra', '123', true, null, null)$q$, :'srv_cor', :'sex14'), '22023', 'telefone inválido é recusado');
select t.erro(format($q$select agendar_online('sorriso', %L, 'a0000000-0000-0000-0000-000000000002', %L, 'Outra', '11977776666', false, null, null)$q$, :'srv_cor', :'sex14'), '22023', 'sem aceite de contato não marca');
select t.erro(format($q$select agendar_online('espacoluz', %L, 'a0000000-0000-0000-0000-000000000002', %L, 'Outra', '11977776666', true, null, null)$q$, :'srv_cor', :'sex14'), '22023', 'serviço de outro salão não é aceito');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro(format($q$select confirmar_sinal(%L)$q$, :'ag_on'), '42501', 'profissional não confirma sinal');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok((select count(*) from aceites_politica where agendamento_id = :'ag_on') = 1, 'recepção vê o aceite da política');
select confirmar_sinal(:'ag_on');
select t.ok((select status from agendamentos where id = :'ag_on') = 'confirmado' and (select status from sinais where agendamento_id = :'ag_on') = 'pago', 'confirmar o Pix confirma o horário');
select cliente_id as cli_on from agendamentos where id = :'ag_on' \gset
insert into comandas (cliente_id) values (:'cli_on') returning id as cmd_on \gset
select t.ok(usar_credito_sinal(:'cmd_on') = 6000, 'sinal entra na comanda');
select t.ok((select status from sinais where agendamento_id = :'ag_on') = 'usado', 'e fica marcado como usado');
select t.ok((select count(*) from comanda_pagamentos where comanda_id = :'cmd_on' and forma = 'sinal' and valor_centavos = 6000) = 1, 'o pagamento do sinal está na comanda');
select t.ok(usar_credito_sinal(:'cmd_on') = 0, 'e não é usado de novo');
reset role;
-- sem sinal: já nasce confirmado; cancelamento pela cliente dentro do prazo
set role service_role;
select agendar_online('sorriso', :'srv_cm', 'a0000000-0000-0000-0000-000000000002', :'sex14', 'Bia', '11966665555', true, null, null) as r2 \gset
select t.ok((select status from agendamentos where id = (:'r2'::jsonb ->> 'agendamento_id')::uuid) = 'confirmado' and (:'r2'::jsonb ->> 'sinal_centavos')::int = 0, 'serviço sem sinal nasce confirmado');
select t.ok(cancelar_online((:'r2'::jsonb ->> 'token')::uuid) = 'cancelado', 'cliente cancela pelo link dentro do prazo');
select t.ok(cancelar_online((:'r2'::jsonb ->> 'token')::uuid) = 'ja_cancelado', 'cancelar de novo não faz nada');
select t.ok(cancelar_online(gen_random_uuid()) = 'nao_encontrado', 'token falso não acha nada');
-- sinal não pago expira e libera o horário
select agendar_online('sorriso', :'srv_cor', 'a0000000-0000-0000-0000-000000000002', :'qui14', 'Caio', '11955554444', true, null, null) as r3 \gset
reset role;
update sinais set expira_em = now() - interval '1 minute' where agendamento_id = (:'r3'::jsonb ->> 'agendamento_id')::uuid;
set role service_role;
select t.ok(expirar_sinais() = 1, 'sinal vencido é expirado');
select t.ok((select status from agendamentos where id = (:'r3'::jsonb ->> 'agendamento_id')::uuid) = 'cancelado', 'horário sem sinal pago é cancelado sozinho');
select t.ok(not exists (select 1 from ocupacoes where agendamento_id = (:'r3'::jsonb ->> 'agendamento_id')::uuid), 'e a agenda fica livre de novo');
-- Mercado Pago: o webhook só confirma com o valor certo
select agendar_online('sorriso', :'srv_cor', 'a0000000-0000-0000-0000-000000000002', :'qui14', 'Davi', '11944443333', true, null, null) as r4 \gset
select registrar_cobranca_sinal((:'r4'::jsonb ->> 'agendamento_id')::uuid, 'TX1', '000201...', 'mp-123', 'mercadopago');
select t.ok((select modo from sinais where agendamento_id = (:'r4'::jsonb ->> 'agendamento_id')::uuid) = 'mercadopago', 'o modo gravado é o que foi gerado');
select t.ok(not sinal_pago_mp('mp-123', 6000, (select id from saloes where slug = 'espacoluz')), 'webhook de outro salão não confirma');
select t.ok(not sinal_pago_mp('mp-123', 100, :'salao_a'), 'pagamento menor que o sinal não confirma');
select t.ok(sinal_pago_mp('mp-123', 6000, :'salao_a'), 'pagamento certo confirma');
select t.ok((select status from agendamentos where id = (:'r4'::jsonb ->> 'agendamento_id')::uuid) = 'confirmado', 'horário confirmado pelo webhook');
select t.ok(not sinal_pago_mp('mp-123', 6000, :'salao_a'), 'webhook repetido não faz nada');
reset role;
-- salão com agendamento online desligado
update saloes set agendamento_online = false where slug = 'sorriso';
set role service_role;
select t.erro(format($q$select agendar_online('sorriso', %L, 'a0000000-0000-0000-0000-000000000002', %L, 'Eva', '11933332222', true, null, null)$q$, :'srv_cm', :'sex14'), 'P0002', 'link desligado não aceita marcação');
reset role;
update saloes set agendamento_online = true where slug = 'sorriso';
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from sinais) = 0 and (select count(*) from aceites_politica) = 0, 'outro salão não vê sinais nem aceites');
select t.erro(format($q$select confirmar_sinal(%L)$q$, :'ag_on'), 'P0002', 'outro salão não confirma sinal alheio');
select t.erro($$select * from pagamentos_contas$$, '42501', 'ninguém lê o token do Mercado Pago pela API');
reset role;

-- 17) Painel do dono (0012)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select painel(current_date - 1, current_date + 1) as pn \gset
select t.ok((:'pn'::jsonb ->> 'comandas')::int >= 5, 'painel conta as comandas fechadas');
select t.ok((:'pn'::jsonb ->> 'receita')::int = (:'pn'::jsonb ->> 'servicos')::int + (:'pn'::jsonb ->> 'produtos')::int - (select sum(desconto_centavos) from comandas where status = 'fechada'), 'receita = serviços + produtos − descontos, sem gorjeta');
select t.ok((:'pn'::jsonb ->> 'produtos')::int = 3778 + 222, 'venda de produto separada para o % de varejo');
select t.ok(jsonb_array_length(:'pn'::jsonb -> 'profissionais') >= 2, 'painel traz os números por profissional');
select t.erro($$select painel(current_date, current_date - 1)$$, '22023', 'período invertido é recusado');
select t.ok((select count(*) from clientes_sumidos()) >= 0, 'lista de clientes sumidas responde');
reset role;
-- cliente que veio duas vezes, com intervalo de 30 dias, e não volta há 90: está sumida
insert into clientes (salao_id, nome, telefone) values (:'salao_a', 'Rosa Sumida', '11922221111') returning id as sumida \gset
insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, status)
values (:'salao_a', :'sumida', 'a0000000-0000-0000-0000-000000000001', :'srv_cm', now() - interval '120 days', 'concluido'),
       (:'salao_a', :'sumida', 'a0000000-0000-0000-0000-000000000001', :'srv_cm', now() - interval '90 days', 'concluido');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok(exists (select 1 from clientes_sumidos() where cliente_id = :'sumida' and intervalo_dias = 30 and dias_sem_vir >= 89), 'cliente que passou do tempo de voltar aparece para a recepção');
select t.erro($$select painel(current_date - 1, current_date)$$, '42501', 'recepção não vê o painel financeiro');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from clientes_sumidos()) = 0, 'profissional não recebe a lista');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from clientes_sumidos() where cliente_id = :'sumida') = 0, 'outro salão não vê as sumidas alheias');
select t.ok((painel(current_date - 1, current_date + 1) ->> 'comandas')::int = 0, 'painel de outro salão não mistura dados');
reset role;

-- 18) Correções da revisão (0013)
-- sinal volta a ser crédito quando o pagamento sai da comanda ou a comanda é cancelada
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
delete from comanda_pagamentos where comanda_id = :'cmd_on' and forma = 'sinal';
select t.ok((select status from sinais where agendamento_id = :'ag_on') = 'credito', 'tirar o pagamento do sinal devolve o crédito');
select t.ok(usar_credito_sinal(:'cmd_on') = 6000, 'crédito pode ser usado de novo');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update comandas set status = 'cancelada' where id = :'cmd_on';
select t.ok((select status from sinais where agendamento_id = :'ag_on') = 'credito', 'cancelar a comanda devolve o crédito');
insert into comandas (cliente_id) values (:'cli_on') returning id as cmd_on2 \gset
select t.ok(usar_credito_sinal(:'cmd_on2') = 6000, 'crédito do sinal vale em outra comanda da mesma cliente');
reset role;

-- cliente cancelou e pagou depois: vira crédito, o horário não volta
set role service_role;
select agendar_online('sorriso', :'srv_cor', 'a0000000-0000-0000-0000-000000000002', :'sex14' ::timestamptz + interval '7 days', 'Fábia', '11911110000', true, null, null) as r5 \gset
select registrar_cobranca_sinal((:'r5'::jsonb ->> 'agendamento_id')::uuid, 'TX5', '000201...', 'mp-555', 'mercadopago');
select t.ok(cancelar_online((:'r5'::jsonb ->> 'token')::uuid) = 'cancelado', 'cliente cancela antes de pagar');
select t.ok((select status from sinais where agendamento_id = (:'r5'::jsonb ->> 'agendamento_id')::uuid) = 'cancelado', 'sinal fica cancelado, não expirado');
select t.ok(sinal_pago_mp('mp-555', 6000, :'salao_a'), 'pagamento atrasado é registrado');
select t.ok((select status from sinais where agendamento_id = (:'r5'::jsonb ->> 'agendamento_id')::uuid) = 'credito'
  and (select status from agendamentos where id = (:'r5'::jsonb ->> 'agendamento_id')::uuid) = 'cancelado', 'vira crédito e o horário cancelado não volta');
-- telefone de cliente já cadastrada: aceite não é herdado e a página mostra o nome digitado
reset role;
insert into clientes (salao_id, nome, telefone) values (:'salao_a', 'Helena Dona do Número', '11900003333') returning id as helena \gset
set role service_role;
select agendar_online('sorriso', :'srv_cm', 'a0000000-0000-0000-0000-000000000002', :'sex14' ::timestamptz + interval '8 days', 'Intrusa Silva', '11900003333', true, null, null) as r6 \gset
select t.ok((horario_publico((:'r6'::jsonb ->> 'token')::uuid) ->> 'cliente') = 'Intrusa', 'página mostra o nome digitado, não o do cadastro');
select t.ok((select consentimento_em is null from clientes where id = :'helena'), 'quem digita o telefone de outra pessoa não liga os lembretes dela');
reset role;
-- sem chave Pix e sem Mercado Pago, não há como cobrar sinal: o horário nasce confirmado
update saloes set pix_chave = null where slug = 'sorriso';
set role service_role;
select agendar_online('sorriso', :'srv_cor', 'a0000000-0000-0000-0000-000000000002', :'sex14' ::timestamptz + interval '14 days', 'Gil', '11900001111', true, null, null) as r7 \gset
select t.ok((:'r7'::jsonb ->> 'sinal_centavos')::int = 0 and (select status from agendamentos where id = (:'r7'::jsonb ->> 'agendamento_id')::uuid) = 'confirmado', 'sem meio de cobrança não cria sinal que vai expirar');
reset role;
update saloes set pix_chave = 'pix@studiobela.com' where slug = 'sorriso';

-- unir cadastro com comanda fechada e aceite de política
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select cliente_id as cli_r6 from agendamentos where id = (:'r6'::jsonb ->> 'agendamento_id')::uuid \gset
insert into clientes (nome, telefone) values ('Duplicada Fechada', '11900002222') returning id as dup2 \gset
insert into comandas (cliente_id) values (:'dup2') returning id as cmd_dup \gset
insert into comanda_itens (comanda_id, tipo, produto_id, descricao, preco_centavos) values (:'cmd_dup', 'produto', :'prod', 'Shampoo', 4000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_dup', 'pix', 4000);
select fechar_comanda(:'cmd_dup');
reset role;
update aceites_politica set cliente_id = :'dup2' where agendamento_id = (:'r7'::jsonb ->> 'agendamento_id')::uuid;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select unir_clientes(:'pac_a', :'dup2');
select t.ok((select cliente_id from comandas where id = :'cmd_dup') = :'pac_a'::uuid and (select status from comandas where id = :'cmd_dup') = 'fechada', 'unir leva junto a comanda fechada, que continua fechada');
select t.ok((select cliente_id from aceites_politica where agendamento_id = (:'r7'::jsonb ->> 'agendamento_id')::uuid) = :'pac_a'::uuid, 'o aceite da política não se perde ao unir');
select t.erro(format($q$update comandas set desconto_centavos = 1 where id = %L$q$, :'cmd_dup'), '55000', 'depois de unir a comanda fechada continua travada');

-- vale do caixa: vale e retirada juntos
select id as cx_atual from caixas where fechado_em is null \gset
select vale_do_caixa(:'cx_atual', 'a0000000-0000-0000-0000-000000000005', 700, 'ônibus');
select t.ok(exists (select 1 from vales where profissional_id = 'a0000000-0000-0000-0000-000000000005' and valor_centavos = 700)
  and exists (select 1 from caixa_movimentos where caixa_id = :'cx_atual' and tipo = 'sangria' and valor_centavos = 700 and motivo like 'Vale para Lia%'), 'vale do caixa grava o vale e a retirada');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro(format($q$select vale_do_caixa(%L, auth.uid(), 100, null)$q$, :'cx_atual'), '42501', 'profissional não tira vale do caixa');
reset role;

-- comissão do assistente: independe do principal e respeita o próprio vínculo
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into regras_comissao (tipo, profissional_id, servico_id, percentual, assistente_percentual) values ('servico', 'a0000000-0000-0000-0000-000000000001', :'srv_a', 0, 10);
-- sócio atende com assistente CLT, pago no crédito com taxa e custo ligados: o assistente recebe, sem taxa nem custo
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd7 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, assistente_id, preco_centavos) values (:'cmd7', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005', 10000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd7', 'credito', 10000);
select fechar_comanda(:'cmd7');
select t.ok((select count(*) from comissoes where comanda_id = :'cmd7' and papel = 'profissional') = 0, 'sócio continua sem comissão');
select t.ok((select valor_centavos = 1000 and taxa_centavos = 0 and custo_centavos = 0 from comissoes where comanda_id = :'cmd7' and papel = 'assistente'), 'assistente CLT de um sócio recebe sem desconto de taxa nem produto');

-- vale maior que o que há para receber fica em aberto
insert into vales (profissional_id, valor_centavos, data, motivo) values ('a0000000-0000-0000-0000-000000000005', 999999, current_date, 'Empréstimo');
select pagar_profissional('a0000000-0000-0000-0000-000000000005', current_date - 1, current_date + 1, 'pix') as fech_lia \gset
select t.ok((select pago_centavos >= 0 from fechamentos_comissao where id = :'fech_lia'), 'pagamento nunca fica negativo');
select t.ok((select fechamento_id is null from vales where valor_centavos = 999999), 'vale que não coube continua em aberto para o próximo pagamento');
reset role;

-- 19) Retorno automático e lista de espera (0014)
insert into clientes (salao_id, nome, telefone, consentimento_em) values (:'salao_a', 'Iara Espera', '11900004444', now()) returning id as iara \gset
select ((:'segd'::date + 15 + time '15:00') at time zone 'America/Sao_Paulo') as ter15 \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into lista_espera (cliente_id, servico_id, data_de, data_ate, periodo) values (:'iara', :'srv_cm', (:'ter15'::timestamptz at time zone 'America/Sao_Paulo')::date - 2, (:'ter15'::timestamptz at time zone 'America/Sao_Paulo')::date + 2, 'tarde') returning id as esp \gset
insert into lista_espera (cliente_id, servico_id, data_de, data_ate, periodo) values (:'helena', :'srv_cm', (:'ter15'::timestamptz at time zone 'America/Sao_Paulo')::date, (:'ter15'::timestamptz at time zone 'America/Sao_Paulo')::date, 'qualquer') returning id as esp_h \gset
insert into lista_espera (cliente_id, servico_id, data_de, data_ate, periodo) values (:'iara', :'srv_cm', current_date, current_date + 1, 'manha') returning id as esp_m \gset
select t.erro(format($q$insert into lista_espera (cliente_id, servico_id, data_de, data_ate) values (%L, %L, current_date, current_date + 200)$q$, :'iara', :'srv_cm'), '23514', 'espera de no máximo 90 dias');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'ter15') returning id as ag_vaga \gset
update agendamentos set status = 'cancelado' where id = :'ag_vaga';
select t.ok((select estado from lista_espera where id = :'esp') = 'avisado', 'cancelamento avisa quem espera aquele serviço naquele período');
select t.ok((select estado from lista_espera where id = :'esp_h') = 'aguardando', 'quem não aceitou WhatsApp não é avisado');
select t.ok((select estado from lista_espera where id = :'esp_m') = 'aguardando', 'quem espera outro dia ou período não é avisado');
reset role;
select t.ok((select count(*) from avisos where tipo = 'vaga' and cliente_id = :'iara' and (dados ->> 'inicio')::timestamptz = :'ter15'::timestamptz) = 1, 'aviso de vaga entra na fila');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from avisos) = 0, 'profissional não vê a fila de avisos');
reset role;
-- quem estava na espera e marcou sai da lista
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'iara', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'ter15');
select t.ok((select estado from lista_espera where id = :'esp') = 'marcado', 'quem marca sai da lista de espera');
reset role;
-- retorno: cortou há 35 dias (retorno de 30) e não marcou nada
update saloes set retorno_ativo = true where id = :'salao_a';
insert into clientes (salao_id, nome, telefone, consentimento_em) values (:'salao_a', 'Júlia Retorno', '11900005555', now()) returning id as julia \gset
insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, status)
  values (:'salao_a', :'julia', 'a0000000-0000-0000-0000-000000000001', :'srv_cm', now() - interval '35 days 5 hours', 'concluido');
set role service_role;
select programar_retornos() as n_ret \gset
select t.ok((select count(*) from avisos where tipo = 'retorno' and cliente_id = :'julia') = 1, 'convite de retorno programado para quem passou do prazo');
select t.ok((select dados ->> 'servico' from avisos where tipo = 'retorno' and cliente_id = :'julia') = 'Corte masculino', 'o convite fala do serviço certo');
select t.ok(not exists (select 1 from avisos where tipo = 'retorno' and cliente_id = :'sumida'), 'quem sumiu há muito tempo (ou sem aceite) não recebe convite automático');
select t.ok(programar_retornos() = 0, 'rodar de novo não duplica o convite');
-- envio: reserva o que está na hora, com o telefone no formato do WhatsApp
update avisos set enviar_em = now() - interval '1 minute' where tipo = 'retorno' and cliente_id = :'julia';
select t.ok((select count(*) from reservar_avisos(10) where wa_id = '5511900005555' and tipo = 'retorno') = 1, 'aviso de retorno é reservado para envio');
select id as av_j from avisos where cliente_id = :'julia' \gset
select concluir_aviso(:'av_j', true, 'wamid.R1', null, false);
select t.ok((select estado from avisos where id = :'av_j') = 'enviado', 'envio registrado');
reset role;
-- vaga com mais de 3 horas não é mais oferecida
update avisos set criado_em = now() - interval '4 hours', estado = 'pendente', enviar_em = now() - interval '4 hours' where tipo = 'vaga' and cliente_id = :'iara';
set role service_role;
select t.ok((select count(*) from reservar_avisos(10) where tipo = 'vaga') = 0, 'vaga velha não é enviada');
reset role;
select t.ok((select estado from avisos where tipo = 'vaga' and cliente_id = :'iara') = 'cancelado', 'e fica cancelada');
set role anon;
select t.erro($$select * from reservar_avisos(1)$$, '42501', 'anônimo não mexe na fila de avisos');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from lista_espera) = 0 and (select count(*) from avisos) = 0, 'outro salão não vê lista de espera nem avisos');
reset role;

-- 20) Estoque (0015)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into produtos (nome, tipo, unidade, conteudo, custo_centavos, estoque_minimo) values ('Tinta 7.1', 'uso', 'g', 60, 3500, 100) returning id as tinta \gset
insert into servico_insumos (servico_id, produto_id, quantidade) values (:'srv_cor', :'tinta', 45);
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into movimentos_estoque (produto_id, tipo, quantidade, custo_centavos, motivo) values (:'tinta', 'entrada', 300, 17500, '5 tubos');
insert into movimentos_estoque (produto_id, tipo, quantidade) values (:'prod', 'entrada', 10);
select t.ok((select estoque from produtos where id = :'tinta') = 300, 'entrada soma no estoque');
select t.erro(format($q$update produtos set estoque = 9999 where id = %L$q$, :'tinta'), '42501', 'saldo não muda direto, só por movimento');
select t.erro(format($q$insert into movimentos_estoque (produto_id, tipo, quantidade) values (%L, 'uso', -10)$q$, :'tinta'), '42501', 'consumo não é lançado à mão');
select t.erro(format($q$insert into servico_insumos (servico_id, produto_id, quantidade) values (%L, %L, 1)$q$, :'srv_a', :'tinta'), '42501', 'recepção não muda o consumo dos serviços');
-- comanda com coloração (consome 45 g) e 2 shampoos vendidos
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_e \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_e', 'servico', :'srv_cor', 'Coloração', 'a0000000-0000-0000-0000-000000000002', 20000);
insert into comanda_itens (comanda_id, tipo, produto_id, descricao, quantidade, preco_centavos) values (:'cmd_e', 'produto', :'prod', 'Shampoo', 2, 4000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_e', 'pix', 28000);
select estoque as antes_prod from produtos where id = :'prod' \gset
select fechar_comanda(:'cmd_e');
select t.ok((select estoque from produtos where id = :'tinta') = 255, 'serviço fechado consome o insumo sozinho');
select t.ok((select estoque from produtos where id = :'prod') = :'antes_prod'::numeric - 2, 'venda tira do estoque de revenda');
select ajustar_estoque(:'tinta', 250, 'contagem de sexta') as dif \gset
select t.ok(:'dif'::numeric = -5 and (select estoque from produtos where id = :'tinta') = 250, 'contagem lança a diferença');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select reabrir_comanda(:'cmd_e');
select t.ok((select estoque from produtos where id = :'tinta') = 295 and (select estoque from produtos where id = :'prod') = :'antes_prod'::numeric, 'reabrir a comanda devolve o que tinha saído');
select fechar_comanda(:'cmd_e');
select t.ok((select estoque from produtos where id = :'tinta') = 250, 'fechar de novo baixa de novo');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from movimentos_estoque) = 0, 'profissional não vê movimentos de estoque');
select t.erro(format($q$select ajustar_estoque(%L, 1, null)$q$, :'tinta'), '42501', 'profissional não ajusta estoque');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from servico_insumos) = 0 and (select count(*) from movimentos_estoque) = 0, 'outro salão não vê estoque alheio');
reset role;

-- 21) Pacotes, clube e cashback (0016)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update servicos set preco_centavos = 5000 where id = :'srv_a';
insert into pacotes (nome, tipo, preco_centavos, validade_dias) values ('10 escovas', 'pacote', 40000, 180) returning id as pct \gset
insert into pacote_itens (pacote_id, servico_id, quantidade) values (:'pct', :'srv_a', 10);
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro($$insert into pacotes (nome, preco_centavos) values ('X', 100)$$, '42501', 'recepção não cria pacote');
-- venda sem cliente não fecha
insert into comandas (cliente_id) values (null) returning id as cmd_pa \gset
insert into comanda_itens (comanda_id, tipo, pacote_id, descricao, preco_centavos) values (:'cmd_pa', 'pacote', :'pct', '10 escovas', 40000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_pa', 'pix', 40000);
select t.erro(format($q$select fechar_comanda(%L)$q$, :'cmd_pa'), '22023', 'pacote precisa de cliente');
update comandas set cliente_id = :'julia' where id = :'cmd_pa';
select fechar_comanda(:'cmd_pa');
select t.ok((select ps.total = 10 and ps.usado = 0 and ps.valor_unitario_centavos = 4000 from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id where pc.comanda_id = :'cmd_pa'), 'venda cria o saldo com o valor proporcional da sessão');
-- uso: a escova sai pelo valor da sessão e é paga com o pacote
insert into comandas (cliente_id) values (:'julia') returning id as cmd_u \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_u', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000) returning id as it_u \gset
select t.ok(usar_pacote(:'cmd_u') = 1, 'pacote cobre a escova');
select t.ok((select preco_centavos from comanda_itens where id = :'it_u') = 4000 and (select pago = total from total_comanda(:'cmd_u')), 'item vale a sessão e a comanda fica paga');
select t.ok(usar_pacote(:'cmd_u') = 0, 'a mesma escova não usa duas sessões');
select fechar_comanda(:'cmd_u');
select t.ok((select usado from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id where pc.comanda_id = :'cmd_pa') = 1, 'sessão descontada do saldo');
-- tirar o pagamento devolve a sessão e o preço
insert into comandas (cliente_id) values (:'julia') returning id as cmd_r \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_r', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000) returning id as it_r \gset
select usar_pacote(:'cmd_r');
delete from comanda_pagamentos where comanda_id = :'cmd_r' and forma = 'pacote';
select t.ok((select preco_centavos from comanda_itens where id = :'it_r') = 5000, 'tirar o pagamento do pacote devolve o preço');
select t.ok((select usado from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id where pc.comanda_id = :'cmd_pa') = 1, 'e a sessão volta para o saldo');
-- tirar o item também devolve a sessão
select usar_pacote(:'cmd_r');
delete from comanda_itens where id = :'it_r';
select t.ok((select usado from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id where pc.comanda_id = :'cmd_pa') = 1 and not exists (select 1 from comanda_pagamentos where comanda_id = :'cmd_r'), 'tirar o item devolve a sessão e o pagamento');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro(format($q$select reabrir_comanda(%L)$q$, :'cmd_pa'), '55000', 'venda de pacote já usado não reabre');
-- cashback de 5%
update saloes set cashback_percentual = 5, cashback_validade_dias = 60;
insert into comandas (cliente_id) values (:'julia') returning id as cmd_cb \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_cb', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
insert into comanda_itens (comanda_id, tipo, descricao, profissional_id, preco_centavos) values (:'cmd_cb', 'gorjeta', 'Gorjeta', 'a0000000-0000-0000-0000-000000000002', 1000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_cb', 'pix', 6000);
select fechar_comanda(:'cmd_cb');
select t.ok(saldo_cashback(:'julia') = 250, 'cashback de 5% sobre o pago, sem a gorjeta');
insert into comandas (cliente_id) values (:'julia') returning id as cmd_cb2 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_cb2', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
select t.ok(usar_cashback(:'cmd_cb2') = 250, 'cashback entra como pagamento');
select t.ok(saldo_cashback(:'julia') = 0, 'e sai do saldo');
delete from comanda_pagamentos where comanda_id = :'cmd_cb2' and forma = 'cashback';
select t.ok(saldo_cashback(:'julia') = 250, 'tirar o pagamento devolve o cashback');
reset role;
update cashback_movimentos set expira_em = now() - interval '1 day' where cliente_id = :'julia';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok(saldo_cashback(:'julia') = 0, 'cashback vencido não vale');
select painel(current_date - 1, current_date + 1) as pn2 \gset
select t.ok((:'pn2'::jsonb ->> 'pacotes')::int >= 40000, 'venda de pacote entra no faturamento');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from pacotes) = 0 and (select count(*) from pacotes_cliente) = 0 and (select count(*) from cashback_movimentos) = 0, 'outro salão não vê pacotes nem cashback');
select t.ok(usar_pacote(:'cmd_r') = 0 and usar_cashback(:'cmd_r') = 0, 'outro salão não usa pacote nem cashback alheio');
reset role;

-- 22) Correções da segunda revisão (0017)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
insert into comandas (cliente_id) values (:'julia') returning id as cmd_f \gset
select t.erro(format($q$insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (%L, 'cashback', 20000)$q$, :'cmd_f'), '42501', 'ninguém digita pagamento em cashback');
select t.erro(format($q$insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (%L, 'pacote', 100)$q$, :'cmd_f'), '42501', 'nem em pacote');
select t.erro(format($q$insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (%L, 'sinal', 100)$q$, :'cmd_f'), '42501', 'nem em sinal');
reset role;

-- duas escovas do mesmo pacote na mesma comanda; cancelar devolve as duas
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select usado as usado_antes from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id where pc.comanda_id = :'cmd_pa' \gset
insert into comandas (cliente_id) values (:'julia') returning id as cmd_2e \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_2e', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_2e', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000005', 5000);
select t.ok(usar_pacote(:'cmd_2e') = 2, 'duas escovas usam duas sessões');
select t.erro(format($q$update comandas set cliente_id = %L where id = %L$q$, :'pac_a', :'cmd_2e'), '55000', 'comanda paga com pacote não troca de cliente');
update comandas set status = 'cancelada' where id = :'cmd_2e';
select t.ok((select usado from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id where pc.comanda_id = :'cmd_pa') = :'usado_antes'::int, 'cancelar devolve as duas sessões');
reset role;

-- cashback por ordem de chegada: uso gasta o crédito mais antigo; vencido o antigo, o novo continua valendo
insert into clientes (salao_id, nome) values (:'salao_a', 'Kátia Cashback') returning id as katia \gset
insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, expira_em, criado_em) values
  (:'salao_a', :'katia', 'credito', 100, now() - interval '1 day', now() - interval '90 days'),
  (:'salao_a', :'katia', 'credito', 100, now() + interval '60 days', now() - interval '30 days'),
  (:'salao_a', :'katia', 'uso', -100, null, now() - interval '20 days');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok(saldo_cashback(:'katia') = 100, 'o uso gastou o crédito antigo; o novo ainda vale');
reset role;

-- unir cadastros leva pacote, cashback e lista de espera
insert into clientes (salao_id, nome) values (:'salao_a', 'Kátia Duplicada') returning id as katia2 \gset
insert into pacotes_cliente (salao_id, cliente_id, pacote_id, nome, tipo, comanda_id, expira_em) values (:'salao_a', :'katia2', :'pct', '10 escovas', 'pacote', :'cmd_pa', now() + interval '30 days') returning id as pc_k \gset
insert into lista_espera (salao_id, cliente_id, servico_id, data_de, data_ate) values (:'salao_a', :'katia2', :'srv_a', current_date, current_date + 5);
insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, expira_em) values (:'salao_a', :'katia2', 'credito', 50, now() + interval '10 days');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select unir_clientes(:'katia', :'katia2');
select t.ok((select cliente_id from pacotes_cliente where id = :'pc_k') = :'katia'::uuid, 'pacote do duplicado passa para quem fica');
select t.ok((select count(*) from lista_espera where cliente_id = :'katia') = 1 and saldo_cashback(:'katia') = 150, 'lista de espera e cashback também');
reset role;

-- quem foi avisada de uma vaga continua recebendo as próximas
select ((:'segd'::date + 22 + time '16:00') at time zone 'America/Sao_Paulo') as ter16 \gset
insert into lista_espera (salao_id, cliente_id, servico_id, data_de, data_ate, estado) values (:'salao_a', :'iara', :'srv_cm', (:'ter16'::timestamptz at time zone 'America/Sao_Paulo')::date, (:'ter16'::timestamptz at time zone 'America/Sao_Paulo')::date, 'avisado') returning id as esp2 \gset
insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio) values (:'salao_a', :'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'ter16') returning id as ag_v2 \gset
update agendamentos set status = 'cancelado' where id = :'ag_v2';
select t.ok(exists (select 1 from avisos where chave like 'vaga:' || :'esp2' || ':' || :'ag_v2' || ':%'), 'quem já foi avisada antes recebe o aviso da nova vaga');

-- painel: soma dos dias = receita
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select painel(current_date - 1, current_date + 1) as pn3 \gset
select t.ok((select sum(value::numeric) from jsonb_each_text(:'pn3'::jsonb -> 'por_dia')) = (:'pn3'::jsonb ->> 'receita')::numeric, 'faturamento por dia soma a receita do período');
reset role;

-- 23) Vários serviços no mesmo atendimento e remarcação pelo link (0018)
select ((:'segd'::date + 23 + time '09:00') at time zone 'America/Sao_Paulo') as qua9 \gset
select ((:'segd'::date + 24 + time '09:00') at time zone 'America/Sao_Paulo') as qui9 \gset
set role service_role;
select agendar_online_grupo('sorriso', array[:'srv_cor', :'srv_cm']::uuid[], 'a0000000-0000-0000-0000-000000000002', :'qua9', 'Lara Combo', '11900006666', true, null, null) as g1 \gset
select (:'g1'::jsonb ->> 'agendamento_id') as lider, (:'g1'::jsonb ->> 'token') as tok_g \gset
select t.ok((select count(*) from do_grupo(:'lider')) = 2, 'dois serviços viram dois horários do mesmo atendimento');
select t.ok((select max(inicio) from do_grupo(:'lider')) = :'qua9'::timestamptz + interval '120 minutes', 'o segundo começa quando o primeiro termina');
select t.ok((:'g1'::jsonb ->> 'sinal_centavos')::int = 6000, 'sinal soma os serviços');
select t.ok((select count(*) from lembretes l join do_grupo(:'lider') g on g.id = l.agendamento_id where g.id <> :'lider'::uuid and l.estado = 'pendente') = 0, 'só o primeiro horário manda lembrete');
select t.ok((horario_publico(:'tok_g') ->> 'servico') = 'Coloração + Corte masculino', 'página mostra os dois serviços');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select confirmar_sinal(:'lider');
select t.ok((select bool_and(status = 'confirmado') from do_grupo(:'lider')), 'confirmar o sinal confirma o atendimento todo');
reset role;
-- remarcar para um horário livre: tudo muda junto
set role service_role;
select t.ok(remarcar_online(:'tok_g', :'qui9', 'a0000000-0000-0000-0000-000000000002') = 'remarcado', 'cliente remarca pelo link');
select t.ok((select min(inicio) from do_grupo(:'lider')) = :'qui9'::timestamptz and (select max(inicio) from do_grupo(:'lider')) = :'qui9'::timestamptz + interval '120 minutes', 'os dois serviços mudam juntos');
select t.ok(not exists (select 1 from ocupacoes o join do_grupo(:'lider') g on g.id = o.agendamento_id where lower(o.periodo) < :'qui9'::timestamptz), 'o horário antigo fica livre');
reset role;
-- remarcar para um horário ocupado: nada muda
insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio) values (:'salao_a', :'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'qua9'::timestamptz + interval '30 minutes');
set role service_role;
select (select count(*) from ocupacoes o join do_grupo(:'lider') g on g.id = o.agendamento_id) as ocup_antes \gset
select t.ok(remarcar_online(:'tok_g', :'qua9', 'a0000000-0000-0000-0000-000000000002') = 'horario_indisponivel', 'horário ocupado não aceita a remarcação');
select t.ok((select min(inicio) from do_grupo(:'lider')) = :'qui9'::timestamptz and (select count(*) from ocupacoes o join do_grupo(:'lider') g on g.id = o.agendamento_id) = :'ocup_antes'::int, 'e o horário que ela tinha continua garantido');
select t.ok(cancelar_online(:'tok_g') = 'cancelado', 'cliente cancela pelo link');
select t.ok((select bool_and(status = 'cancelado') from do_grupo(:'lider')), 'cancelar pelo link cancela o atendimento todo');
select t.ok(remarcar_online(:'tok_g', :'qui9', 'a0000000-0000-0000-0000-000000000002') = 'ja_cancelado', 'atendimento cancelado não remarca');
reset role;

-- 24) Ficha de primeira visita por link (0019)
insert into clientes (salao_id, nome, telefone) values (:'salao_a', 'Nina Primeira', '11900007777') returning id as nina \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select criar_link_ficha(:'nina') as tok_f \gset
select t.ok(length(:'tok_f') = 64, 'recepção gera o link da ficha');
select t.ok((select count(*) from fichas_previas where cliente_id = :'nina') = 1, 'a ficha fica registrada');
select t.erro($$select token_hash from fichas_previas$$, '42501', 'ninguém lê o hash do segredo');
reset role;
set role service_role;
select t.ok((ficha_publica(:'tok_f') ->> 'cliente') = 'Nina' and not (ficha_publica(:'tok_f') ->> 'respondida')::boolean, 'link abre a ficha da cliente certa');
select t.ok(ficha_publica('segredo-errado') is null, 'segredo errado não abre nada');
select t.ok((ficha_publica(:'tok_f') ->> 'pedir_nascimento')::boolean, 'sem data no cadastro, a ficha pede o nascimento');
select t.ok(responder_ficha(:'tok_f', '{"tipo_cabelo":"cacheado","quimica":"coloração","quimica_quando":"há 2 meses","alergias":"PPD","reacao_tintura":"sim","gestante":"nao","objetivo":"cobrir os brancos","origem":"instagram","nascimento":"1990-05-10"}') = 'respondida', 'cliente responde');
select t.ok(responder_ficha(:'tok_f', '{}') = 'ja_respondida', 'não responde duas vezes');
reset role;
select t.ok((select tipo_cabelo = 'cacheado' and alergias = 'PPD' and origem = 'instagram' and nascimento = '1990-05-10' and observacoes like '%já teve reação a tintura%' from clientes where id = :'nina'), 'respostas vão para a ficha da cliente');
select t.ok(not (ficha_publica(:'tok_f') ->> 'pedir_nascimento')::boolean, 'com data no cadastro, a ficha não pede de novo');
-- link antigo deixa de valer quando um novo é gerado
insert into clientes (salao_id, nome) values (:'salao_a', 'Olga Dois Links') returning id as olga \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select criar_link_ficha(:'olga') as tok_o1 \gset
select criar_link_ficha(:'olga') as tok_o2 \gset
reset role;
set role service_role;
select t.ok(responder_ficha(:'tok_o1', '{}') = 'expirada', 'link antigo não vale depois de gerar outro');
select t.ok(criar_link_ficha_online(:'ag_on') is not null, 'cliente nova que marcou pelo link recebe a ficha');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro(format($q$select criar_link_ficha(%L)$q$, :'nina'), 'P0002', 'outro salão não gera ficha de cliente alheia');
select t.ok((select count(*) from fichas_previas) = 0, 'nem vê as fichas');
reset role;
set role anon;
select t.erro(format($q$select responder_ficha(%L, '{}')$q$, :'tok_o2'), '42501', 'anônimo não chama a função direto');
reset role;

-- 25) Avaliação depois do atendimento (0020)
update saloes set avaliacao_ativa = true, google_avaliacao_url = 'https://g.page/r/exemplo/review' where id = :'salao_a';
update clientes set consentimento_em = now() where id = :'nina';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into comandas (cliente_id) values (:'nina') returning id as cmd_av \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_av', 'servico', :'srv_cm', 'Corte masculino', 'a0000000-0000-0000-0000-000000000002', 4000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_av', 'pix', 4000);
select fechar_comanda(:'cmd_av');
select t.ok((select count(*) from avaliacoes where comanda_id = :'cmd_av') = 1, 'comanda fechada pede avaliação');
select t.ok((select enviar_em > now() from avisos where chave = 'avaliacao:' || :'cmd_av'), 'a pergunta sai no dia seguinte');
-- outra comanda da mesma cliente no mesmo mês não pergunta de novo
insert into comandas (cliente_id) values (:'nina') returning id as cmd_av2 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_av2', 'servico', :'srv_cm', 'Corte masculino', 'a0000000-0000-0000-0000-000000000002', 4000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_av2', 'pix', 4000);
select fechar_comanda(:'cmd_av2');
select t.ok((select count(*) from avaliacoes where cliente_id = :'nina') = 1, 'no máximo uma pergunta a cada 30 dias');
select t.erro($$select token_hash from avaliacoes$$, '42501', 'ninguém lê o hash do segredo');
reset role;
select dados ->> 'token' as tok_av from avisos where chave = 'avaliacao:' || :'cmd_av' \gset
set role service_role;
select t.ok((avaliacao_publica(:'tok_av') ->> 'cliente') = 'Nina', 'link abre a avaliação da cliente');
select t.ok(responder_avaliacao(:'tok_av', 11, null) = 'invalida', 'nota fora de 0 a 10 é recusada');
select t.ok(responder_avaliacao(:'tok_av', 4, 'Esperei 30 minutos') = 'respondida', 'cliente responde');
select t.ok(responder_avaliacao(:'tok_av', 10, null) = 'ja_respondida', 'não muda a nota depois');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((nps(current_date - 1, current_date + 1) ->> 'detratores')::int = 1 and (nps(current_date - 1, current_date + 1) ->> 'nps')::int = -100, 'NPS conta detratores');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from avaliacoes) = 0, 'profissional não lê as avaliações');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from avaliacoes) = 0 and (nps(current_date - 1, current_date + 1) ->> 'respostas')::int = 0, 'outro salão não vê avaliações alheias');
reset role;

-- 26) Vale-presente (0021)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into comandas (cliente_id) values (:'julia') returning id as cmd_vv \gset
insert into comanda_itens (comanda_id, tipo, descricao, preco_centavos, presente_para, presente_mensagem) values (:'cmd_vv', 'vale_presente', 'Vale-presente', 15000, 'Mãe', 'Feliz dia!');
select t.erro(format($q$insert into comanda_itens (comanda_id, tipo, descricao, preco_centavos) values (%L, 'vale_presente', 'X', 100)$q$, :'cmd_vv'), '23514', 'vale-presente precisa dizer para quem');
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_vv', 'pix', 15000);
select fechar_comanda(:'cmd_vv');
select codigo as cod from vales_presente where comanda_id = :'cmd_vv' \gset
select t.ok(:'cod' ~ '^[A-Z2-9]{8}$' and (select saldo_centavos = 15000 and para = 'Mãe' from vales_presente where codigo = :'cod'), 'venda gera o código com o saldo');
-- uso em duas visitas
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_vu \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_vu', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 10000);
select t.erro(format($q$insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (%L, 'vale_presente', 10000)$q$, :'cmd_vu'), '42501', 'vale não é digitado como pagamento');
select t.ok(usar_vale_presente(:'cmd_vu', lower(:'cod')) = 10000, 'vale paga até o total (código em minúscula também vale)');
select t.ok((select saldo_centavos from vales_presente where codigo = :'cod') = 5000, 'saldo diminui');
delete from comanda_pagamentos where comanda_id = :'cmd_vu' and forma = 'vale_presente';
select t.ok((select saldo_centavos from vales_presente where codigo = :'cod') = 15000, 'tirar o pagamento devolve o saldo');
select usar_vale_presente(:'cmd_vu', :'cod');
select fechar_comanda(:'cmd_vu');
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_vu2 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_vu2', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 10000);
select t.ok(usar_vale_presente(:'cmd_vu2', :'cod') = 5000, 'o resto do saldo vale na visita seguinte');
select t.erro(format($q$select usar_vale_presente(%L, 'ZZZZZZZZ')$q$, :'cmd_vu2'), 'P0002', 'código errado não vale');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro(format($q$select reabrir_comanda(%L)$q$, :'cmd_vv'), '55000', 'venda de vale já usado não reabre');
update comandas set status = 'cancelada' where id = :'cmd_vu2';
select t.ok((select saldo_centavos from vales_presente where codigo = :'cod') = 5000, 'cancelar a comanda devolve o que tinha sido usado nela');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from vales_presente) = 0, 'outro salão não vê vales alheios');
reset role;

-- 27) Correções da terceira revisão (0022)
select ((:'segd'::date + 30 + time '09:00') at time zone 'America/Sao_Paulo') as d30 \gset
select ((:'segd'::date + 30 + time '13:00') at time zone 'America/Sao_Paulo') as d30t \gset
set role service_role;
select agendar_online_grupo('sorriso', array[:'srv_cor', :'srv_cm']::uuid[], 'a0000000-0000-0000-0000-000000000002', :'d30', 'Paula Grupo', '11900008888', true, null, null) as gr \gset
select (:'gr'::jsonb ->> 'agendamento_id') as lider2, (:'gr'::jsonb ->> 'token') as tok2 \gset
select t.ok((:'gr'::jsonb ->> 'cliente_novo')::boolean, 'avisa quando a cliente é nova');
select t.ok((select c.origem is null from clientes c join agendamentos a on a.cliente_id = c.id where a.id = :'lider2'), 'cliente nova pelo link nasce sem origem');
select t.ok(remarcar_online(:'tok2', :'d30t', 'a0000000-0000-0000-0000-000000000002') = 'remarcado', 'remarca o atendimento para mais tarde');
reset role;
select t.ok((select count(*) from lembretes where agendamento_id = :'lider2' and estado = 'pendente') > 0, 'depois de remarcar, o primeiro horário continua com lembrete');
select t.ok((select count(*) from lembretes l join do_grupo(:'lider2') g on g.id = l.agendamento_id where g.id <> :'lider2'::uuid and l.estado = 'pendente') = 0, 'e o segundo continua sem');
-- telefone de cliente já cadastrada: nem ficha nova, nem cliente novo
set role service_role;
select agendar_online('sorriso', :'srv_cm', 'a0000000-0000-0000-0000-000000000002', :'d30'::timestamptz + interval '1 day', 'Outra Pessoa', '11900003333', true, null, null) as gr2 \gset
select t.ok(not (:'gr2'::jsonb ->> 'cliente_novo')::boolean, 'telefone já cadastrado não é cliente nova');
select t.ok(criar_link_ficha_online((:'gr2'::jsonb ->> 'agendamento_id')::uuid) is null, 'e não recebe a ficha de primeira visita da dona do número');
reset role;
-- atendimento com dois profissionais não é remarcado pelo link
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select gen_random_uuid() as gdois \gset
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, grupo_id) values
  (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'d30'::timestamptz + interval '2 days', :'gdois'),
  (:'pac_a', 'a0000000-0000-0000-0000-000000000005', :'srv_cm', :'d30'::timestamptz + interval '2 days 30 minutes', :'gdois');
reset role;
select token as tok_dois from agendamentos where grupo_id = :'gdois' order by inicio limit 1 \gset
set role service_role;
select t.ok(remarcar_online(:'tok_dois', :'d30'::timestamptz + interval '3 days', 'a0000000-0000-0000-0000-000000000002') = 'varios_profissionais', 'atendimento com profissionais diferentes não é remarcado pelo link');
reset role;
-- vale-presente com desconto na comanda vale o que foi pago
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into comandas (cliente_id) values (:'julia') returning id as cmd_vd \gset
insert into comanda_itens (comanda_id, tipo, descricao, preco_centavos, presente_para) values (:'cmd_vd', 'vale_presente', 'Vale', 10000, 'Irmã');
update comandas set desconto_centavos = 1000 where id = :'cmd_vd';
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_vd', 'pix', 9000);
select fechar_comanda(:'cmd_vd');
select t.ok((select valor_centavos = 9000 and saldo_centavos = 9000 from vales_presente where comanda_id = :'cmd_vd'), 'vale vendido com desconto vale o que foi pago');
-- unir leva a ficha de primeira visita
insert into clientes (nome) values ('Nina Duplicada') returning id as nina2 \gset
select criar_link_ficha(:'nina2');
select unir_clientes(:'nina', :'nina2');
select t.ok((select count(*) from fichas_previas where cliente_id = :'nina') = 2, 'unir leva as fichas de primeira visita');
reset role;

-- 28) Correções da quarta revisão (0023)
update cashback_movimentos set expira_em = now() - interval '1 day' where cliente_id = :'julia' and tipo = 'credito';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into comandas (cliente_id) values (:'julia') returning id as cmd_k \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_k', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_k', 'pix', 5000);
select fechar_comanda(:'cmd_k');
select t.ok(saldo_cashback(:'julia') = 250, 'comanda nova gera cashback');
insert into comandas (cliente_id) values (:'julia') returning id as cmd_k2 \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_k2', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
select t.ok(usar_cashback(:'cmd_k2') = 250, 'cashback usado em outra comanda');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro(format($q$select reabrir_comanda(%L)$q$, :'cmd_k'), '55000', 'comanda com cashback já gasto não reabre');
select t.ok(saldo_cashback(:'julia') = 0, 'e o cashback gasto continua contado');
delete from comanda_pagamentos where comanda_id = :'cmd_k2' and forma = 'cashback';
select reabrir_comanda(:'cmd_k');
select t.ok(saldo_cashback(:'julia') = 0 and (select status from comandas where id = :'cmd_k') = 'aberta', 'cashback devolvido: a comanda reabre e o crédito sai');
select fechar_comanda(:'cmd_k');
select t.ok(saldo_cashback(:'julia') = 250, 'fechar de novo gera o cashback uma vez só');
-- desconto da comanda também vale na venda do pacote
insert into comandas (cliente_id) values (:'julia') returning id as cmd_pd \gset
insert into comanda_itens (comanda_id, tipo, pacote_id, descricao, preco_centavos) values (:'cmd_pd', 'pacote', :'pct', '10 escovas', 40000);
update comandas set desconto_centavos = 4000 where id = :'cmd_pd';
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_pd', 'pix', 36000);
select fechar_comanda(:'cmd_pd');
select t.ok((select ps.valor_unitario_centavos = 3600 from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id where pc.comanda_id = :'cmd_pd'), 'pacote vendido com desconto: a sessão vale o que foi pago');
reset role;

-- 29) Correções da quinta revisão (0024)
set role service_role;
select agendar_online_grupo('sorriso', array[:'srv_cor', :'srv_cm']::uuid[], 'a0000000-0000-0000-0000-000000000002', :'d30'::timestamptz + interval '7 days', 'Rita Grupo', '11900007777', true, null, null) as gr5 \gset
reset role;
select (:'gr5'::jsonb ->> 'agendamento_id') as lider5 \gset
select (receber_mensagem(:'salao_a', '5511900007777', 'Rita', 'wamid.g5', 'texto', 'oi') ->> 'conversa_id') as conv_g \gset
select t.ok((select count(*) from agendamentos_whatsapp(:'salao_a', :'conv_g')) = 1, 'robô mostra o atendimento com vários serviços como um horário só');
select t.ok((select id = :'lider5'::uuid and servico like '% + %' from agendamentos_whatsapp(:'salao_a', :'conv_g')), 'com o primeiro serviço e os nomes juntos');
select t.ok(cancelar_whatsapp(:'salao_a', :'conv_g', :'lider5'), 'cancelar pelo robô');
select t.ok((select count(*) from do_grupo(:'lider5') where status = 'cancelado') = 2, 'cancela o atendimento inteiro');

-- 30) Correções da sexta revisão (0025)
set role service_role;
select agendar_online('sorriso', :'srv_cor', 'a0000000-0000-0000-0000-000000000002', :'d30'::timestamptz + interval '14 days', 'Eva Atrasada', '11900006666', true, null, null) as r6 \gset
reset role;
update sinais set expira_em = now() - interval '1 minute' where agendamento_id = (:'r6'::jsonb ->> 'agendamento_id')::uuid;
set role service_role;
select expirar_sinais();
select agendar_online('sorriso', :'srv_cor', 'a0000000-0000-0000-0000-000000000002', :'d30'::timestamptz + interval '14 days', 'Fabi Nova', '11900005555', true, null, null);
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select confirmar_sinal((:'r6'::jsonb ->> 'agendamento_id')::uuid);
reset role;
select t.ok((select status from sinais where agendamento_id = (:'r6'::jsonb ->> 'agendamento_id')::uuid) = 'credito', 'Pix pago depois do prazo com o horário ocupado vira crédito');
select t.ok((select status from agendamentos where id = (:'r6'::jsonb ->> 'agendamento_id')::uuid) = 'cancelado', 'e o horário continua com quem marcou depois');

-- 31) Segurança do agendamento online (0026)
set role service_role;
select agendar_online('sorriso', :'srv_cm', 'a0000000-0000-0000-0000-000000000002', :'d30'::timestamptz + make_interval(days => 21 + 7 * k), 'Robo ' || k, '1190000' || lpad(k::text, 4, '0'), true, '203.0.113.9', null)
from generate_series(0, 4) k;
select t.erro($q$select agendar_online('sorriso', '$q$ || :'srv_cm' || $q$', 'a0000000-0000-0000-0000-000000000002', '$q$ || (:'d30'::timestamptz + interval '56 days') || $q$', 'Robo 6', '11900009999', true, '203.0.113.9', null)$q$, '54000', 'o sexto agendamento do mesmo endereço em uma hora é recusado');
select t.ok((agendar_online('sorriso', :'srv_cm', 'a0000000-0000-0000-0000-000000000002', :'d30'::timestamptz + interval '56 days', 'Pessoa Real', '11900009998', true, '198.51.100.7', null) ->> 'agendamento_id') is not null, 'outro endereço continua marcando');
reset role;

-- 32) Limite de tentativas (0027)
set role service_role;
select registrar_tentativa('login:ip:1.2.3.4', 3, 15) from generate_series(1, 3);
select t.ok(not registrar_tentativa('login:ip:1.2.3.4', 3, 15), 'a quarta tentativa na janela é barrada');
select t.ok(registrar_tentativa('login:ip:5.6.7.8', 3, 15), 'outro endereço não é afetado');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.erro($$select registrar_tentativa('x', 1, 1)$$, '42501', 'usuário logado não mexe no limite');
select t.erro($$select count(*) from tentativas$$, '42501', 'nem lê as tentativas');
reset role;

-- 33) Barba masculina e serviço avulso (0028)
select t.ok((select count(*) from servicos where salao_id = :'salao_a' and nome = 'Barba masculina') = 1, 'salão existente ganha Barba masculina');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select servico_avulso('Sobrancelha  com henna', 30) as av1 \gset
select t.ok(servico_avulso('sobrancelha com henna', 30) = :'av1'::uuid, 'o mesmo "Outro" é reaproveitado');
select t.ok((select not ativo and not online and avulso and duracao_min = 30 from servicos where id = :'av1'), 'avulso nasce fora do catálogo e do link');
select t.erro($$select servico_avulso('X', 30)$$, '22023', 'nome curto é recusado');
select t.erro($$select servico_avulso('Depilação', 7)$$, '22023', 'duração fora do passo de 5 min é recusada');
reset role;
set role anon;
select t.erro($$select servico_avulso('Teste', 30)$$, '42501', 'anônimo não cria serviço');
reset role;

-- 34) Aniversário, robô remarcando o atendimento inteiro e lista de espera em remarcação (0029)
update saloes set aniversario_ativo = true where id = :'salao_a';
insert into clientes (salao_id, nome, telefone, consentimento_em, nascimento)
values (:'salao_a', 'Ana Aniversário', '11900002222', now(), ((now() at time zone 'America/Sao_Paulo')::date - interval '30 years')::date) returning id as aniv \gset
set role service_role;
select programar_aniversarios() as n_aniv \gset
select t.ok(:'n_aniv'::int >= 1, 'aniversariante do dia recebe a mensagem');
select t.ok(programar_aniversarios() = 0, 'e só uma vez por ano');
reset role;
select t.ok((select count(*) from cashback_movimentos where cliente_id = :'aniv' and tipo = 'credito' and valor_centavos = 2000) = 1, 'com o presente em crédito');
select t.ok((select dados ->> 'credito' from avisos where cliente_id = :'aniv' and tipo = 'aniversario') = '2000', 'o aviso leva o valor do presente');
-- robô remarca os dois serviços juntos
set role service_role;
select agendar_online_grupo('sorriso', array[:'srv_cor', :'srv_cm']::uuid[], 'a0000000-0000-0000-0000-000000000002', :'d30'::timestamptz + interval '28 days 5 hours', 'Lia Grupo', '11900001111', true, null, null) as gr7 \gset
reset role;
select (:'gr7'::jsonb ->> 'agendamento_id') as lider7 \gset
select (receber_mensagem(:'salao_a', '5511900001111', 'Lia', 'wamid.g7', 'texto', 'oi') ->> 'conversa_id') as conv7 \gset
insert into lista_espera (salao_id, cliente_id, servico_id, data_de, data_ate)
values (:'salao_a', :'aniv', :'srv_cor', ((:'d30'::timestamptz + interval '28 days 5 hours') at time zone 'America/Sao_Paulo')::date, ((:'d30'::timestamptz + interval '28 days 5 hours') at time zone 'America/Sao_Paulo')::date);
set role service_role;
select t.ok(remarcar_whatsapp(:'salao_a', :'conv7', :'lider7', :'d30'::timestamptz + interval '35 days 5 hours', 'a0000000-0000-0000-0000-000000000002') = 'remarcado', 'robô remarca o atendimento com dois serviços');
reset role;
select t.ok((select count(*) from do_grupo(:'lider7') where status in ('agendado', 'confirmado') and inicio >= :'d30'::timestamptz + interval '35 days 5 hours') = 2, 'os dois serviços mudaram juntos');
select t.ok(exists (select 1 from avisos where cliente_id = :'aniv' and tipo = 'vaga'), 'quem esperava aquele horário é avisada da vaga');
set role service_role;
select t.ok(remarcar_whatsapp(:'salao_a', :'conv7', :'lider', :'d30'::timestamptz + interval '36 days 5 hours', 'a0000000-0000-0000-0000-000000000002') = 'nao_encontrado', 'robô não remarca horário de outra cliente');
reset role;

-- 35) Regras de acesso calculadas uma vez por consulta (0030)
select t.ok(not exists (select 1 from pg_policies where schemaname = 'public' and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(?<!SELECT )(meu_salao|meu_papel)\(\)'), 'nenhuma regra chama meu_salao/meu_papel linha a linha');
select t.ok((select count(*) from pg_policies where schemaname = 'public' and qual like '%SELECT meu_salao()%') > 50, 'as regras usam o valor calculado uma vez');

-- 36) Agenda avançada (0031)
select ((:'d30'::timestamptz) + interval '91 days 5 hours') as q1, ((:'d30'::timestamptz) + interval '98 days 5 hours') as q2, ((:'d30'::timestamptz) + interval '105 days 5 hours') as q3 \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into servico_variacoes (servico_id, nome, preco_centavos, fases) values (:'srv_a', 'Longo', 8000, '[{"tipo":"trabalho","min":90}]') returning id as var_longo \gset
insert into servico_profissional (servico_id, profissional_id, preco_centavos, fases) values (:'srv_a', 'a0000000-0000-0000-0000-000000000002', 7000, '[{"tipo":"trabalho","min":60}]');
select t.ok(preco_de(:'srv_a', 'a0000000-0000-0000-0000-000000000002', :'var_longo') = 8000, 'o tamanho vale primeiro no preço');
select t.ok(preco_de(:'srv_a', 'a0000000-0000-0000-0000-000000000002', null) = 7000, 'depois o preço do profissional');
select t.ok(preco_de(:'srv_a', 'a0000000-0000-0000-0000-000000000005', null) = 5000, 'e por fim o do catálogo');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro($$insert into servico_variacoes (servico_id, nome, preco_centavos, fases) values ('$$ || :'srv_a' || $$', 'Curto', 4000, '[{"tipo":"trabalho","min":30}]')$$, '42501', 'recepção não mexe nos tamanhos');
insert into agendamentos (cliente_id, profissional_id, servico_id, variacao_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'var_longo', :'q1') returning id as ag_v, fim - inicio as dur_v \gset
select t.ok(:'dur_v'::interval = interval '90 minutes', 'agendamento com tamanho usa o tempo do tamanho');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'q1'::timestamptz + interval '2 hours') returning fim - inicio as dur_p \gset
select t.ok(:'dur_p'::interval = interval '60 minutes', 'sem tamanho, usa o tempo do profissional');
reset role;
-- intervalo de limpeza ocupa o profissional
update servicos set intervalo_min = 15 where id = :'srv_cm';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000005', :'srv_cm', :'q2') returning id as ag_i, fim as fim_i \gset
select t.erro($$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values ('$$ || :'pac_a' || $$', 'a0000000-0000-0000-0000-000000000005', '$$ || :'srv_cm' || $$', '$$ || :'fim_i' || $$')$$, '23P01', 'o intervalo de limpeza não deixa marcar colado');
select t.ok((select count(*) from agendamentos where id = :'ag_i' and intervalo_min = 15) = 1, 'o intervalo fica guardado no horário');
reset role;
update servicos set intervalo_min = 0 where id = :'srv_cm';
-- recurso: um lavatório só
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into recursos (nome, quantidade) values ('Lavatório', 1) returning id as lav \gset
insert into servico_recursos (servico_id, recurso_id) values (:'srv_cm', :'lav');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_cm', :'q3');
select t.erro($$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values ('$$ || :'pac_a' || $$', 'a0000000-0000-0000-0000-000000000005', '$$ || :'srv_cm' || $$', '$$ || :'q3' || $$')$$, '23P01', 'o lavatório não é usado por duas clientes ao mesmo tempo');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000005', :'srv_cm', :'q3'::timestamptz + interval '3 hours');
select t.ok(true, 'em outro horário o lavatório está livre');
reset role;
-- cliente bloqueada, VIP e antecedência
insert into clientes (salao_id, nome, telefone, bloqueada) values (:'salao_a', 'Bia Bloqueada', '11977770001', true);
insert into clientes (salao_id, nome, telefone, vip) values (:'salao_a', 'Vera VIP', '11977770002', true);
set role service_role;
select t.erro($$select agendar_online_grupo('sorriso', array['$$ || :'srv_cor' || $$']::uuid[], 'a0000000-0000-0000-0000-000000000002', '$$ || (:'q1'::timestamptz + interval '7 days') || $$', 'Bia', '11977770001', true, null, null)$$, '42501', 'cliente bloqueada não marca pelo link');
select agendar_online_grupo('sorriso', array[:'srv_cor']::uuid[], 'a0000000-0000-0000-0000-000000000002', :'q1'::timestamptz + interval '7 days', 'Vera', '11977770002', true, null, null) as vip \gset
select t.ok((:'vip'::jsonb ->> 'sinal_centavos')::int = 0, 'cliente VIP não paga sinal');
reset role;
update saloes set antecedencia_max_dias = 30 where id = :'salao_a';
set role service_role;
select t.erro($$select agendar_online_grupo('sorriso', array['$$ || :'srv_cm' || $$']::uuid[], 'a0000000-0000-0000-0000-000000000002', '$$ || (:'q1'::timestamptz + interval '14 days') || $$', 'Longe', '11977770003', true, null, null)$$, '22023', 'horário além da antecedência máxima é recusado');
reset role;
update saloes set antecedencia_max_dias = 365 where id = :'salao_a';
-- fila de quem chega sem hora
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into fila_atendimento (nome, servico_id) values ('Rapaz da barba', :'srv_cm') returning id as fila1 \gset
update fila_atendimento set estado = 'atendendo' where id = :'fila1';
select t.ok((select estado from fila_atendimento where id = :'fila1') = 'atendendo', 'recepção põe na fila e chama');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from fila_atendimento) = 0 and (select count(*) from servico_variacoes) = 0 and (select count(*) from recursos) = 0, 'outro salão não vê fila, tamanhos nem recursos');
reset role;


-- 37) promoções, campanhas, vitrine, avisos da equipe, nota fiscal e termos
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into promocoes (nome, tipo, percentual, servico_ids) values ('Corte 20% off', 'horario', 20, array[:'srv_cm']::uuid[]) returning id as promo1 \gset
insert into promocoes (nome, tipo, percentual, horas_antes, servico_ids) values ('Última hora', 'ultima_hora', 30, 3, array[:'srv_a']::uuid[]);
select t.ok((promocao_em(:'salao_a', :'srv_a', now() + interval '1 hour') ->> 'percentual')::int = 30, 'promoção de última hora vale perto do horário');
select t.ok(promocao_em(:'salao_a', :'srv_a', now() + interval '5 hours') is null, 'e não vale longe dele');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro($$insert into promocoes (nome, tipo, percentual) values ('Pirata', 'horario', 50)$$, '42501', 'recepção não cria promoção');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000005', :'srv_cm', :'q1'::timestamptz + interval '21 days') returning id as ag_promo, promocao_percentual as pct_promo \gset
select t.ok(:pct_promo = 20, 'horário marcado guarda o desconto da promoção');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000005', :'srv_a', :'q1'::timestamptz + interval '21 days 3 hours') returning promocao_percentual as pct_sem \gset
select t.ok(:pct_sem = 0, 'serviço fora da promoção fica sem desconto');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from promocoes) = 0, 'outro salão não vê as promoções');
reset role;

-- etiquetas e campanha
update clientes set consentimento_em = now(), recusou_lembretes_em = null where id = :'pac_a';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update clientes set etiquetas = '{noiva}' where id = :'pac_a';
select t.erro(format($q$update clientes set etiquetas = '{Noiva }' where id = %L$q$, :'pac_a'), '23514', 'etiqueta fora do padrão é recusada');
select t.ok(contar_publico_campanha('{noiva}', null) = 1, 'campanha conta quem tem a etiqueta e aceitou mensagens');
insert into campanhas (nome, mensagem, etiquetas) values ('Noivas', 'Pacote noiva com 15% de desconto em novembro!', '{noiva}') returning id as camp1 \gset
select t.ok(disparar_campanha(:'camp1') = 1, 'campanha dispara para o público certo');
select t.ok((select count(*) from avisos where tipo = 'campanha' and dados ->> 'campanha_id' = :'camp1') = 1, 'a mensagem entra na fila de envio');
select t.erro(format('select disparar_campanha(%L)', :'camp1'), '23505', 'a mesma campanha não dispara duas vezes');
insert into campanhas (nome, mensagem) values ('Todas', 'Semana da hidratação no salão!') returning id as camp2 \gset
select t.erro(format('select disparar_campanha(%L)', :'camp2'), '54000', 'no máximo uma campanha por dia');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro($$select contar_publico_campanha('{}', null)$$, '42501', 'recepção não faz campanha');
select t.ok((select count(*) from campanhas) = 0, 'recepção não vê as campanhas');
reset role;

-- vitrine
insert into clientes (salao_id, nome) values (:'salao_a', 'Lia Foto') returning id as lia \gset
insert into fotos_cliente (salao_id, cliente_id, momento, caminho) values (:'salao_a', :'lia', 'depois', :'salao_a' || '/lia/depois.jpg') returning id as foto_lia \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro(format('select publicar_foto_cliente(%L, %L)', :'foto_lia', 'Loiro'), '42501', 'foto sem autorização de imagem não vai para a vitrine');
reset role;
update clientes set consentimento_imagem_em = now() where id = :'lia';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select publicar_foto_cliente(:'foto_lia', 'Loiro perolado') as vit1 \gset
select t.ok((select count(*) from vitrine_fotos) = 1, 'com autorização, a foto vai para a vitrine');
select t.erro(format($q$insert into vitrine_fotos (caminho) values ('outro/x.jpg')$q$), '42501', 'foto da vitrine fora da pasta do salão é recusada');
reset role;
update clientes set consentimento_imagem_em = null where id = :'lia';
select t.ok((select count(*) from vitrine_fotos where salao_id = :'salao_a') = 0, 'retirar a autorização tira a foto da vitrine');

-- avisos para a equipe
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'q1'::timestamptz + interval '28 days') returning id as ag_eq \gset
update agendamentos set inicio = inicio + interval '1 hour' where id = :'ag_eq';
update agendamentos set status = 'cancelado' where id = :'ag_eq';
reset role;
select t.ok((select string_agg(tipo, ',' order by criado_em, tipo) from avisos_equipe where agendamento_id = :'ag_eq') in ('novo,mudou,cancelou', 'cancelou,mudou,novo', 'cancelou,novo,mudou', 'mudou,novo,cancelou', 'mudou,cancelou,novo', 'novo,cancelou,mudou'), 'profissional é avisado de horário novo, remarcado e cancelado');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from avisos_equipe where agendamento_id = :'ag_eq') = 3, 'o profissional vê os avisos dele');
update avisos_equipe set lido_em = now() where agendamento_id = :'ag_eq';
select t.ok((select count(*) from avisos_equipe where agendamento_id = :'ag_eq' and lido_em is not null) = 3, 'e marca como lidos');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'q1'::timestamptz + interval '28 days 3 hours') returning id as ag_proprio \gset
reset role;
select t.ok((select count(*) from avisos_equipe where agendamento_id = :'ag_proprio') = 0, 'quem marca na própria agenda não recebe aviso');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok((select count(*) from avisos_equipe where agendamento_id = :'ag_eq') = 0, 'a recepção não lê os avisos do profissional');
reset role;
update membros set telefone = '11955550002', avisos_whatsapp = true where user_id = 'a0000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'q1'::timestamptz + interval '35 days') returning id as ag_wa \gset
reset role;
select t.ok((select whatsapp from avisos_equipe where agendamento_id = :'ag_wa') = 'pendente', 'com celular cadastrado, o aviso vai também pelo WhatsApp');
set role service_role;
select t.ok((select wa_id from reservar_avisos_equipe(50) where id = (select id from avisos_equipe where agendamento_id = :'ag_wa')) = '5511955550002', 'o envio usa o celular do profissional');
reset role;

-- nota fiscal: só o administrador configura; ninguém escreve notas pelo navegador
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro($$insert into fiscal_salao (cnpj) values ('12345678000199')$$, '42501', 'recepção não mexe nos dados fiscais');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into fiscal_salao (cnpj, razao_social, codigo_municipio, item_lista_servico, aliquota) values ('12345678000199', 'Studio Bela LTDA', '3548500', '06.01', 2);
select t.ok((select count(*) from fiscal_salao) = 1, 'administrador configura a nota fiscal');
update fiscal_salao set token_emissor = 'segredo-do-emissor-123';
select t.erro($$select token_emissor from fiscal_salao$$, '42501', 'o token do emissor não é lido pelo navegador');
select t.ok(fiscal_tem_token(), 'a tela sabe que o token está guardado');
select t.erro(format($q$insert into notas_fiscais (salao_id, comanda_id, ref, ambiente, valor_centavos) values (%L, gen_random_uuid(), 'falsa-123', 'producao', 100)$q$, :'salao_a'), '42501', 'ninguém grava nota fiscal pelo navegador');
reset role;

-- termos com assinatura
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select criar_termo(:'lia', 'imagem', 'Autorização de uso de imagem', 'Autorizo o salão a usar fotos do meu cabelo nas redes sociais.') as tok_t \gset
select t.erro(format('select termo_publico(%L)', :'tok_t'), '42501', 'termo só abre pelo servidor');
reset role;
set role service_role;
select t.ok((termo_publico(:'tok_t') ->> 'titulo') = 'Autorização de uso de imagem', 'link abre o termo certo');
select t.ok(assinar_termo(:'tok_t', 'Lia Foto', null, null, 'sem-assinatura', '1.2.3.4', 'teste') = 'invalido', 'sem assinatura desenhada não vale');
select t.ok(assinar_termo(:'tok_t', 'Lia Foto', '12345678909', '{}', 'data:image/png;base64,iVBORw0KGgo=', '1.2.3.4', 'teste') = 'assinado', 'cliente assina');
select t.ok(assinar_termo(:'tok_t', 'Outra', null, null, 'data:image/png;base64,iVBORw0KGgo=', '1.2.3.4', 'teste') = 'ja_assinado', 'não assina duas vezes');
reset role;
select t.ok((select consentimento_imagem_em is not null from clientes where id = :'lia'), 'termo de imagem assinado registra a autorização');
select t.ok((select texto_hash = encode(sha256(convert_to(texto, 'UTF8')), 'hex') from termos_assinados where cliente_id = :'lia'), 'o texto assinado fica guardado com o hash');
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from termos_assinados) = 0 and (select count(*) from vitrine_fotos) = 0 and (select count(*) from avisos_equipe) = 0, 'outro salão não vê termos, vitrine nem avisos');
reset role;

-- 38) permissões, fidelidade, indicação, pedido de compra, metas, cobranças, taxa por falta, área da cliente, relatórios
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.erro($$select painel(current_date - 7, current_date)$$, '42501', 'recepção não vê o painel sem permissão');
reset role;
update membros set permissoes = '{"painel": true, "divulgar": true, "desconto": false}' where user_id = 'a0000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok(painel(current_date - 7, current_date) is not null, 'com a permissão, a recepção vê o painel');
insert into promocoes (nome, tipo, percentual) values ('Da recepção', 'horario', 10) returning id as promo_rec \gset
delete from promocoes where id = :'promo_rec';
select t.ok(true, 'com a permissão, a recepção cria promoção');
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_p \gset
select t.erro(format($q$insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos, desconto_centavos) values (%L, 'servico', %L, 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000, 500)$q$, :'cmd_p', :'srv_a'), '42501', 'sem permissão de desconto, o desconto é recusado');
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_p', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
select t.ok(true, 'sem desconto, lança normal');
reset role;
update membros set permissoes = '{"agenda_outros": false}' where user_id = 'a0000000-0000-0000-0000-000000000002';
select (:'q1'::timestamptz + interval '42 days') as q42 \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro(format($q$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (%L, 'a0000000-0000-0000-0000-000000000005', %L, %L)$q$, :'pac_a', :'srv_a', :'q42'), '42501', 'profissional sem permissão não mexe na agenda dos outros');
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'q42');
select t.ok(true, 'mas mexe na própria');
reset role;
update membros set permissoes = '{}' where user_id in ('a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000003');

-- fidelidade e indicação
update saloes set fidelidade_ativa = true, fidelidade_niveis = '[{"nome":"Prata","pontos":50,"bonus":5}]', indicacao_credito_centavos = 1500,
  taxa_falta_centavos = 3000, cashback_percentual = 0, venda_online = true where id = :'salao_a';
select t.erro(format($q$update saloes set fidelidade_niveis = '[{"nome":"X","pontos":-1,"bonus":1}]' where id = %L$q$, :'salao_a'), '23514', 'nível de fidelidade inválido é recusado');
insert into clientes (salao_id, nome, telefone) values (:'salao_a', 'Rita Indicadora', '11966660001') returning id as rita \gset
insert into clientes (salao_id, nome, telefone, indicado_por) values (:'salao_a', 'Sara Indicada', '11966660002', :'rita') returning id as sara \gset
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into caixas (troco_inicial_centavos) select 0 where not exists (select 1 from caixas where fechado_em is null);
insert into comandas (cliente_id) values (:'sara') returning id as cmd_s \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_s', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 10000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_s', 'pix', 10000);
select fechar_comanda(:'cmd_s');
reset role;
select t.ok((select sum(valor_centavos) from cashback_movimentos where cliente_id = :'rita' and tipo = 'credito') = 1500, 'quem indicou ganha o crédito na primeira visita da amiga');
select t.ok((fidelidade_interna(:'salao_a', :'sara') ->> 'nivel') = 'Prata', 'R$ 100 pagos dão 100 pontos e o nível Prata');
select t.ok((select count(*) from cashback_movimentos where cliente_id = :'sara' and comanda_id = :'cmd_s' and valor_centavos = 500) = 1, 'o nível Prata dá 5% de bônus em cashback');
insert into clientes (salao_id, nome, telefone) values (:'salao_a', 'Vivi Nova', '11933330001') returning id as vivi \gset
insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio) values (:'salao_a', :'vivi', 'a0000000-0000-0000-0000-000000000005', :'srv_a', :'q1'::timestamptz + interval '56 days') returning id as ag_vivi \gset
select codigo_indicacao_interno(:'sara') as cod_sara \gset
set role service_role;
select vincular_origem(:'ag_vivi', :'cod_sara', 'google');
reset role;
select t.ok((select indicado_por = :'sara' and origem = 'indicacao' from clientes where id = :'vivi'), 'link de indicação liga a cliente nova a quem indicou');

-- taxa por falta
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'sara', 'a0000000-0000-0000-0000-000000000005', :'srv_a', :'q1'::timestamptz + interval '49 days') returning id as ag_f \gset
update agendamentos set status = 'faltou' where id = :'ag_f';
select t.ok((select valor_centavos from taxas_falta where agendamento_id = :'ag_f') = 3000, 'falta sem aviso gera a taxa');
select id as taxa1 from taxas_pendentes(:'sara') \gset
insert into comandas (cliente_id) values (:'sara') returning id as cmd_t \gset
insert into comanda_itens (comanda_id, tipo, descricao, preco_centavos, taxa_falta_id) values (:'cmd_t', 'taxa', 'Taxa por falta', 1, :'taxa1');
select t.ok((select preco_centavos from comanda_itens where comanda_id = :'cmd_t') = 3000, 'a taxa entra na comanda com o valor certo');
select t.ok((select count(*) from taxas_pendentes(:'sara')) = 0, 'cobrada, sai das pendentes');
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_t2 \gset
select t.erro(format($q$insert into comanda_itens (comanda_id, tipo, descricao, preco_centavos, taxa_falta_id) values (%L, 'taxa', 'Taxa', 1, %L)$q$, :'cmd_t2', :'taxa1'), '22023', 'a taxa não entra na comanda de outra cliente nem duas vezes');
reset role;

-- pedido de compra
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into produtos (nome, preco_centavos, tipo, unidade, conteudo) values ('Shampoo Teste', 3000, 'revenda', 'un', 1) returning id as prod_s \gset
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into fornecedores (nome, telefone) values ('Distribuidora Bela', '11955554444') returning id as forn \gset
insert into pedidos_compra (fornecedor_id) values (:'forn') returning id as ped \gset
insert into pedido_compra_itens (pedido_id, produto_id, embalagens, custo_centavos) values (:'ped', :'prod_s', 6, 1500);
select t.ok(receber_pedido(:'ped') = 1, 'pedido recebido dá entrada no estoque');
select t.ok((select estoque from produtos where id = :'prod_s') = 6, 'o estoque sobe com o que chegou');
select t.erro(format('select receber_pedido(%L)', :'ped'), '55000', 'o mesmo pedido não entra duas vezes');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro($$insert into fornecedores (nome) values ('Xis')$$, '42501', 'profissional não mexe em fornecedores');
reset role;

-- metas
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into metas (membro_id, mes, tipo, valor) values ('a0000000-0000-0000-0000-000000000002', date_trunc('month', now() at time zone 'America/Sao_Paulo')::date, 'faturamento', 500000);
insert into metas (mes, tipo, valor) values (date_trunc('month', now() at time zone 'America/Sao_Paulo')::date, 'atendimentos', 100);
insert into metas (membro_id, mes, tipo, valor) values ('a0000000-0000-0000-0000-000000000005', date_trunc('month', now() at time zone 'America/Sao_Paulo')::date, 'faturamento', 300000);
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.ok((select count(*) from progresso_metas((now() at time zone 'America/Sao_Paulo')::date)) = 2, 'profissional vê a meta dele e a do salão, não a dos colegas');
select t.ok((select realizado from progresso_metas((now() at time zone 'America/Sao_Paulo')::date) where tipo = 'faturamento') >= 10000, 'o faturamento do mês conta o que ele fez');
select t.erro($$insert into metas (mes, tipo, valor) values (date_trunc('month', now())::date, 'produtos', 1)$$, '42501', 'só o administrador define metas');
reset role;

-- cobrança pelo celular
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_c \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_c', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 8000);
select criar_cobranca_comanda(:'cmd_c') as cob \gset
select t.ok((:'cob'::jsonb ->> 'valor_centavos')::int = 8000, 'link de pagamento cobra o que falta na comanda');
select t.erro($$select cobranca_publica('x')$$, '42501', 'a cobrança só abre pelo servidor');
reset role;
set role service_role;
select t.ok((cobranca_publica(:'cob'::jsonb ->> 'token') ->> 'valor_centavos')::int = 8000, 'o link mostra o valor e os itens');
select t.ok(cobranca_paga_mp('999999', 8000, :'salao_a') = 'nao_encontrada', 'aviso de pagamento desconhecido não quita nada');
select criar_pedido_online('sorriso', 'vale', null, 5000, 'Tânia Compra', '11944440001', 'Mãe', 'Feliz dia') as ped_v \gset
select t.erro($$select criar_pedido_online('sorriso', 'vale', null, 100, 'Tânia', '11944440001', 'Mãe', null)$$, '22023', 'vale abaixo do mínimo é recusado');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select t.ok(confirmar_cobranca((:'cob'::jsonb ->> 'id')::uuid) = 'paga', 'recepção confirma o Pix da comanda');
select t.ok((select sum(valor_centavos) from comanda_pagamentos where comanda_id = :'cmd_c') = 8000, 'o Pix entra na comanda');
select t.ok(confirmar_cobranca((:'ped_v'::jsonb ->> 'id')::uuid) = 'paga', 'vale comprado pelo link é confirmado');
select t.ok((select count(*) from comandas c join comanda_itens i on i.comanda_id = c.id where c.observacao = 'Venda pelo link' and i.tipo::text = 'vale_presente' and c.status = 'aberta') = 1, 'vira comanda aberta com o vale, para a recepção fechar');
reset role;

-- área da cliente
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
select criar_link_cliente(:'sara') as tok_area \gset
select t.erro($$select token_hash from links_cliente$$, '42501', 'ninguém lê os links da cliente');
reset role;
set role service_role;
select area_cliente_preparar(:'tok_area');
select t.ok((area_cliente(:'tok_area') ->> 'nome') = 'Sara Indicada' and (area_cliente(:'tok_area') ->> 'codigo') ~ '^[A-Z2-9]{6}$', 'área da cliente abre com o código de indicação');
select t.ok((area_cliente(:'tok_area') -> 'fidelidade' ->> 'nivel') = 'Prata', 'a área mostra o nível de fidelidade');
select t.ok(area_cliente('errado') is null, 'link errado não abre nada');
reset role;

-- relatórios
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok(relatorios(current_date - 30, current_date) ? 'previsao', 'relatórios trazem a previsão de faturamento');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro($$select relatorios(current_date - 30, current_date)$$, '42501', 'profissional não vê relatórios');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok((select count(*) from cobrancas) + (select count(*) from metas) + (select count(*) from fornecedores) + (select count(*) from taxas_falta) = 0, 'outro salão não vê cobranças, metas, fornecedores nem taxas');
select t.ok(fidelidade(:'sara') is null, 'nem a fidelidade da cliente alheia');
reset role;

-- 39) política aceita guarda a taxa por falta
update saloes set taxa_falta_centavos = 2000 where id = :'salao_a';
set role service_role;
select agendar_online_grupo('sorriso', array[:'srv_a']::uuid[], 'a0000000-0000-0000-0000-000000000002', :'q1'::timestamptz + interval '63 days', 'Tina Taxa', '11922220001', true, null, null) as tina \gset
reset role;
select t.ok((select texto like '%Falta sem aviso: taxa de R$ 20,00 cobrada na próxima visita.' from aceites_politica where agendamento_id = (:'tina'::jsonb ->> 'agendamento_id')::uuid), 'a política aceita guarda a taxa por falta');

-- 40) endereço da cliente
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into clientes (nome, cep, logradouro, numero, bairro, cidade, uf) values ('Ana Endereço', '11430090', 'Avenida Manoel da Cruz Michael', '120', 'Jardim São Manoel', 'Guarujá', 'SP') returning id as end_a \gset
insert into clientes (nome, telefone) values ('Ana Sem Endereço', '11933330001') returning id as end_b \gset
insert into clientes (nome, bairro, cidade, uf) values ('Bia Vizinha', 'jardim são manoel ', 'Guarujá', 'SP');
select t.erro($$insert into clientes (nome, cep) values ('CEP ruim', '1143-009')$$, '23514', 'CEP tem 8 números');
select t.erro($$insert into clientes (nome, uf) values ('UF ruim', 'sp')$$, '23514', 'estado é a sigla');
select t.ok((bairros_clientes() -> 'bairros' -> 0 ->> 'clientes')::int = 2, 'o mesmo bairro escrito diferente conta junto');
select unir_clientes(:'end_b', :'end_a');
select t.ok((select logradouro = 'Avenida Manoel da Cruz Michael' and numero = '120' and cep = '11430090' and telefone = '11933330001' from clientes where id = :'end_b'), 'unir cadastros leva o endereço inteiro de quem tinha');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro($$select bairros_clientes()$$, '42501', 'profissional não vê os bairros');
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', false);
set role authenticated;
select t.ok(not (bairros_clientes() -> 'bairros') @> '[{"cidade": "Guarujá"}]', 'outro salão não vê os bairros das clientes alheias');
reset role;

-- 41) primeiro acesso guiado
select t.ok((select guia_concluido_em is null from saloes where id = :'salao_a'), 'salão novo começa pelo guia');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
update saloes set guia_concluido_em = now();
reset role;
select t.ok((select guia_concluido_em is null from saloes where id = :'salao_a'), 'profissional não encerra o guia do salão');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
update saloes set guia_concluido_em = now();
reset role;
select t.ok((select guia_concluido_em is not null from saloes where id = :'salao_a'), 'o administrador encerra o guia');
select t.ok((select guia_concluido_em is null from saloes where id = :'salao_b'), 'e só do próprio salão');

-- 42) banca de revisão: caixa só com permissão, desconto não come gorjeta, agenda travada
insert into caixas (salao_id, troco_inicial_centavos) select :'salao_a', 0 where not exists (select 1 from caixas where salao_id = :'salao_a' and fechado_em is null);
-- profissional não lança pagamento nem fecha comanda (gorjeta e vale "pagos" com Pix inventado)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_golpe \gset
insert into comanda_itens (comanda_id, tipo, descricao, profissional_id, preco_centavos) values (:'cmd_golpe', 'gorjeta', 'Gorjeta', 'a0000000-0000-0000-0000-000000000002', 500000);
select t.erro(format($q$insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (%L, 'pix', 500000)$q$, :'cmd_golpe'), '42501', 'profissional não lança pagamento');
select t.erro(format($q$select fechar_comanda(%L)$q$, :'cmd_golpe'), '42501', 'profissional não fecha comanda');
select t.erro(format($q$select usar_cashback(%L)$q$, :'cmd_golpe'), '42501', 'profissional não usa cashback da cliente');
select t.erro(format($q$select usar_vale_presente(%L, 'ABC')$q$, :'cmd_golpe'), '42501', 'profissional não usa vale-presente');
reset role;
-- com a permissão "caixa" ligada pelo admin, o profissional cobra (salão sem recepção)
update membros set permissoes = '{"caixa": true}' where user_id = 'a0000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
delete from comanda_itens where comanda_id = :'cmd_golpe';
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_golpe', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 5000);
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_golpe', 'pix', 5000);
select fechar_comanda(:'cmd_golpe');
select t.ok((select status from comandas where id = :'cmd_golpe') = 'fechada', 'com a permissão caixa o profissional fecha a comanda');
reset role;
update membros set permissoes = '{}' where user_id = 'a0000000-0000-0000-0000-000000000002';
-- desconto maior que os serviços não "paga" a gorjeta com dinheiro do salão
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
set role authenticated;
insert into comandas (cliente_id) values (:'pac_a') returning id as cmd_neg \gset
insert into comanda_itens (comanda_id, tipo, servico_id, descricao, profissional_id, preco_centavos) values (:'cmd_neg', 'servico', :'srv_a', 'Escova', 'a0000000-0000-0000-0000-000000000002', 1000);
insert into comanda_itens (comanda_id, tipo, descricao, profissional_id, preco_centavos) values (:'cmd_neg', 'gorjeta', 'Gorjeta', 'a0000000-0000-0000-0000-000000000002', 5000);
update comandas set desconto_centavos = 3000 where id = :'cmd_neg';
insert into comanda_pagamentos (comanda_id, forma, valor_centavos) values (:'cmd_neg', 'pix', 3000);
select t.erro(format($q$select fechar_comanda(%L)$q$, :'cmd_neg'), '22023', 'desconto maior que os serviços não fecha (gorjeta não vira dinheiro do salão)');
select t.ok((select status from comandas where id = :'cmd_neg') = 'aberta', 'e a comanda continua aberta');
reset role;
-- agenda: promoção, cliente e token não mudam pela API
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000002', :'srv_a', :'seg10'::timestamptz + interval '56 days') returning id as ag_trava \gset
select t.erro(format($q$update agendamentos set promocao_percentual = 70 where id = %L$q$, :'ag_trava'), '42501', 'ninguém inventa promoção no horário');
select t.erro(format($q$update agendamentos set token = gen_random_uuid() where id = %L$q$, :'ag_trava'), '42501', 'token do link não muda pela API');
select t.erro(format($q$update agendamentos set cliente_id = %L where id = %L$q$, :'pac_a', :'ag_trava'), '42501', 'cliente do horário não muda pela API');
select t.erro(format($q$insert into agendamentos (cliente_id, profissional_id, servico_id, inicio, token) values (%L, 'a0000000-0000-0000-0000-000000000002', %L, %L::timestamptz + interval '57 days', gen_random_uuid())$q$, :'pac_a', :'srv_a', :'seg10'), '42501', 'token não é escolhido por quem marca');
update agendamentos set status = 'confirmado' where id = :'ag_trava';
select t.ok((select status from agendamentos where id = :'ag_trava') = 'confirmado', 'situação do próprio horário continua mudando');
reset role;
-- profissional sem "agenda_outros" não marca falta no horário de outra pessoa
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into agendamentos (cliente_id, profissional_id, servico_id, inicio) values (:'pac_a', 'a0000000-0000-0000-0000-000000000001', :'srv_a', :'seg10'::timestamptz + interval '49 days') returning id as ag_outro \gset
reset role;
update membros set permissoes = '{"agenda_outros": false}' where user_id = 'a0000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
set role authenticated;
select t.erro(format($q$update agendamentos set status = 'faltou' where id = %L$q$, :'ag_outro'), '42501', 'sem a permissão, não marca falta no horário de outro');
select t.erro(format($q$update agendamentos set status = 'concluido' where id = %L$q$, :'ag_outro'), '42501', 'nem conclui o horário de outro');
reset role;
update membros set permissoes = '{}' where user_id = 'a0000000-0000-0000-0000-000000000002';
select t.ok((select status from agendamentos where id = :'ag_outro') = 'agendado', 'o horário do outro ficou como estava');
\echo
\echo TODOS OS TESTES PASSARAM
