-- Belezando · vários serviços num mesmo atendimento e remarcação pela cliente.
-- Um atendimento com vários serviços vira vários horários com o mesmo grupo_id, em sequência.
-- O primeiro do grupo é o "líder": tem o token do link, o sinal e os lembretes; confirmar, cancelar e remarcar valem para o grupo.

alter table agendamentos add column grupo_id uuid;
create index on agendamentos (grupo_id) where grupo_id is not null;
grant insert (grupo_id) on agendamentos to authenticated;

-- Horários do mesmo grupo (ou só ele, se não tiver grupo).
create function do_grupo(p_ag uuid) returns setof agendamentos
language sql stable set search_path = public, pg_temp as
$$
  select x.* from agendamentos a join agendamentos x on x.id = a.id or (a.grupo_id is not null and x.grupo_id = a.grupo_id)
  where a.id = p_ag
$$;
revoke all on function do_grupo(uuid) from public, anon;
grant execute on function do_grupo(uuid) to authenticated, service_role;

-- Lembrete só do primeiro horário do atendimento (a cliente não recebe três mensagens).
create or replace function programar_lembretes(p_ag uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a agendamentos; c saloes; p clientes;
  v_agora timestamptz := now();
  v_vesp timestamptz; v_mesmo timestamptz;
begin
  select * into a from agendamentos where id = p_ag;
  if not found then return; end if;
  select * into c from saloes where id = a.salao_id;
  select * into p from clientes where id = a.cliente_id;

  -- tudo o que ainda não saiu é refeito do zero
  update lembretes set estado = 'cancelado' where agendamento_id = p_ag and estado = 'pendente';
  -- vários serviços no mesmo atendimento: só o primeiro horário do grupo manda lembrete
  if a.grupo_id is not null and exists (select 1 from agendamentos o where o.grupo_id = a.grupo_id and o.id <> a.id
      and o.status not in ('cancelado', 'faltou') and (o.inicio, o.id) < (a.inicio, a.id)) then
    return;
  end if;

  if not c.lembretes_ativos or a.status <> 'agendado' or a.inicio < v_agora + interval '1 hour'
     or p.telefone is null or p.consentimento_em is null or p.recusou_lembretes_em is not null then
    return;
  end if;

  v_vesp := (((a.inicio at time zone c.fuso)::date - 1) + c.lembrete_hora) at time zone c.fuso;
  v_mesmo := a.inicio - interval '3 hours';

  if v_vesp > v_agora + interval '5 minutes' then
    insert into lembretes (salao_id, agendamento_id, tipo, inicio_ref, enviar_em)
    values (a.salao_id, a.id, 'vespera', a.inicio, v_vesp)
    on conflict (agendamento_id, tipo, inicio_ref) do update set enviar_em = excluded.enviar_em, estado = 'pendente'
      where lembretes.estado in ('cancelado', 'pendente', 'ignorado');
  elsif a.origem = 'interno' and a.inicio > v_agora + interval '4 hours' then
    -- marcada pela recepção em cima da hora: pede a confirmação agora
    insert into lembretes (salao_id, agendamento_id, tipo, inicio_ref, enviar_em)
    values (a.salao_id, a.id, 'confirmacao', a.inicio, v_agora)
    on conflict (agendamento_id, tipo, inicio_ref) do update set enviar_em = excluded.enviar_em, estado = 'pendente'
      where lembretes.estado in ('cancelado', 'pendente', 'ignorado');
  end if;

  -- segundo aviso: só em horário decente
  if v_mesmo > v_agora + interval '30 minutes'
     and (v_mesmo at time zone c.fuso)::time between time '07:00' and time '20:00' then
    insert into lembretes (salao_id, agendamento_id, tipo, inicio_ref, enviar_em)
    values (a.salao_id, a.id, 'mesmo_dia', a.inicio, v_mesmo)
    on conflict (agendamento_id, tipo, inicio_ref) do update set enviar_em = excluded.enviar_em, estado = 'pendente'
      where lembretes.estado in ('cancelado', 'pendente', 'ignorado');
  end if;
end
$$;

-- Confirmar ou cancelar pelo lembrete vale para todos os serviços do atendimento.
create or replace function responder_lembrete(p_salao uuid, p_wa_id text, p_lembrete uuid, p_resposta text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare l lembretes; a agendamentos; p clientes; v_novo status_agendamento; v_valida boolean;
begin
  if p_resposta not in ('confirmou', 'remarcar', 'cancelou') then
    return jsonb_build_object('ok', false, 'motivo', 'resposta_invalida');
  end if;
  select * into l from lembretes where id = p_lembrete and salao_id = p_salao;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'nao_encontrado'); end if;
  select * into a from agendamentos where id = l.agendamento_id;
  select * into p from clientes where id = a.cliente_id;
  if tel_nacional(p.telefone) is distinct from tel_nacional(p_wa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'telefone_diferente');
  end if;
  if l.resposta is not null then
    return jsonb_build_object('ok', true, 'repetida', true, 'acao', l.resposta, 'agendamento_id', a.id, 'inicio', a.inicio, 'status', a.status);
  end if;
  v_valida := a.inicio > now() and a.inicio = l.inicio_ref and a.status in ('agendado', 'confirmado');
  if not v_valida then
    return jsonb_build_object('ok', false, 'motivo', 'consulta_mudou', 'inicio', a.inicio, 'status', a.status);
  end if;

  if p_resposta = 'confirmou' then
    update agendamentos set status = 'confirmado' where id in (select id from do_grupo(a.id)) and status = 'agendado';
  elsif p_resposta = 'cancelou' then
    update agendamentos set status = 'cancelado' where id in (select id from do_grupo(a.id)) and status in ('agendado', 'confirmado');
  end if;
  update lembretes set estado = 'respondido', resposta = p_resposta, respondido_em = now() where id = l.id;
  select status into v_novo from agendamentos where id = a.id;
  return jsonb_build_object('ok', true, 'acao', p_resposta, 'agendamento_id', a.id, 'inicio', a.inicio, 'status', v_novo,
    'servico_id', a.servico_id, 'profissional_id', a.profissional_id);
end
$$;

-- O teto de 3 horários futuros conta atendimentos (um atendimento com 3 serviços conta como 1).
create or replace function limitar_agendamentos_whatsapp() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if new.origem in ('whatsapp', 'online') and new.status in ('agendado', 'confirmado') and
     (select count(distinct coalesce(a.grupo_id, a.id)) from agendamentos a
      where a.cliente_id = new.cliente_id and a.status in ('agendado', 'confirmado') and a.inicio > now()
        and (new.grupo_id is null or a.grupo_id is distinct from new.grupo_id)) >= 3 then
    raise exception 'limite_agendamentos' using errcode = '22023';
  end if;
  return new;
end
$$;

create or replace function expirar_sinais() returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  n int;
begin
  with e as (
    update sinais set status = 'expirado' where status = 'pendente' and expira_em < now() returning agendamento_id
  )
  update agendamentos a set status = 'cancelado' from e, lateral do_grupo(e.agendamento_id) g where a.id = g.id and a.status = 'agendado';
  get diagnostics n = row_count;
  return n;
end
$$;

create or replace function confirmar_sinal(p_agendamento uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção confirmam sinal' using errcode = '42501'; end if;
  update sinais set status = 'pago', pago_em = now(), confirmado_por = auth.uid()
  where agendamento_id = p_agendamento and salao_id = meu_salao() and status in ('pendente', 'expirado');
  if not found then raise exception 'sinal_nao_encontrado' using errcode = 'P0002'; end if;
  update agendamentos set status = 'confirmado' where id in (select id from do_grupo(p_agendamento)) and status in ('agendado', 'cancelado');
end
$$;

create or replace function sinal_pago_mp(p_payment_id text, p_valor_centavos int, p_salao uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  x sinais;
begin
  select * into x from sinais where mp_payment_id = p_payment_id and salao_id = p_salao for update;
  if x.id is null or x.status not in ('pendente', 'expirado', 'cancelado') or p_valor_centavos < x.valor_centavos then return false; end if;
  if x.status = 'cancelado' then
    update sinais set status = 'credito', pago_em = now() where id = x.id;
    return true;
  end if;
  update sinais set status = 'pago', pago_em = now() where id = x.id;
  begin
    update agendamentos set status = 'confirmado' where id in (select id from do_grupo(x.agendamento_id)) and status in ('agendado', 'cancelado');
  exception when exclusion_violation then
    update sinais set status = 'credito' where id = x.id;
  end;
  return true;
end
$$;

-- Cancelar pelo link cancela todos os serviços do atendimento.
create or replace function cancelar_online(p_token uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a agendamentos;
  c saloes;
begin
  select * into a from agendamentos where token = p_token for update;
  if a.id is null then return 'nao_encontrado'; end if;
  select * into c from saloes where id = a.salao_id;
  if a.status not in ('agendado', 'confirmado') then return 'ja_cancelado'; end if;
  if a.inicio - now() < make_interval(hours => c.cancelamento_horas) then return 'fora_do_prazo'; end if;
  update agendamentos set status = 'cancelado' where id in (select id from do_grupo(a.id)) and status in ('agendado', 'confirmado');
  update sinais set status = case status when 'pago' then 'credito' when 'pendente' then 'cancelado' else status end where agendamento_id = a.id;
  return 'cancelado';
end
$$;

-- A página do horário mostra todos os serviços do atendimento.
create or replace function horario_publico(p_token uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object(
    'id', a.id, 'inicio', a.inicio, 'fim', (select max(g.fim) from do_grupo(a.id) g where g.status <> 'cancelado'), 'status', a.status,
    'servico', (select string_agg(sv.nome, ' + ' order by g.inicio) from do_grupo(a.id) g join servicos sv on sv.id = g.servico_id where g.status <> 'cancelado' or a.status = 'cancelado'),
    'servico_ids', (select jsonb_agg(g.servico_id order by g.inicio) from do_grupo(a.id) g),
    'profissional_id', a.profissional_id, 'profissional', m.nome,
    'cliente', split_part(coalesce((select p.nome_informado from aceites_politica p where p.agendamento_id = a.id order by aceito_em desc limit 1), 'Olá'), ' ', 1),
    'salao', c.nome, 'slug', c.slug, 'fuso', c.fuso, 'endereco', c.endereco, 'telefone', c.telefone,
    'cancelamento_horas', c.cancelamento_horas,
    'pode_cancelar', a.status in ('agendado', 'confirmado') and a.inicio - now() >= make_interval(hours => c.cancelamento_horas),
    'sinal', (select jsonb_build_object('valor', x.valor_centavos, 'status', x.status, 'modo', x.modo, 'copia_cola', x.copia_cola, 'expira_em', x.expira_em)
              from sinais x where x.agendamento_id = a.id),
    'politica', (select texto from aceites_politica p where p.agendamento_id = a.id order by aceito_em desc limit 1)
  )
  from agendamentos a join saloes c on c.id = a.salao_id join servicos s on s.id = a.servico_id
  join membros m on m.user_id = a.profissional_id and m.salao_id = a.salao_id
  where a.token = p_token
$$;

-- Vários serviços pelo link: um depois do outro, com o mesmo profissional.
create function agendar_online_grupo(
  p_slug text, p_servicos uuid[], p_profissional uuid, p_inicio timestamptz,
  p_nome text, p_telefone text, p_aceite_contato boolean, p_ip text, p_agente text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c saloes;
  v_srv servicos;
  v_tel text := tel_nacional(p_telefone);
  v_cli uuid;
  v_ag agendamentos;
  v_sinal int;
  v_mp boolean;
  v_texto text;
  v_fases jsonb := '[]';
  v_grupo uuid;
  v_t timestamptz;
  v_lider agendamentos;
  v_sid uuid;
  k int;
begin
  select * into c from saloes where slug = lower(p_slug) and agendamento_online;
  if c.id is null then raise exception 'salao_indisponivel' using errcode = 'P0002'; end if;
  if coalesce(array_length(p_servicos, 1), 0) not between 1 and 4 then raise exception 'dados inválidos' using errcode = '22023'; end if;
  -- o atendimento inteiro precisa caber: as fases dos serviços em sequência
  v_sinal := 0;
  foreach v_sid in array p_servicos loop
    select * into v_srv from servicos where id = v_sid and salao_id = c.id and ativo and online;
    if v_srv.id is null then raise exception 'dados inválidos' using errcode = '22023'; end if;
    v_fases := v_fases || v_srv.fases;
    v_sinal := v_sinal + round(coalesce(v_srv.preco_centavos, 0) * v_srv.sinal_percentual / 100.0)::int;
  end loop;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = c.id and ativo and papel in ('admin', 'profissional')) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_nome, ''))) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if not coalesce(p_aceite_contato, false) then raise exception 'consentimento obrigatório' using errcode = '22023'; end if;
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(c.id, p_profissional, p_inicio, v_fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  -- Telefone já cadastrado: o horário entra nesse cadastro, mas o aceite de contato não é herdado de quem digitou
  -- (sem verificar o número, qualquer um poderia ligar lembretes no WhatsApp de outra pessoa).
  select id into v_cli from clientes where salao_id = c.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli is null then
    insert into clientes (salao_id, nome, telefone, consentimento_em, origem) values (c.id, left(trim(p_nome), 120), v_tel, now(), 'outro') returning id into v_cli;
  end if;

  v_mp := exists (select 1 from pagamentos_contas where salao_id = c.id and mp_access_token is not null);
  if c.pix_chave is null and not v_mp then v_sinal := 0; end if;
  v_grupo := case when array_length(p_servicos, 1) > 1 then gen_random_uuid() end;
  v_t := p_inicio;
  begin
    for k in 1 .. array_length(p_servicos, 1) loop
      select * into v_srv from servicos where id = p_servicos[k];
      insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fases, origem, status, grupo_id)
      values (c.id, v_cli, p_profissional, v_srv.id, v_t, v_srv.fases, 'online', case when v_sinal > 0 then 'agendado' else 'confirmado' end::status_agendamento, v_grupo)
      returning * into v_ag;
      if k = 1 then v_lider := v_ag; end if;
      v_t := v_ag.fim;
    end loop;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;
  v_ag := v_lider;

  v_texto := coalesce(nullif(trim(c.politica_cancelamento), ''),
    format('Cancelamentos e remarcações até %s horas antes do horário. Depois disso, ou em caso de falta, o sinal não é devolvido.', c.cancelamento_horas));
  insert into aceites_politica (salao_id, agendamento_id, cliente_id, texto, ip, agente, nome_informado)
  values (c.id, v_ag.id, v_cli, v_texto, left(p_ip, 64), left(p_agente, 300), left(trim(p_nome), 120));
  if v_sinal > 0 then
    insert into sinais (salao_id, agendamento_id, valor_centavos, modo) values (c.id, v_ag.id, v_sinal, case when v_mp then 'mercadopago' else 'pix_manual' end);
  end if;
  return jsonb_build_object('agendamento_id', v_ag.id, 'token', v_ag.token, 'sinal_centavos', v_sinal);
end
$$;

create or replace function agendar_online(
  p_slug text, p_servico uuid, p_profissional uuid, p_inicio timestamptz,
  p_nome text, p_telefone text, p_aceite_contato boolean, p_ip text, p_agente text
) returns jsonb
language sql security definer set search_path = public, pg_temp as
$$ select agendar_online_grupo(p_slug, array[p_servico], p_profissional, p_inicio, p_nome, p_telefone, p_aceite_contato, p_ip, p_agente) $$;

-- Remarcar pelo link: o atendimento inteiro muda de horário (e de profissional, se ela escolher) numa operação só.
-- O horário antigo só é liberado porque o novo foi garantido; se o novo não couber, nada muda.
create function remarcar_online(p_token uuid, p_inicio timestamptz, p_profissional uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a agendamentos;
  c saloes;
  v_fases jsonb := '[]';
  r record;
  v_t timestamptz;
begin
  select * into a from agendamentos where token = p_token for update;
  if a.id is null then return 'nao_encontrado'; end if;
  select * into c from saloes where id = a.salao_id;
  if a.status not in ('agendado', 'confirmado') then return 'ja_cancelado'; end if;
  if a.inicio - now() < make_interval(hours => c.cancelamento_horas) then return 'fora_do_prazo'; end if;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = a.salao_id and ativo and papel in ('admin', 'profissional')) then return 'dados_invalidos'; end if;
  select coalesce(jsonb_agg(f order by g.inicio, ord), '[]') into v_fases
  from do_grupo(a.id) g, jsonb_array_elements(g.fases) with ordinality as e(f, ord) where g.status in ('agendado', 'confirmado');
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(a.salao_id, p_profissional, p_inicio, v_fases) then return 'horario_indisponivel'; end if;
  -- solta as ocupações do atendimento antes de mover (senão um serviço esbarra no outro no meio da troca)
  v_t := p_inicio;
  begin
    delete from ocupacoes where agendamento_id in (select id from do_grupo(a.id));
    for r in select * from do_grupo(a.id) where status in ('agendado', 'confirmado') order by inicio loop
      update agendamentos set inicio = v_t, profissional_id = p_profissional where id = r.id returning fim into v_t;
    end loop;
  exception when exclusion_violation then
    return 'horario_indisponivel';  -- a exceção desfaz tudo o que foi feito dentro do bloco
  end;
  return 'remarcado';
end
$$;

revoke all on function agendar_online_grupo(text, uuid[], uuid, timestamptz, text, text, boolean, text, text), remarcar_online(uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function agendar_online_grupo(text, uuid[], uuid, timestamptz, text, text, boolean, text, text), remarcar_online(uuid, timestamptz, uuid) to service_role;
revoke all on function agendar_online(text, uuid, uuid, timestamptz, text, text, boolean, text, text) from public, anon, authenticated;
grant execute on function agendar_online(text, uuid, uuid, timestamptz, text, text, boolean, text, text) to service_role;
