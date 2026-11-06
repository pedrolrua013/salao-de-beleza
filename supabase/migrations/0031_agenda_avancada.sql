-- Belezando · agenda avançada: tamanhos de cabelo, preço e tempo por profissional, recursos do salão, intervalo de limpeza,
-- cor do serviço, horários que se repetem, cliente VIP/bloqueada, regras de antecedência e fila de quem chega sem hora.

-- ───────────── serviços: cor e intervalo de limpeza ─────────────
alter table servicos add column cor text check (cor ~ '^#[0-9A-Fa-f]{6}$');
alter table servicos add column intervalo_min int not null default 0 check (intervalo_min between 0 and 60);
grant update (cor, intervalo_min) on servicos to authenticated;

-- ───────────── tamanhos (variações) e preço/tempo por profissional ─────────────
create table servico_variacoes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  servico_id uuid not null,
  nome text not null check (length(nome) between 1 and 40),
  preco_centavos int not null default 0 check (preco_centavos between 0 and 10000000),
  fases jsonb not null check (fases_validas(fases)),
  ordem int not null default 0,
  unique (servico_id, nome),
  unique (id, salao_id),
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade
);
create index on servico_variacoes (salao_id);

create table servico_profissional (
  servico_id uuid not null,
  profissional_id uuid not null,
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  preco_centavos int check (preco_centavos between 0 and 10000000),
  fases jsonb check (fases is null or fases_validas(fases)),
  primary key (servico_id, profissional_id),
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade,
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id) on delete cascade
);
create index on servico_profissional (salao_id);

alter table servico_variacoes enable row level security;
alter table servico_profissional enable row level security;
create policy var_ler on servico_variacoes for select to authenticated using (salao_id = (select meu_salao()));
create policy var_escrever on servico_variacoes for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy var_editar on servico_variacoes for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin') with check (salao_id = (select meu_salao()));
create policy var_apagar on servico_variacoes for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy sp_ler on servico_profissional for select to authenticated using (salao_id = (select meu_salao()));
create policy sp_escrever on servico_profissional for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy sp_editar on servico_profissional for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin') with check (salao_id = (select meu_salao()));
create policy sp_apagar on servico_profissional for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on servico_variacoes, servico_profissional from anon, authenticated;
grant select, insert, update, delete on servico_variacoes, servico_profissional to authenticated;
create trigger aud_variacoes after insert or update or delete on servico_variacoes for each row execute function auditar();

-- Tempo e preço de um serviço: o tamanho escolhido vale primeiro, depois o do profissional, depois o do catálogo.
create function fases_de(p_servico uuid, p_prof uuid, p_variacao uuid) returns jsonb
language sql stable set search_path = public, pg_temp as
$$
  select coalesce(
    (select fases from servico_variacoes where id = p_variacao and servico_id = p_servico),
    (select fases from servico_profissional where servico_id = p_servico and profissional_id = p_prof),
    (select fases from servicos where id = p_servico))
$$;
create function preco_de(p_servico uuid, p_prof uuid, p_variacao uuid) returns int
language sql stable set search_path = public, pg_temp as
$$
  select coalesce(
    (select preco_centavos from servico_variacoes where id = p_variacao and servico_id = p_servico),
    (select preco_centavos from servico_profissional where servico_id = p_servico and profissional_id = p_prof),
    (select preco_centavos from servicos where id = p_servico), 0)
$$;
revoke all on function fases_de(uuid, uuid, uuid), preco_de(uuid, uuid, uuid) from public, anon;
grant execute on function fases_de(uuid, uuid, uuid), preco_de(uuid, uuid, uuid) to authenticated, service_role;

-- ───────────── agendamento: tamanho, intervalo e série ─────────────
alter table agendamentos add column variacao_id uuid references servico_variacoes (id) on delete set null;
alter table agendamentos add column intervalo_min int not null default 0 check (intervalo_min between 0 and 60);
alter table agendamentos add column serie_id uuid;
create index on agendamentos (serie_id) where serie_id is not null;
grant insert (variacao_id, serie_id) on agendamentos to authenticated;
grant update (variacao_id) on agendamentos to authenticated;

