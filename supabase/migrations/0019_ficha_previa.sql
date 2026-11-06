-- Belezando · ficha de primeira visita por link.
-- A cliente nova responde antes de vir (tipo de cabelo, química recente, alergias, gestação, medicamentos, objetivo).
-- O link vale 7 dias; o banco guarda só o hash do segredo. As respostas vão para a ficha da cliente.

create table fichas_previas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  token_hash text not null unique,
  expira_em timestamptz not null default now() + interval '7 days',
  respondida_em timestamptz,
  respostas jsonb,
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on fichas_previas (cliente_id, criado_em desc);
alter table fichas_previas enable row level security;
create policy fprev_ler on fichas_previas for select to authenticated using (salao_id = meu_salao());
revoke all on fichas_previas from anon, authenticated;
grant select (id, salao_id, cliente_id, expira_em, respondida_em, respostas, criado_em) on fichas_previas to authenticated;

-- Cria o link (um segredo aleatório; só o hash fica no banco). Link antigo ainda não respondido deixa de valer.
create function criar_link_ficha_interno(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  select salao_id into v_salao from clientes where id = p_cliente;
  if v_salao is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update fichas_previas set expira_em = least(expira_em, now()) where cliente_id = p_cliente and respondida_em is null;
  insert into fichas_previas (salao_id, cliente_id, token_hash) values (v_salao, p_cliente, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'));
  return v_token;
end
$$;
revoke all on function criar_link_ficha_interno(uuid) from public, anon, authenticated;

-- Pela equipe (cliente do próprio salão).
create function criar_link_ficha(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if not exists (select 1 from clientes where id = p_cliente and salao_id = meu_salao()) then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  return criar_link_ficha_interno(p_cliente);
end
$$;
revoke all on function criar_link_ficha(uuid) from public, anon;
grant execute on function criar_link_ficha(uuid) to authenticated;

-- Pelo link público, logo depois de a cliente nova marcar (só se ela ainda não respondeu nenhuma ficha).
create function criar_link_ficha_online(p_agendamento uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_cli uuid;
begin
  select cliente_id into v_cli from agendamentos where id = p_agendamento;
  if v_cli is null or exists (select 1 from fichas_previas where cliente_id = v_cli and respondida_em is not null) then return null; end if;
  return criar_link_ficha_interno(v_cli);
end
$$;

create function ficha_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'slug', s.slug, 'cliente', split_part(c.nome, ' ', 1), 'respondida', f.respondida_em is not null,
    'expirada', f.expira_em < now() and f.respondida_em is null)
  from fichas_previas f join clientes c on c.id = f.cliente_id join saloes s on s.id = f.salao_id
  where f.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;

-- Grava as respostas e leva o que interessa para a ficha da cliente (sem apagar o que a equipe já anotou).
create function responder_ficha(p_token text, p_respostas jsonb) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  f fichas_previas;
  r jsonb := p_respostas;
  v_resumo text;
begin
  select * into f from fichas_previas where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if f.id is null then return 'nao_encontrado'; end if;
  if f.respondida_em is not null then return 'ja_respondida'; end if;
  if f.expira_em < now() then return 'expirada'; end if;
  if jsonb_typeof(r) <> 'object' or length(r::text) > 4000 then return 'invalida'; end if;
  update fichas_previas set respostas = r, respondida_em = now() where id = f.id;
  v_resumo := concat_ws(' · ',
    'Ficha de primeira visita (' || to_char(now(), 'DD/MM/YYYY') || ')',
    nullif('química recente: ' || coalesce(r ->> 'quimica', ''), 'química recente: '),
    nullif('quando: ' || coalesce(r ->> 'quimica_quando', ''), 'quando: '),
    case r ->> 'reacao_tintura' when 'sim' then 'já teve reação a tintura' end,
    case r ->> 'couro_sensivel' when 'sim' then 'couro cabeludo sensível' end,
    case r ->> 'gestante' when 'sim' then 'gestante ou amamentando' end,
    nullif('medicamento: ' || coalesce(r ->> 'medicamento', ''), 'medicamento: '),
    nullif('quer: ' || coalesce(r ->> 'objetivo', ''), 'quer: '));
  update clientes c set
    tipo_cabelo = coalesce(case when r ->> 'tipo_cabelo' in ('liso', 'ondulado', 'cacheado', 'crespo') then r ->> 'tipo_cabelo' end, c.tipo_cabelo),
    alergias = left(nullif(concat_ws('; ', c.alergias, nullif(trim(r ->> 'alergias'), '')), ''), 500),
    origem = coalesce(c.origem, case when r ->> 'origem' in ('indicacao', 'instagram', 'google', 'whatsapp', 'passante', 'facebook', 'tiktok', 'outro') then r ->> 'origem' end),
    nascimento = coalesce(c.nascimento, case when (r ->> 'nascimento') ~ '^\d{4}-\d{2}-\d{2}$' and (r ->> 'nascimento')::date between date '1900-01-01' and current_date then (r ->> 'nascimento')::date end),
    observacoes = left(concat_ws(E'\n', c.observacoes, v_resumo), 2000)
  where c.id = f.cliente_id;
  return 'respondida';
end
$$;

revoke all on function criar_link_ficha_online(uuid), ficha_publica(text), responder_ficha(text, jsonb) from public, anon, authenticated;
grant execute on function criar_link_ficha_online(uuid), ficha_publica(text), responder_ficha(text, jsonb) to service_role;
