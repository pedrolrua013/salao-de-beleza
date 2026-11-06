-- Belezando · agenda de salão.
-- 1) O serviço tem fases de trabalho e de pausa (ex.: coloração = aplicar 40 + pausa 40 + finalizar 40).
--    Na pausa a cliente espera a química agir e o profissional fica livre para atender outra pessoa.
-- 2) A trava de conflito sai do agendamento inteiro e passa para "ocupacoes": só as fases de trabalho e os bloqueios.
-- 3) Bloqueios (folga, férias, compromisso) e jornada de cada profissional (dias, entrada, saída, almoço).

-- ───────────── fases ─────────────

-- Lista de 1 a 5 fases {"tipo": "trabalho" | "pausa", "min": inteiro}, começando e terminando em trabalho, sem duas pausas seguidas.
create function fases_validas(f jsonb) returns boolean
language plpgsql immutable set search_path = public, pg_temp as
$$
declare
  e jsonb;
  anterior text := '';
begin
  if f is null or jsonb_typeof(f) <> 'array' or jsonb_array_length(f) not between 1 and 5 then return false; end if;
  for e in select * from jsonb_array_elements(f) loop
    if jsonb_typeof(e) <> 'object' or (e ->> 'tipo') is null or (e ->> 'tipo') not in ('trabalho', 'pausa')
       or jsonb_typeof(e -> 'min') <> 'number' then return false; end if;
    if (e ->> 'min')::numeric <> trunc((e ->> 'min')::numeric) or (e ->> 'min')::numeric not between 5 and 480 then return false; end if;
    if e ->> 'tipo' = 'pausa' and anterior <> 'trabalho' then return false; end if;
    anterior := e ->> 'tipo';
  end loop;
  return f -> 0 ->> 'tipo' = 'trabalho' and f -> -1 ->> 'tipo' = 'trabalho';
end
$$;

create function fases_total(f jsonb) returns int
language sql immutable set search_path = public, pg_temp as
$$ select coalesce(sum((e ->> 'min')::int), 0)::int from jsonb_array_elements(f) e $$;

revoke all on function fases_validas(jsonb), fases_total(jsonb) from public, anon;
grant execute on function fases_validas(jsonb), fases_total(jsonb) to authenticated, service_role;

alter table servicos add column fases jsonb;
update servicos set fases = jsonb_build_array(jsonb_build_object('tipo', 'trabalho', 'min', duracao_min));
alter table servicos alter column fases set not null;
alter table servicos add constraint fases_ok check (fases_validas(fases) and fases_total(fases) = duracao_min);

-- A duração passa a ser a soma das fases. Quem manda só a duração ganha uma fase única de trabalho.
create function preparar_servico() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.fases is null
     or (tg_op = 'UPDATE' and new.fases is not distinct from old.fases and new.duracao_min is distinct from old.duracao_min) then
    new.fases := jsonb_build_array(jsonb_build_object('tipo', 'trabalho', 'min', new.duracao_min));
  end if;
  if not fases_validas(new.fases) then
    raise exception 'fases inválidas' using errcode = '23514';
  end if;
  new.duracao_min := fases_total(new.fases);
  return new;
end
$$;
create trigger prep_servico before insert or update on servicos for each row execute function preparar_servico();

-- O agendamento guarda as fases do serviço no momento da marcação (mudar o catálogo não mexe no que já está marcado).
alter table agendamentos add column fases jsonb;
update agendamentos set fases = jsonb_build_array(jsonb_build_object('tipo', 'trabalho', 'min', greatest(5, round(extract(epoch from fim - inicio) / 60)::int)));
alter table agendamentos alter column fases set not null;
alter table agendamentos add constraint fases_ok check (fases_validas(fases));

create function preparar_agendamento() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.fases is null
     or (tg_op = 'UPDATE' and new.servico_id is distinct from old.servico_id and new.fases is not distinct from old.fases) then
    select s.fases into new.fases from servicos s where s.id = new.servico_id and s.salao_id = new.salao_id;
  end if;
  if new.fases is null or not fases_validas(new.fases) then
    raise exception 'fases inválidas' using errcode = '23514';
  end if;
  new.fim := new.inicio + make_interval(mins => fases_total(new.fases));
  return new;
end
$$;
create trigger prep_agendamento before insert or update on agendamentos for each row execute function preparar_agendamento();

-- ───────────── jornada do profissional ─────────────

-- Vazio = segue o salão. Vale para o robô e para os horários sugeridos; a equipe pode encaixar fora dela.
alter table membros add column dias_semana int[];
alter table membros add column entrada time;
alter table membros add column saida time;
alter table membros add column almoco_inicio time;
alter table membros add column almoco_fim time;
alter table membros add constraint jornada_ok check (
  (entrada is null or saida is null or saida > entrada)
  and ((almoco_inicio is null) = (almoco_fim is null))
  and (almoco_inicio is null or almoco_fim > almoco_inicio)
  and (dias_semana is null or dias_semana <@ array[1, 2, 3, 4, 5, 6, 7])
);
grant update (dias_semana, entrada, saida, almoco_inicio, almoco_fim) on membros to authenticated;

