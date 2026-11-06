-- Belezando · núcleo multitenant (salão de beleza)
-- Isolamento: toda tabela de negócio tem salao_id e política RLS que o compara com o salão do usuário logado.
-- Papéis: admin, profissional, recepcao.

create extension if not exists btree_gist with schema extensions;

create type papel as enum ('admin', 'profissional', 'recepcao');
create type status_agendamento as enum ('agendado', 'confirmado', 'em_atendimento', 'concluido', 'faltou', 'cancelado');
create type origem_agendamento as enum ('interno', 'whatsapp');

-- ───────────── tabelas ─────────────

create table saloes (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(nome) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 40),
  cor_marca text not null default '#0F8F7E' check (cor_marca ~ '^#[0-9A-Fa-f]{6}$'),
  telefone text,
  endereco text,
  mensagem text check (length(mensagem) <= 280),
  fuso text not null default 'America/Sao_Paulo',
  abre time not null default '08:00',
  fecha time not null default '18:00',
  dias_semana int[] not null default '{1,2,3,4,5}', -- 1 = segunda ... 7 = domingo
  criado_em timestamptz not null default now(),
  check (fecha > abre)
);

create table membros (
  user_id uuid primary key references auth.users (id) on delete cascade,
  salao_id uuid not null references saloes (id) on delete cascade,
  papel papel not null,
  nome text not null check (length(nome) between 2 and 120),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (user_id, salao_id)
);
create index on membros (salao_id);

-- Funções usadas pelas políticas. Leem a linha do próprio usuário, ignorando RLS (security definer).
create function meu_salao() returns uuid
language sql stable security definer set search_path = public as
$$ select salao_id from membros where user_id = auth.uid() and ativo $$;

create function meu_papel() returns papel
language sql stable security definer set search_path = public as
$$ select papel from membros where user_id = auth.uid() and ativo $$;

create table clientes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 120),
  telefone text check (telefone ~ '^[0-9]{10,13}$'),
  email text check (length(email) <= 200),
  nascimento date check (nascimento <= current_date),
  observacoes text check (length(observacoes) <= 2000),
  consentimento_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (id, salao_id)
);
create index on clientes (salao_id, nome);
create index on clientes (salao_id, telefone);

create table servicos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 120),
  duracao_min int not null check (duracao_min between 10 and 480),
  ativo boolean not null default true,
  unique (id, salao_id)
);
create index on servicos (salao_id);

create table agendamentos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  profissional_id uuid not null,
  servico_id uuid not null,
  inicio timestamptz not null,
  fim timestamptz not null,
  status status_agendamento not null default 'agendado',
  origem origem_agendamento not null default 'interno',
  criado_em timestamptz not null default now(),
  unique (id, salao_id),
  check (fim > inicio),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id),
  foreign key (servico_id, salao_id) references servicos (id, salao_id),
  -- um profissional não pode ter dois horários sobrepostos (cancelados e faltas liberam o horário)
  constraint sem_conflito exclude using gist (
    profissional_id with =,
    tstzrange(inicio, fim) with &&
  ) where (status not in ('cancelado', 'faltou'))
);
create index on agendamentos (salao_id, inicio);
create index on agendamentos (cliente_id);

create table log_auditoria (
  id bigint generated always as identity primary key,
  salao_id uuid not null,
  user_id uuid,
  tabela text not null,
  registro_id uuid,
  acao text not null,
  campos_alterados text[],
  em timestamptz not null default now()
);
create index on log_auditoria (salao_id, em desc);

-- ───────────── gatilhos ─────────────

-- Registra quem mexeu e em quais campos. Não copia o conteúdo para o log.
create function auditar() returns trigger
language plpgsql security definer set search_path = public as
$$
declare
  novo jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  velho jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  campos text[];
begin
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into campos
    from jsonb_object_keys(novo) k
    where novo -> k is distinct from velho -> k;
    if campos is null then return new; end if;
  end if;
  insert into log_auditoria (salao_id, user_id, tabela, registro_id, acao, campos_alterados)
  values (
    coalesce(novo ->> 'salao_id', velho ->> 'salao_id')::uuid,
    auth.uid(),
    tg_table_name,
    coalesce(novo ->> 'id', velho ->> 'id')::uuid,
    lower(tg_op),
    campos
  );
  return coalesce(new, old);
end
$$;

create trigger aud_clientes after insert or update or delete on clientes for each row execute function auditar();
create trigger aud_agendamentos after insert or update or delete on agendamentos for each row execute function auditar();

-- ───────────── RLS ─────────────

alter table saloes enable row level security;
alter table membros enable row level security;
alter table clientes enable row level security;
alter table servicos enable row level security;
alter table agendamentos enable row level security;
alter table log_auditoria enable row level security;

create policy saloes_ler on saloes for select to authenticated using (id = meu_salao());
create policy saloes_editar on saloes for update to authenticated
  using (id = meu_salao() and meu_papel() = 'admin') with check (id = meu_salao());

create policy membros_ler on membros for select to authenticated using (salao_id = meu_salao());
create policy membros_editar on membros for update to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao());

create policy clientes_ler on clientes for select to authenticated using (salao_id = meu_salao());
create policy clientes_criar on clientes for insert to authenticated with check (salao_id = meu_salao());
create policy clientes_editar on clientes for update to authenticated
  using (salao_id = meu_salao()) with check (salao_id = meu_salao());
create policy clientes_apagar on clientes for delete to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin');

create policy servicos_ler on servicos for select to authenticated using (salao_id = meu_salao());
create policy servicos_escrever on servicos for all to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin')
  with check (salao_id = meu_salao() and meu_papel() = 'admin');

create policy agenda_ler on agendamentos for select to authenticated using (salao_id = meu_salao());
create policy agenda_criar on agendamentos for insert to authenticated with check (salao_id = meu_salao());
create policy agenda_editar on agendamentos for update to authenticated
  using (salao_id = meu_salao()) with check (salao_id = meu_salao());
create policy agenda_apagar on agendamentos for delete to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin');

create policy auditoria_admin on log_auditoria for select to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin');

-- ───────────── permissões ─────────────

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select, update on saloes to authenticated;
grant select, update on membros to authenticated;
grant select, insert, update, delete on clientes, servicos, agendamentos to authenticated;
grant select on log_auditoria to authenticated;
revoke all on function meu_salao(), meu_papel() from public;
grant execute on function meu_salao(), meu_papel() to authenticated;

-- ───────────── funções chamadas pelo app ─────────────

-- Cria o salão e torna o usuário logado administrador. Cadastra serviços de partida.
create function criar_salao(p_nome text, p_slug text, p_nome_usuario text) returns uuid
language plpgsql security definer set search_path = public as
$$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'não autenticado' using errcode = '28000';
  end if;
  if exists (select 1 from membros where user_id = auth.uid()) then
    raise exception 'usuário já pertence a um salão' using errcode = '23505';
  end if;
  insert into saloes (nome, slug) values (trim(p_nome), lower(trim(p_slug))) returning id into v_id;
  insert into membros (user_id, salao_id, papel, nome) values (auth.uid(), v_id, 'admin', trim(p_nome_usuario));
  insert into servicos (salao_id, nome, duracao_min) values
    (v_id, 'Corte feminino', 60), (v_id, 'Corte masculino', 30), (v_id, 'Escova', 45),
    (v_id, 'Coloração', 120), (v_id, 'Hidratação', 45), (v_id, 'Manicure', 45), (v_id, 'Pedicure', 45);
  return v_id;
end
$$;
revoke all on function criar_salao(text, text, text) from public;
grant execute on function criar_salao(text, text, text) to authenticated;