create or replace function preparar_agendamento() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.variacao_id is not null and not exists (select 1 from servico_variacoes v where v.id = new.variacao_id and v.servico_id = new.servico_id) then
    raise exception 'tamanho não é deste serviço' using errcode = '23514';
  end if;
  if new.fases is null
     or (tg_op = 'UPDATE' and (new.servico_id is distinct from old.servico_id or new.variacao_id is distinct from old.variacao_id) and new.fases is not distinct from old.fases) then
    new.fases := fases_de(new.servico_id, new.profissional_id, new.variacao_id);
  end if;
  if new.fases is null or not fases_validas(new.fases) then
    raise exception 'fases inválidas' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' or new.servico_id is distinct from old.servico_id then
    new.intervalo_min := coalesce((select intervalo_min from servicos where id = new.servico_id), 0);
  end if;
  new.fim := new.inicio + make_interval(mins => fases_total(new.fases));
  return new;
end
$$;

-- O intervalo de limpeza também ocupa o profissional (ninguém é marcado colado).
create or replace function sincronizar_ocupacoes_agendamento() returns trigger
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
  if new.intervalo_min > 0 then
    insert into ocupacoes (salao_id, profissional_id, agendamento_id, periodo)
    values (new.salao_id, new.profissional_id, new.id, tstzrange(t, t + make_interval(mins => new.intervalo_min)));
  end if;
  return new;
end
$$;

-- ───────────── recursos do salão (lavatório, sala, cadeira) ─────────────
create table recursos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 60),
  quantidade int not null default 1 check (quantidade between 1 and 50),
  unique (id, salao_id)
);
create table servico_recursos (
  servico_id uuid not null,
  recurso_id uuid not null,
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  primary key (servico_id, recurso_id),
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade,
  foreign key (recurso_id, salao_id) references recursos (id, salao_id) on delete cascade
);
create index on servico_recursos (recurso_id);
alter table recursos enable row level security;
alter table servico_recursos enable row level security;
create policy rec_ler on recursos for select to authenticated using (salao_id = (select meu_salao()));
create policy rec_escrever on recursos for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy rec_editar on recursos for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin') with check (salao_id = (select meu_salao()));
create policy rec_apagar on recursos for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy srec_ler on servico_recursos for select to authenticated using (salao_id = (select meu_salao()));
create policy srec_escrever on servico_recursos for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy srec_apagar on servico_recursos for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on recursos, servico_recursos from anon, authenticated;
grant select, insert, update, delete on recursos to authenticated;
grant select, insert, delete on servico_recursos to authenticated;

-- Dois atendimentos não usam o mesmo recurso ao mesmo tempo além da quantidade (só nas fases de trabalho).
-- Roda depois das ocupações (nome com "zz") e trava o recurso, para dois pedidos simultâneos não passarem juntos.
create function checar_recursos() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  r recursos;
  n int;
begin
  if new.status in ('cancelado', 'faltou') then return new; end if;
  for r in select x.* from recursos x join servico_recursos sr on sr.recurso_id = x.id where sr.servico_id = new.servico_id order by x.id for update of x loop
    select count(distinct a2.id) into n
    from agendamentos a2
    join servico_recursos s2 on s2.servico_id = a2.servico_id and s2.recurso_id = r.id
    where a2.salao_id = new.salao_id and a2.id <> new.id and a2.status not in ('cancelado', 'faltou')
      and exists (select 1 from ocupacoes o1 join ocupacoes o2 on o2.agendamento_id = a2.id and o2.periodo && o1.periodo where o1.agendamento_id = new.id);
    if n >= r.quantidade then
      raise exception 'recurso_ocupado: %', r.nome using errcode = '23P01';
    end if;
  end loop;
  return new;
end
$$;
create trigger zz_recursos after insert or update of inicio, fim, fases, status, servico_id, profissional_id on agendamentos
  for each row execute function checar_recursos();
revoke execute on function checar_recursos() from public, anon, authenticated;

-- ───────────── cliente VIP, bloqueada e que sempre paga sinal ─────────────
alter table clientes add column vip boolean not null default false;
alter table clientes add column bloqueada boolean not null default false;
alter table clientes add column sempre_sinal boolean not null default false;
grant insert (vip, bloqueada, sempre_sinal) on clientes to authenticated;
grant update (vip, bloqueada, sempre_sinal) on clientes to authenticated;

-- ───────────── regras de antecedência e sinal padrão ─────────────
alter table saloes add column antecedencia_min_horas int not null default 1 check (antecedencia_min_horas between 0 and 72);
alter table saloes add column antecedencia_max_dias int not null default 60 check (antecedencia_max_dias between 7 and 365);
alter table saloes add column sinal_padrao_percentual int not null default 30 check (sinal_padrao_percentual between 1 and 100);
grant update (antecedencia_min_horas, antecedencia_max_dias, sinal_padrao_percentual) on saloes to authenticated;