-- ───────────── bloqueios ─────────────

create table bloqueios (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  profissional_id uuid not null,
  inicio timestamptz not null,
  fim timestamptz not null,
  motivo text check (length(motivo) <= 120),
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  check (fim > inicio and fim - inicio <= interval '60 days'),
  unique (id, salao_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id) on delete cascade
);
create index on bloqueios (salao_id, inicio);
create index on bloqueios (profissional_id, salao_id);

alter table bloqueios enable row level security;
create policy bloqueios_ler on bloqueios for select to authenticated using (salao_id = meu_salao());
-- Administrador e recepção bloqueiam qualquer profissional; o profissional, só a própria agenda.
create policy bloqueios_criar on bloqueios for insert to authenticated
  with check (salao_id = meu_salao() and (meu_papel() in ('admin', 'recepcao') or profissional_id = auth.uid()));
create policy bloqueios_apagar on bloqueios for delete to authenticated
  using (salao_id = meu_salao() and (meu_papel() in ('admin', 'recepcao') or profissional_id = auth.uid()));
revoke all on bloqueios from anon, authenticated;
grant select, delete on bloqueios to authenticated;
grant insert (profissional_id, inicio, fim, motivo) on bloqueios to authenticated;
create trigger aud_bloqueios after insert or update or delete on bloqueios for each row execute function auditar();

-- ───────────── ocupações: a trava de conflito ─────────────

-- Cada linha é um intervalo em que o profissional está com as mãos ocupadas: uma fase de trabalho ou um bloqueio.
-- As pausas não entram, e por isso outra cliente pode ser encaixada nelas.
create table ocupacoes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  profissional_id uuid not null,
  agendamento_id uuid references agendamentos (id) on delete cascade,
  bloqueio_id uuid references bloqueios (id) on delete cascade,
  periodo tstzrange not null,
  check (num_nonnulls(agendamento_id, bloqueio_id) = 1),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id) on delete cascade,
  constraint sem_conflito_profissional exclude using gist (profissional_id with =, periodo with &&)
);
create index on ocupacoes (salao_id, periodo);
create index on ocupacoes (agendamento_id);
create index on ocupacoes (bloqueio_id);
create index on ocupacoes (profissional_id, salao_id);

alter table ocupacoes enable row level security;
create policy ocupacoes_ler on ocupacoes for select to authenticated using (salao_id = meu_salao());
revoke all on ocupacoes from anon, authenticated;
grant select on ocupacoes to authenticated;

alter table agendamentos drop constraint sem_conflito;

-- Refaz as ocupações de um agendamento. Cancelado ou falta libera tudo.
create function sincronizar_ocupacoes_agendamento() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  e jsonb;
  t timestamptz;
begin
  delete from ocupacoes where agendamento_id = new.id;
  if new.status in ('cancelado', 'faltou') then return new; end if;
  t := new.inicio;
  for e in select * from jsonb_array_elements(new.fases) loop
    if e ->> 'tipo' = 'trabalho' then
      insert into ocupacoes (salao_id, profissional_id, agendamento_id, periodo)
      values (new.salao_id, new.profissional_id, new.id, tstzrange(t, t + make_interval(mins => (e ->> 'min')::int)));
    end if;
    t := t + make_interval(mins => (e ->> 'min')::int);
  end loop;
  return new;
end
$$;
create trigger ocup_agendamento after insert or update of inicio, fim, fases, status, profissional_id on agendamentos
  for each row execute function sincronizar_ocupacoes_agendamento();

create function sincronizar_ocupacoes_bloqueio() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if tg_op = 'DELETE' then return old; end if;  -- a linha some junto (on delete cascade)
  delete from ocupacoes where bloqueio_id = new.id;
  insert into ocupacoes (salao_id, profissional_id, bloqueio_id, periodo)
  values (new.salao_id, new.profissional_id, new.id, tstzrange(new.inicio, new.fim));
  return new;
end
$$;
create trigger ocup_bloqueio after insert or update on bloqueios for each row execute function sincronizar_ocupacoes_bloqueio();

revoke execute on function preparar_servico(), preparar_agendamento(), sincronizar_ocupacoes_agendamento(), sincronizar_ocupacoes_bloqueio()
  from public, anon, authenticated;

-- Agendamentos que já existiam passam a ocupar a agenda pelo novo modelo.
insert into ocupacoes (salao_id, profissional_id, agendamento_id, periodo)
select salao_id, profissional_id, id, tstzrange(inicio, fim) from agendamentos where status not in ('cancelado', 'faltou');

-- ───────────── salão novo nasce com serviços de salão ─────────────