-- Horário dentro das regras do salão (de fora: link e robô).
create function dentro_da_antecedencia(c saloes, p_inicio timestamptz) returns boolean
language sql stable set search_path = public, pg_temp as
$$ select p_inicio >= now() + make_interval(hours => c.antecedencia_min_horas) and p_inicio <= now() + make_interval(days => c.antecedencia_max_dias) $$;
revoke all on function dentro_da_antecedencia(saloes, timestamptz) from public, anon, authenticated;

-- Link: agora com tamanho por serviço, preço/tempo do profissional, cliente bloqueada/VIP/sempre sinal e regras de antecedência.
drop function agendar_online_grupo(text, uuid[], uuid, timestamptz, text, text, boolean, text, text);
create function agendar_online_grupo(
  p_slug text, p_servicos uuid[], p_profissional uuid, p_inicio timestamptz,
  p_nome text, p_telefone text, p_aceite_contato boolean, p_ip text, p_agente text, p_variacoes uuid[] default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c saloes;
  v_srv servicos;
  v_tel text := tel_nacional(p_telefone);
  v_cli clientes;
  v_cli_id uuid;
  v_ag agendamentos;
  v_sinal int;
  v_preco int := 0;
  v_mp boolean;
  v_texto text;
  v_novo boolean := false;
  v_fases jsonb := '[]';
  v_grupo uuid;
  v_t timestamptz;
  v_lider agendamentos;
  v_var uuid;
  k int;
begin
  select * into c from saloes where slug = lower(p_slug) and agendamento_online;
  if c.id is null then raise exception 'salao_indisponivel' using errcode = 'P0002'; end if;
  if p_ip is not null and (select count(distinct agendamento_id) from aceites_politica where ip = p_ip and aceito_em > now() - interval '1 hour') >= 5 then
    raise exception 'muitas_tentativas' using errcode = '54000';
  end if;
  if (select count(distinct agendamento_id) from aceites_politica where salao_id = c.id and aceito_em > now() - interval '1 hour') >= 40 then
    raise exception 'muitas_tentativas' using errcode = '54000';
  end if;
  if coalesce(array_length(p_servicos, 1), 0) not between 1 and 4 then raise exception 'dados inválidos' using errcode = '22023'; end if;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = c.id and ativo and papel in ('admin', 'profissional')) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;
  v_sinal := 0;
  for k in 1 .. array_length(p_servicos, 1) loop
    select * into v_srv from servicos where id = p_servicos[k] and salao_id = c.id and ativo and online;
    if v_srv.id is null then raise exception 'dados inválidos' using errcode = '22023'; end if;
    v_var := p_variacoes[k];
    if v_var is not null and not exists (select 1 from servico_variacoes where id = v_var and servico_id = v_srv.id) then raise exception 'dados inválidos' using errcode = '22023'; end if;
    v_fases := v_fases || fases_de(v_srv.id, p_profissional, v_var);
    v_preco := v_preco + preco_de(v_srv.id, p_profissional, v_var);
    v_sinal := v_sinal + round(preco_de(v_srv.id, p_profissional, v_var) * v_srv.sinal_percentual / 100.0)::int;
  end loop;
  if length(trim(coalesce(p_nome, ''))) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if not coalesce(p_aceite_contato, false) then raise exception 'consentimento obrigatório' using errcode = '22023'; end if;
  if not dentro_da_antecedencia(c, p_inicio) or not cabe_na_jornada(c.id, p_profissional, p_inicio, v_fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  -- Telefone já cadastrado: o horário entra nesse cadastro, mas o aceite de contato não é herdado de quem digitou.
  select * into v_cli from clientes where salao_id = c.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli.id is not null and v_cli.bloqueada then raise exception 'cliente_bloqueada' using errcode = '42501'; end if;
  v_cli_id := v_cli.id;
  if v_cli_id is null then
    insert into clientes (salao_id, nome, telefone, consentimento_em) values (c.id, left(trim(p_nome), 120), v_tel, now()) returning id into v_cli_id;
    v_novo := true;
  end if;
  -- VIP não paga sinal; quem "sempre paga sinal" paga o sinal padrão mesmo em serviço sem sinal.
  if coalesce(v_cli.vip, false) then v_sinal := 0;
  elsif coalesce(v_cli.sempre_sinal, false) and v_sinal = 0 then v_sinal := round(v_preco * c.sinal_padrao_percentual / 100.0)::int;
  end if;

  v_mp := exists (select 1 from pagamentos_contas where salao_id = c.id and mp_access_token is not null);
  if c.pix_chave is null and not v_mp then v_sinal := 0; end if;
  v_grupo := case when array_length(p_servicos, 1) > 1 then gen_random_uuid() end;
  v_t := p_inicio;
  begin
    for k in 1 .. array_length(p_servicos, 1) loop
      insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, variacao_id, inicio, fases, origem, status, grupo_id)
      values (c.id, v_cli_id, p_profissional, p_servicos[k], p_variacoes[k], v_t, fases_de(p_servicos[k], p_profissional, p_variacoes[k]), 'online',
              case when v_sinal > 0 then 'agendado' else 'confirmado' end::status_agendamento, v_grupo)
      returning * into v_ag;
      if k = 1 then v_lider := v_ag; end if;
      v_t := v_ag.fim + make_interval(mins => v_ag.intervalo_min);
    end loop;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;
  v_ag := v_lider;

  v_texto := coalesce(nullif(trim(c.politica_cancelamento), ''),
    format('Cancelamentos e remarcações até %s horas antes do horário. Depois disso, ou em caso de falta, o sinal não é devolvido.', c.cancelamento_horas));
  insert into aceites_politica (salao_id, agendamento_id, cliente_id, texto, ip, agente, nome_informado)
  values (c.id, v_ag.id, v_cli_id, v_texto, left(p_ip, 64), left(p_agente, 300), left(trim(p_nome), 120));
  if v_sinal > 0 then
    insert into sinais (salao_id, agendamento_id, valor_centavos, modo) values (c.id, v_ag.id, v_sinal, case when v_mp then 'mercadopago' else 'pix_manual' end);
  end if;
  return jsonb_build_object('agendamento_id', v_ag.id, 'token', v_ag.token, 'sinal_centavos', v_sinal, 'cliente_novo', v_novo);