create or replace function criar_salao(p_nome text, p_slug text, p_nome_usuario text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_id uuid;
  t constant text := 'trabalho';
  p constant text := 'pausa';
begin
  if auth.uid() is null then
    raise exception 'não autenticado' using errcode = '28000';
  end if;
  if exists (select 1 from membros where user_id = auth.uid()) then
    raise exception 'usuário já pertence a um salão' using errcode = '23505';
  end if;
  insert into saloes (nome, slug) values (trim(p_nome), lower(trim(p_slug))) returning id into v_id;
  insert into membros (user_id, salao_id, papel, nome) values (auth.uid(), v_id, 'admin', trim(p_nome_usuario));
  insert into servicos (salao_id, nome, duracao_min, fases) values
    (v_id, 'Corte feminino', 60, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 60))),
    (v_id, 'Corte masculino', 30, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 30))),
    (v_id, 'Escova', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45))),
    (v_id, 'Coloração', 120, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 40), jsonb_build_object('tipo', p, 'min', 40), jsonb_build_object('tipo', t, 'min', 40))),
    (v_id, 'Hidratação', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 15), jsonb_build_object('tipo', p, 'min', 20), jsonb_build_object('tipo', t, 'min', 10))),
    (v_id, 'Manicure', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45))),
    (v_id, 'Pedicure', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45)));
  return v_id;
end
$$;

-- ───────────── robô: respeita fases, jornada, almoço e bloqueios ─────────────

create function cabe_na_jornada(p_salao uuid, p_prof uuid, p_inicio timestamptz, p_fases jsonb) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  c saloes;
  m membros;
  v_ini timestamp;
  v_fim timestamp;
  e jsonb;
  t timestamp;
  f timestamp;
begin
  select * into c from saloes where id = p_salao;
  select * into m from membros where user_id = p_prof and salao_id = p_salao;
  v_ini := p_inicio at time zone c.fuso;
  v_fim := v_ini + make_interval(mins => fases_total(p_fases));
  if v_ini::date <> v_fim::date
     or not (extract(isodow from v_ini)::int = any (coalesce(m.dias_semana, c.dias_semana)))
     or v_ini::time < coalesce(m.entrada, c.abre) or v_fim::time > coalesce(m.saida, c.fecha) then
    return false;
  end if;
  -- no almoço o profissional não trabalha, mas a pausa de uma química pode cair nele
  if m.almoco_inicio is not null then
    t := v_ini;
    for e in select * from jsonb_array_elements(p_fases) loop
      f := t + make_interval(mins => (e ->> 'min')::int);
      if e ->> 'tipo' = 'trabalho' and t::time < m.almoco_fim and f::time > m.almoco_inicio then return false; end if;
      t := f;
    end loop;
  end if;
  return true;
end
$$;
revoke all on function cabe_na_jornada(uuid, uuid, timestamptz, jsonb) from public, anon, authenticated;
grant execute on function cabe_na_jornada(uuid, uuid, timestamptz, jsonb) to service_role;

create or replace function agendar_whatsapp(
  p_salao uuid, p_conversa uuid, p_servico uuid, p_profissional uuid, p_inicio timestamptz,
  p_nome text, p_consentiu boolean
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c saloes;
  v_conv conversas;
  v_srv servicos;
  v_pac uuid;
  v_ag uuid;
begin
  select * into c from saloes where id = p_salao;
  select * into v_conv from conversas where id = p_conversa and salao_id = p_salao;
  select * into v_srv from servicos where id = p_servico and salao_id = p_salao and ativo;
  if c.id is null or v_conv.id is null or v_srv.id is null
     or not exists (select 1 from membros where user_id = p_profissional and salao_id = p_salao and ativo and papel in ('admin', 'profissional')) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;

  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(p_salao, p_profissional, p_inicio, v_srv.fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  v_pac := v_conv.cliente_id;
  if v_pac is null then
    select id into v_pac from clientes where salao_id = p_salao and tel_nacional(telefone) = v_conv.telefone order by criado_em limit 1;
  end if;
  if v_pac is null then
    if not coalesce(p_consentiu, false) then raise exception 'consentimento obrigatório' using errcode = '22023'; end if;
    if length(trim(coalesce(p_nome, ''))) < 2 then raise exception 'nome obrigatório' using errcode = '22023'; end if;
    insert into clientes (salao_id, nome, telefone, consentimento_em)
    values (p_salao, left(trim(p_nome), 120), v_conv.telefone, now()) returning id into v_pac;
  elsif coalesce(p_consentiu, false) then
    update clientes set consentimento_em = coalesce(consentimento_em, now()) where id = v_pac;
  elsif not exists (select 1 from clientes where id = v_pac and consentimento_em is not null) then
    raise exception 'consentimento obrigatório' using errcode = '22023';
  end if;

  begin
    insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fases, origem, status)
    values (p_salao, v_pac, p_profissional, p_servico, p_inicio, v_srv.fases, 'whatsapp', 'confirmado') returning id into v_ag;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;
  update conversas set cliente_id = v_pac where id = p_conversa;
  return v_ag;
end
$$;