end
$$;
revoke all on function agendar_online_grupo(text, uuid[], uuid, timestamptz, text, text, boolean, text, text, uuid[]) from public, anon, authenticated;
grant execute on function agendar_online_grupo(text, uuid[], uuid, timestamptz, text, text, boolean, text, text, uuid[]) to service_role;

-- Robô: tamanho, preço/tempo do profissional, cliente bloqueada e antecedência.
drop function agendar_whatsapp(uuid, uuid, uuid, uuid, timestamptz, text, boolean);
create function agendar_whatsapp(
  p_salao uuid, p_conversa uuid, p_servico uuid, p_profissional uuid, p_inicio timestamptz,
  p_nome text, p_consentiu boolean, p_variacao uuid default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c saloes;
  v_conv conversas;
  v_srv servicos;
  v_pac uuid;
  v_ag uuid;
  v_fases jsonb;
begin
  select * into c from saloes where id = p_salao;
  select * into v_conv from conversas where id = p_conversa and salao_id = p_salao;
  select * into v_srv from servicos where id = p_servico and salao_id = p_salao and ativo;
  if c.id is null or v_conv.id is null or v_srv.id is null
     or not exists (select 1 from membros where user_id = p_profissional and salao_id = p_salao and ativo and papel in ('admin', 'profissional'))
     or (p_variacao is not null and not exists (select 1 from servico_variacoes where id = p_variacao and servico_id = p_servico)) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;
  v_fases := fases_de(p_servico, p_profissional, p_variacao);
  if not dentro_da_antecedencia(c, p_inicio) or not cabe_na_jornada(p_salao, p_profissional, p_inicio, v_fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  v_pac := v_conv.cliente_id;
  if v_pac is null then
    select id into v_pac from clientes where salao_id = p_salao and tel_nacional(telefone) = v_conv.telefone order by criado_em limit 1;
  end if;
  if v_pac is not null and exists (select 1 from clientes where id = v_pac and bloqueada) then
    raise exception 'cliente_bloqueada' using errcode = '42501';
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
    insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, variacao_id, inicio, fases, origem, status)
    values (p_salao, v_pac, p_profissional, p_servico, p_variacao, p_inicio, v_fases, 'whatsapp', 'confirmado') returning id into v_ag;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;
  update conversas set cliente_id = v_pac where id = p_conversa;
  return v_ag;
end
$$;
revoke all on function agendar_whatsapp(uuid, uuid, uuid, uuid, timestamptz, text, boolean, uuid) from public, anon, authenticated;
grant execute on function agendar_whatsapp(uuid, uuid, uuid, uuid, timestamptz, text, boolean, uuid) to service_role;

-- Remarcar pelo link e pelo robô também respeita as regras de antecedência.
create or replace function remarcar_online(p_token uuid, p_inicio timestamptz, p_profissional uuid) returns text
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
  if (select count(distinct profissional_id) from do_grupo(a.id) where status in ('agendado', 'confirmado')) > 1 then return 'varios_profissionais'; end if;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = a.salao_id and ativo and papel in ('admin', 'profissional')) then return 'dados_invalidos'; end if;
  select coalesce(jsonb_agg(f order by g.inicio, ord), '[]') into v_fases
  from do_grupo(a.id) g, jsonb_array_elements(g.fases) with ordinality as e(f, ord) where g.status in ('agendado', 'confirmado');
  if not dentro_da_antecedencia(c, p_inicio) or not cabe_na_jornada(a.salao_id, p_profissional, p_inicio, v_fases) then return 'horario_indisponivel'; end if;
  v_t := p_inicio;
  begin
    delete from ocupacoes where agendamento_id in (select id from do_grupo(a.id));
    for r in select * from do_grupo(a.id) where status in ('agendado', 'confirmado') order by inicio loop
      update agendamentos set inicio = v_t, profissional_id = p_profissional where id = r.id returning fim + make_interval(mins => intervalo_min) into v_t;
    end loop;
  exception when exclusion_violation then
    return 'horario_indisponivel';
  end;
  return 'remarcado';
end
$$;

create or replace function remarcar_whatsapp(p_salao uuid, p_conversa uuid, p_agendamento uuid, p_inicio timestamptz, p_profissional uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a agendamentos;
  c saloes;
  v_fases jsonb := '[]';
  r record;
  v_t timestamptz;
begin
  if not exists (select 1 from agendamentos_whatsapp(p_salao, p_conversa) x where x.id = p_agendamento) then return 'nao_encontrado'; end if;
  select * into a from agendamentos where id = p_agendamento and salao_id = p_salao for update;
  if a.id is null or a.status not in ('agendado', 'confirmado') then return 'nao_encontrado'; end if;
  select * into c from saloes where id = p_salao;
  if (select count(distinct profissional_id) from do_grupo(a.id) where status in ('agendado', 'confirmado')) > 1 then return 'varios_profissionais'; end if;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = p_salao and ativo and papel in ('admin', 'profissional')) then return 'dados_invalidos'; end if;
  select coalesce(jsonb_agg(f order by g.inicio, ord), '[]') into v_fases
  from do_grupo(a.id) g, jsonb_array_elements(g.fases) with ordinality as e(f, ord) where g.status in ('agendado', 'confirmado');
  if not dentro_da_antecedencia(c, p_inicio) or not cabe_na_jornada(p_salao, p_profissional, p_inicio, v_fases) then return 'horario_indisponivel'; end if;
  v_t := p_inicio;
  begin
    delete from ocupacoes where agendamento_id in (select id from do_grupo(a.id));
    for r in select * from do_grupo(a.id) where status in ('agendado', 'confirmado') order by inicio loop
      update agendamentos set inicio = v_t, profissional_id = p_profissional where id = r.id returning fim + make_interval(mins => intervalo_min) into v_t;
    end loop;
  exception when exclusion_violation then
    return 'horario_indisponivel';
  end;
  return 'remarcado';
end
$$;

-- ───────────── fila de quem chega sem hora (rodízio) ─────────────
create table fila_atendimento (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid,
  nome text not null check (length(nome) between 2 and 120),
  servico_id uuid,
  profissional_preferido uuid,
  chegou_em timestamptz not null default now(),
  estado text not null default 'aguardando' check (estado in ('aguardando', 'atendendo', 'saiu')),
  agendamento_id uuid,
  criado_por uuid default auth.uid(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete set null (cliente_id),
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete set null (servico_id),
  foreign key (profissional_preferido, salao_id) references membros (user_id, salao_id) on delete set null (profissional_preferido)
);
create index on fila_atendimento (salao_id, estado, chegou_em);
alter table fila_atendimento enable row level security;
create policy fila_ler on fila_atendimento for select to authenticated using (salao_id = (select meu_salao()));
create policy fila_criar on fila_atendimento for insert to authenticated with check (salao_id = (select meu_salao()));
create policy fila_editar on fila_atendimento for update to authenticated using (salao_id = (select meu_salao())) with check (salao_id = (select meu_salao()));
revoke all on fila_atendimento from anon, authenticated;
grant select on fila_atendimento to authenticated;
grant insert (cliente_id, nome, servico_id, profissional_preferido) on fila_atendimento to authenticated;
grant update (estado, agendamento_id) on fila_atendimento to authenticated;
