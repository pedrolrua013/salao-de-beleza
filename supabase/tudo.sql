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
-- Belezando · WhatsApp: conversas espelhadas, robô de agendamento e cancelamento.
-- O robô roda no servidor com a chave de serviço (service_role). Nenhuma função daqui é aberta ao público.
-- Mensagens de clientes podem conter dado de saúde: só membros da próprio salão leem, e ninguém escreve pelo app.

-- Telefone no formato nacional (DDD + número): tira o 55 e acrescenta o 9 que o WhatsApp às vezes omite em celulares antigos.
create function tel_nacional(p text) returns text
language sql immutable as
$$
  select case
    when n ~ '^[0-9]{2}[6-9][0-9]{7}$' then substr(n, 1, 2) || '9' || substr(n, 3)
    else n
  end
  from (
    select case when d ~ '^55[0-9]{10,11}$' then substr(d, 3) else d end as n
    from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) a
  ) b
$$;

create table whatsapp_contas (
  salao_id uuid primary key references saloes (id) on delete cascade,
  phone_number_id text not null unique check (phone_number_id ~ '^[0-9]{5,30}$'),
  waba_id text,
  token text not null check (length(token) >= 20),   -- só service_role lê. Em produção, guarde no Supabase Vault.
  criado_em timestamptz not null default now()
);

create table conversas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  wa_id text not null check (wa_id ~ '^[0-9]{10,15}$'),   -- como a Meta identifica o contato (usado para responder)
  telefone text not null,                                  -- formato nacional, para casar com o cadastro do cliente
  nome_contato text check (length(nome_contato) <= 120),
  cliente_id uuid,
  estado jsonb not null default '{}'::jsonb,               -- passo atual do robô
  bot_ativo boolean not null default true,
  nao_lidas int not null default 0 check (nao_lidas >= 0),
  ultima_msg_em timestamptz not null default now(),
  ultima_entrada_em timestamptz,                           -- última mensagem do cliente (janela de 24 h da Meta)
  criado_em timestamptz not null default now(),
  unique (id, salao_id),
  unique (salao_id, wa_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete set null (cliente_id)
);
create index on conversas (salao_id, ultima_msg_em desc);

create table mensagens (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null,
  conversa_id uuid not null,
  direcao text not null check (direcao in ('entrada', 'saida')),
  autor text not null check (autor in ('cliente', 'robo', 'equipe')),
  tipo text not null default 'texto',
  corpo text not null check (length(corpo) <= 4096),
  wa_msg_id text,
  erro text check (length(erro) <= 500),
  criado_em timestamptz not null default now(),
  unique (salao_id, wa_msg_id),                          -- a Meta reenvia webhooks: isto garante processar uma vez só
  foreign key (conversa_id, salao_id) references conversas (id, salao_id) on delete cascade
);
create index on mensagens (conversa_id, criado_em);

alter table whatsapp_contas enable row level security;   -- sem política: só service_role acessa
alter table conversas enable row level security;
alter table mensagens enable row level security;

create policy conversas_ler on conversas for select to authenticated using (salao_id = meu_salao());
create policy conversas_editar on conversas for update to authenticated
  using (salao_id = meu_salao()) with check (salao_id = meu_salao());
create policy mensagens_ler on mensagens for select to authenticated using (salao_id = meu_salao());

revoke all on whatsapp_contas, conversas, mensagens from anon, authenticated;
grant select on conversas, mensagens to authenticated;
grant update (bot_ativo, nao_lidas) on conversas to authenticated;

-- ───────────── funções do robô (só service_role) ─────────────

-- Registra a mensagem recebida. Cria a conversa se for nova e liga ao cliente pelo telefone.
create function receber_mensagem(
  p_salao uuid, p_wa_id text, p_nome text, p_wa_msg_id text, p_tipo text, p_corpo text
) returns jsonb
language plpgsql security definer set search_path = public as
$$
declare
  v_tel text := tel_nacional(p_wa_id);
  v_conv conversas;
  v_pac clientes;
  v_nova boolean;
begin
  select * into v_conv from conversas where salao_id = p_salao and wa_id = p_wa_id;
  if not found then
    select * into v_pac from clientes where salao_id = p_salao and tel_nacional(telefone) = v_tel order by criado_em limit 1;
    insert into conversas (salao_id, wa_id, telefone, nome_contato, cliente_id)
    values (p_salao, p_wa_id, v_tel, left(nullif(trim(p_nome), ''), 120), v_pac.id)
    returning * into v_conv;
  end if;

  insert into mensagens (salao_id, conversa_id, direcao, autor, tipo, corpo, wa_msg_id)
  values (p_salao, v_conv.id, 'entrada', 'cliente', p_tipo, left(p_corpo, 4096), p_wa_msg_id)
  on conflict (salao_id, wa_msg_id) do nothing;
  v_nova := found;

  if v_nova then
    update conversas set nao_lidas = nao_lidas + 1, ultima_msg_em = now(), ultima_entrada_em = now(),
      nome_contato = coalesce(nome_contato, left(nullif(trim(p_nome), ''), 120))
    where id = v_conv.id returning * into v_conv;
  end if;

  return jsonb_build_object(
    'conversa_id', v_conv.id, 'nova', v_nova, 'bot_ativo', v_conv.bot_ativo, 'estado', v_conv.estado,
    'telefone', v_conv.telefone, 'nome_contato', v_conv.nome_contato,
    'cliente_nome', (select nome from clientes where id = v_conv.cliente_id),
    'consentiu', coalesce((select consentimento_em is not null from clientes where id = v_conv.cliente_id), false)
  );
end
$$;

create function agendar_whatsapp(
  p_salao uuid, p_conversa uuid, p_servico uuid, p_profissional uuid, p_inicio timestamptz,
  p_nome text, p_consentiu boolean
) returns uuid
language plpgsql security definer set search_path = public as
$$
declare
  c saloes;
  v_conv conversas;
  v_srv servicos;
  v_fim timestamptz;
  v_ini_local timestamp;
  v_fim_local timestamp;
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

  v_fim := p_inicio + make_interval(mins => v_srv.duracao_min);
  v_ini_local := p_inicio at time zone c.fuso;
  v_fim_local := v_fim at time zone c.fuso;
  if p_inicio < now() + interval '1 hour'
     or v_ini_local::date <> v_fim_local::date
     or not (extract(isodow from v_ini_local)::int = any (c.dias_semana))
     or v_ini_local::time < c.abre or v_fim_local::time > c.fecha then
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
    insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fim, origem, status)
    values (p_salao, v_pac, p_profissional, p_servico, p_inicio, v_fim, 'whatsapp', 'confirmado') returning id into v_ag;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;
  update conversas set cliente_id = v_pac where id = p_conversa;
  return v_ag;
end
$$;

-- Próximos agendamentos do cliente desta conversa.
create function agendamentos_whatsapp(p_salao uuid, p_conversa uuid)
returns table (id uuid, inicio timestamptz, servico text, profissional text)
language sql stable security definer set search_path = public as
$$
  select a.id, a.inicio, s.nome, m.nome
  from conversas v
  join clientes p on p.salao_id = v.salao_id
    and (p.id = v.cliente_id or tel_nacional(p.telefone) = v.telefone)
  join agendamentos a on a.cliente_id = p.id and a.salao_id = v.salao_id
  join servicos s on s.id = a.servico_id
  join membros m on m.user_id = a.profissional_id
  where v.id = p_conversa and v.salao_id = p_salao
    and a.status in ('agendado', 'confirmado') and a.inicio > now()
  order by a.inicio
  limit 10
$$;

create function cancelar_whatsapp(p_salao uuid, p_conversa uuid, p_agendamento uuid) returns boolean
language plpgsql security definer set search_path = public as
$$
declare n int;
begin
  update agendamentos set status = 'cancelado'
  where id = p_agendamento and salao_id = p_salao and status in ('agendado', 'confirmado') and inicio > now()
    and id in (select x.id from agendamentos_whatsapp(p_salao, p_conversa) x);
  get diagnostics n = row_count;
  return n > 0;
end
$$;

revoke all on function tel_nacional(text) from public;
grant execute on function tel_nacional(text) to authenticated, service_role;
revoke all on function
  receber_mensagem(uuid, text, text, text, text, text),
  agendar_whatsapp(uuid, uuid, uuid, uuid, timestamptz, text, boolean),
  agendamentos_whatsapp(uuid, uuid),
  cancelar_whatsapp(uuid, uuid, uuid)
from public, anon, authenticated;
grant execute on function
  receber_mensagem(uuid, text, text, text, text, text),
  agendar_whatsapp(uuid, uuid, uuid, uuid, timestamptz, text, boolean),
  agendamentos_whatsapp(uuid, uuid),
  cancelar_whatsapp(uuid, uuid, uuid)
to service_role;
-- Belezando · lembretes e confirmação de horário pelo WhatsApp.
-- Regras: só quem tem telefone, aceite e não pediu para parar recebe. Só horários "agendado" (não confirmadas) geram lembrete.
-- O envio roda no servidor (service_role). Nada aqui é aberto ao público.

alter table saloes
  add column lembretes_ativos boolean not null default true,
  add column lembrete_hora time not null default '10:00';
alter table clientes add column recusou_lembretes_em timestamptz;

create table lembretes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  agendamento_id uuid not null,
  tipo text not null check (tipo in ('confirmacao', 'vespera', 'mesmo_dia')),
  inicio_ref timestamptz not null,                 -- início do horário quando o lembrete foi programado
  enviar_em timestamptz not null,
  estado text not null default 'pendente' check (estado in ('pendente', 'enviando', 'enviado', 'respondido', 'falhou', 'cancelado', 'ignorado')),
  tentativas int not null default 0,
  reservado_em timestamptz,
  wa_msg_id text,
  resposta text check (resposta in ('confirmou', 'remarcar', 'cancelou')),
  erro text check (length(erro) <= 500),
  enviado_em timestamptz,
  respondido_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (agendamento_id, tipo, inicio_ref),      -- um lembrete de cada tipo por horário: impede envio duplicado
  foreign key (agendamento_id, salao_id) references agendamentos (id, salao_id) on delete cascade
);
create index on lembretes (enviar_em) where estado in ('pendente', 'enviando');
create index on lembretes (agendamento_id);
alter table lembretes enable row level security;
create policy lembretes_ler on lembretes for select to authenticated using (salao_id = meu_salao());
revoke all on lembretes from anon, authenticated;
grant select on lembretes to authenticated;

-- ───────────── programação ─────────────

-- Recalcula os lembretes de um horário. Roda sozinho quando o horário, o cliente ou o salão mudam.
create function programar_lembretes(p_ag uuid) returns void
language plpgsql security definer set search_path = public as
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

create function trg_lembretes_agendamento() returns trigger
language plpgsql security definer set search_path = public as
$$ begin perform programar_lembretes(new.id); return new; end $$;
create trigger lem_agendamento after insert or update of inicio, status, cliente_id on agendamentos
  for each row execute function trg_lembretes_agendamento();

create function trg_lembretes_cliente() returns trigger
language plpgsql security definer set search_path = public as
$$
declare r record;
begin
  for r in select id from agendamentos where cliente_id = new.id and status = 'agendado' and inicio > now() loop
    perform programar_lembretes(r.id);
  end loop;
  return new;
end $$;
create trigger lem_cliente after update of telefone, consentimento_em, recusou_lembretes_em on clientes
  for each row execute function trg_lembretes_cliente();

create function trg_lembretes_salao() returns trigger
language plpgsql security definer set search_path = public as
$$
declare r record;
begin
  for r in select id from agendamentos where salao_id = new.id and status = 'agendado' and inicio > now() loop
    perform programar_lembretes(r.id);
  end loop;
  return new;
end $$;
create trigger lem_salao after update of lembretes_ativos, lembrete_hora on saloes
  for each row execute function trg_lembretes_salao();

-- ───────────── envio (chamado pelo servidor) ─────────────

-- Reserva os lembretes que já estão na hora. "for update skip locked" garante que duas execuções ao mesmo tempo nunca peguem o mesmo.
create function reservar_lembretes(p_limite int default 20)
returns table (
  id uuid, salao_id uuid, agendamento_id uuid, tipo text, wa_id text, cliente_nome text, salao_nome text,
  inicio timestamptz, fuso text, profissional text, servico text
)
language plpgsql security definer set search_path = public as
$$
#variable_conflict use_column
begin
  -- envio que travou volta para a fila
  update lembretes l set estado = 'pendente', tentativas = l.tentativas + 1
  where l.estado = 'enviando' and l.reservado_em < now() - interval '15 minutes';

  -- horário mudou, foi confirmado ou está perto demais: não envia
  update lembretes l set estado = 'cancelado'
  where l.estado = 'pendente' and l.enviar_em <= now()
    and not exists (select 1 from agendamentos a where a.id = l.agendamento_id and a.status = 'agendado'
                    and a.inicio = l.inicio_ref and a.inicio > now() + interval '30 minutes');

  -- o servidor ficou fora do ar: lembrete velho demais deixa de servir
  update lembretes l set estado = 'ignorado', erro = 'passou da hora de enviar'
  where l.estado = 'pendente'
    and l.enviar_em < now() - case when l.tipo = 'mesmo_dia' then interval '1 hour' else interval '6 hours' end;

  -- já houve resposta, ou outro lembrete saiu há pouco: não insiste
  update lembretes l set estado = 'ignorado', erro = 'já respondeu ou recebeu aviso há pouco'
  where l.estado = 'pendente' and l.enviar_em <= now() and l.tipo = 'mesmo_dia'
    and exists (select 1 from lembretes o where o.agendamento_id = l.agendamento_id and o.id <> l.id
                and o.inicio_ref = l.inicio_ref and (o.resposta is not null or o.enviado_em > now() - interval '6 hours'));

  return query
  with alvo as (
    select l.id from lembretes l
    where l.estado = 'pendente' and l.enviar_em <= now() and l.tentativas < 3
    order by l.enviar_em limit p_limite for update skip locked
  ), marcado as (
    update lembretes l set estado = 'enviando', reservado_em = now() from alvo where l.id = alvo.id returning l.*
  )
  select m.id, m.salao_id, m.agendamento_id, m.tipo,
         coalesce((select cv.wa_id from conversas cv where cv.salao_id = m.salao_id and cv.cliente_id = p.id order by cv.ultima_msg_em desc limit 1),
                  '55' || tel_nacional(p.telefone)),
         p.nome, c.nome, a.inicio, c.fuso, mem.nome, s.nome
  from marcado m
  join agendamentos a on a.id = m.agendamento_id
  join clientes p on p.id = a.cliente_id
  join saloes c on c.id = m.salao_id
  join membros mem on mem.user_id = a.profissional_id
  join servicos s on s.id = a.servico_id;
end
$$;

-- Registra o resultado do envio. Falha temporária tenta de novo (até 3 vezes, com espera); definitiva encerra.
create function concluir_lembrete(p_id uuid, p_ok boolean, p_wa_msg_id text, p_erro text, p_definitivo boolean default false)
returns void
language plpgsql security definer set search_path = public as
$$
begin
  if p_ok then
    update lembretes set estado = 'enviado', wa_msg_id = p_wa_msg_id, enviado_em = now(), reservado_em = null,
      tentativas = tentativas + 1, erro = null where id = p_id and estado = 'enviando';
  else
    update lembretes set tentativas = tentativas + 1, reservado_em = null, erro = left(p_erro, 500),
      estado = case when p_definitivo or tentativas + 1 >= 3 then 'falhou' else 'pendente' end,
      enviar_em = case when p_definitivo or tentativas + 1 >= 3 then enviar_em else now() + make_interval(mins => 10 * (tentativas + 1)) end
    where id = p_id and estado = 'enviando';
  end if;
end
$$;

-- ───────────── respostas do cliente ─────────────

-- O cliente tocou num botão do lembrete. Confere que o telefone é o do cliente do horário.
create function responder_lembrete(p_salao uuid, p_wa_id text, p_lembrete uuid, p_resposta text) returns jsonb
language plpgsql security definer set search_path = public as
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

  if p_resposta = 'confirmou' and a.status = 'agendado' then
    update agendamentos set status = 'confirmado' where id = a.id;
  elsif p_resposta = 'cancelou' then
    update agendamentos set status = 'cancelado' where id = a.id;
  end if;
  update lembretes set estado = 'respondido', resposta = p_resposta, respondido_em = now() where id = l.id;
  select status into v_novo from agendamentos where id = a.id;
  return jsonb_build_object('ok', true, 'acao', p_resposta, 'agendamento_id', a.id, 'inicio', a.inicio, 'status', v_novo,
    'servico_id', a.servico_id, 'profissional_id', a.profissional_id);
end
$$;

-- Último lembrete enviado nas últimas 24 h para este telefone (para entender um "confirmo" digitado).
create function lembrete_aberto(p_salao uuid, p_wa_id text) returns uuid
language sql stable security definer set search_path = public as
$$
  select l.id from lembretes l
  join agendamentos a on a.id = l.agendamento_id
  join clientes p on p.id = a.cliente_id
  where l.salao_id = p_salao and l.estado = 'enviado' and l.enviado_em > now() - interval '24 hours'
    and a.status = 'agendado' and a.inicio > now()
    and tel_nacional(p.telefone) = tel_nacional(p_wa_id)
  order by l.enviado_em desc limit 1
$$;

-- "PARAR": o cliente não recebe mais lembretes automáticos.
create function recusar_lembretes(p_salao uuid, p_wa_id text) returns boolean
language plpgsql security definer set search_path = public as
$$
declare n int;
begin
  update clientes set recusou_lembretes_em = now()
  where salao_id = p_salao and tel_nacional(telefone) = tel_nacional(p_wa_id) and recusou_lembretes_em is null;
  get diagnostics n = row_count;
  return n > 0;
end
$$;

-- Garante uma conversa para o cliente (o lembrete aparece no histórico mesmo antes de ele responder).
create function abrir_conversa(p_salao uuid, p_wa_id text, p_nome text) returns uuid
language plpgsql security definer set search_path = public as
$$
declare v_id uuid; v_pac uuid;
begin
  select id into v_id from conversas where salao_id = p_salao and wa_id = p_wa_id;
  if v_id is not null then return v_id; end if;
  select id into v_pac from clientes where salao_id = p_salao and tel_nacional(telefone) = tel_nacional(p_wa_id) order by criado_em limit 1;
  insert into conversas (salao_id, wa_id, telefone, nome_contato, cliente_id)
  values (p_salao, p_wa_id, tel_nacional(p_wa_id), left(nullif(trim(p_nome), ''), 120), v_pac)
  on conflict (salao_id, wa_id) do update set salao_id = excluded.salao_id
  returning id into v_id;
  return v_id;
end
$$;

revoke all on function
  programar_lembretes(uuid), trg_lembretes_agendamento(), trg_lembretes_cliente(), trg_lembretes_salao(),
  reservar_lembretes(int), concluir_lembrete(uuid, boolean, text, text, boolean),
  responder_lembrete(uuid, text, uuid, text), lembrete_aberto(uuid, text), recusar_lembretes(uuid, text), abrir_conversa(uuid, text, text)
from public, anon, authenticated;
grant execute on function
  reservar_lembretes(int), concluir_lembrete(uuid, boolean, text, text, boolean),
  responder_lembrete(uuid, text, uuid, text), lembrete_aberto(uuid, text), recusar_lembretes(uuid, text), abrir_conversa(uuid, text, text)
to service_role;
-- Belezando · endurecimento de segurança (revisão de segurança de 24/10/2026).

-- 1) Permissões por coluna: o app nunca precisa mexer em consentimento, opt-out, identificador ou fuso.
--    Com o grant da tabela inteira, qualquer membro conseguia alterar esses campos direto pela API.
revoke insert, update on clientes from authenticated;
grant insert (nome, telefone, email, nascimento, observacoes) on clientes to authenticated;
grant update (nome, telefone, email, nascimento, observacoes) on clientes to authenticated;

revoke update on membros from authenticated;
grant update (nome, papel, ativo) on membros to authenticated;

revoke update on saloes from authenticated;
grant update (nome, telefone, endereco, mensagem, abre, fecha, dias_semana, lembretes_ativos, lembrete_hora) on saloes to authenticated;

-- 2) O aceite de contato por WhatsApp só entra por esta função (fica na auditoria, com quem registrou).
--    Não existe função para apagar o PARAR do cliente: quem pediu para parar só volta se o próprio cliente pedir.
create function registrar_aceite_contato(p_cliente uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare n int;
begin
  if auth.uid() is null or meu_salao() is null then return false; end if;
  update clientes set consentimento_em = coalesce(consentimento_em, now())
  where id = p_cliente and salao_id = meu_salao() and consentimento_em is null;
  get diagnostics n = row_count;
  return n > 0;
end
$$;
revoke all on function registrar_aceite_contato(uuid) from public, anon;
grant execute on function registrar_aceite_contato(uuid) to authenticated;

-- 3) Teto de horários futuros por cliente nas marcações feitas pelo robô (impede encher a agenda por WhatsApp).
create function limitar_agendamentos_whatsapp() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if new.origem = 'whatsapp' and new.status in ('agendado', 'confirmado') and
     (select count(*) from agendamentos a
      where a.cliente_id = new.cliente_id and a.status in ('agendado', 'confirmado') and a.inicio > now()) >= 3 then
    raise exception 'limite_agendamentos' using errcode = '22023';
  end if;
  return new;
end
$$;
create trigger lim_agendamentos_whatsapp before insert on agendamentos for each row execute function limitar_agendamentos_whatsapp();

-- 4) Mensagem recebida nunca se perde: só é dada como tratada depois de processada (a Meta reenvia se o servidor responder erro).
alter table mensagens add column processada_em timestamptz;
alter table mensagens add column tentativas smallint not null default 0;
update mensagens set processada_em = criado_em;

drop function receber_mensagem(uuid, text, text, text, text, text);
create function receber_mensagem(
  p_salao uuid, p_wa_id text, p_nome text, p_wa_msg_id text, p_tipo text, p_corpo text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_tel text := tel_nacional(p_wa_id);
  v_conv conversas;
  v_pac clientes;
  v_msg uuid;
  v_nova boolean;
  v_repetida boolean := false;
  v_recebidas int;
begin
  select * into v_conv from conversas where salao_id = p_salao and wa_id = p_wa_id;
  if not found then
    select * into v_pac from clientes where salao_id = p_salao and tel_nacional(telefone) = v_tel order by criado_em limit 1;
    insert into conversas (salao_id, wa_id, telefone, nome_contato, cliente_id)
    values (p_salao, p_wa_id, v_tel, left(nullif(trim(p_nome), ''), 120), v_pac.id)
    on conflict (salao_id, wa_id) do nothing
    returning * into v_conv;
    if v_conv.id is null then   -- duas primeiras mensagens ao mesmo tempo: a outra chegou antes
      select * into v_conv from conversas where salao_id = p_salao and wa_id = p_wa_id;
    end if;
  end if;

  insert into mensagens (salao_id, conversa_id, direcao, autor, tipo, corpo, wa_msg_id)
  values (p_salao, v_conv.id, 'entrada', 'cliente', p_tipo, left(p_corpo, 4096), p_wa_msg_id)
  on conflict (salao_id, wa_msg_id) do nothing
  returning id into v_msg;
  v_nova := v_msg is not null;

  if v_nova then
    update conversas set nao_lidas = nao_lidas + 1, ultima_msg_em = now(), ultima_entrada_em = now(),
      nome_contato = coalesce(nome_contato, left(nullif(trim(p_nome), ''), 120))
    where id = v_conv.id returning * into v_conv;
  else
    -- reenvio de uma mensagem que o servidor não conseguiu tratar: tenta de novo, no máximo 3 vezes
    update mensagens set tentativas = tentativas + 1
    where salao_id = p_salao and wa_msg_id = p_wa_msg_id and direcao = 'entrada' and processada_em is null and tentativas < 3;
    v_repetida := found;
  end if;

  select count(*) into v_recebidas from mensagens
  where conversa_id = v_conv.id and direcao = 'entrada' and criado_em > now() - interval '10 minutes';

  return jsonb_build_object(
    'conversa_id', v_conv.id, 'nova', v_nova or v_repetida, 'bot_ativo', v_conv.bot_ativo, 'estado', v_conv.estado,
    'telefone', v_conv.telefone, 'nome_contato', v_conv.nome_contato,
    'limitado', v_recebidas > 30,      -- mais de 30 mensagens em 10 minutos: não responde (evita custo e abuso)
    'cliente_nome', (select nome from clientes where id = v_conv.cliente_id),
    'consentiu', coalesce((select consentimento_em is not null from clientes where id = v_conv.cliente_id), false)
  );
end
$$;
revoke all on function receber_mensagem(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function receber_mensagem(uuid, text, text, text, text, text) to service_role;

-- 5) Funções: nada executável por anônimo, e search_path sem pg_temp nas funções SECURITY DEFINER.
revoke execute on all functions in schema public from anon;
alter default privileges in schema public revoke execute on functions from anon, public;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef loop
    execute format('alter function %s set search_path = public, pg_temp', f.assinatura);
  end loop;
end $$;
-- Belezando · ajustes apontados pelos avisos de segurança e desempenho do Supabase (24/10/2026).

-- 1) Funções de gatilho não são chamadas pela API: ninguém, além do dono, precisa executá-las.
revoke execute on function auditar(), limitar_agendamentos_whatsapp()
  from public, anon, authenticated;
revoke execute on function trg_lembretes_agendamento(), trg_lembretes_cliente(), trg_lembretes_salao()
  from public, anon, authenticated;

-- 2) search_path fixo nas funções que ainda não tinham.
alter function tel_nacional(text) set search_path = public, pg_temp;

-- 3) Índices nas chaves estrangeiras compostas (acelera exclusões em cascata e junções).
create index on agendamentos (cliente_id, salao_id);
create index on agendamentos (profissional_id, salao_id);
create index on agendamentos (servico_id, salao_id);
create index on conversas (cliente_id, salao_id);
create index on lembretes (salao_id);
create index on lembretes (agendamento_id, salao_id);
create index on mensagens (conversa_id, salao_id);
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
-- Belezando · comanda e caixa.
-- Valores em centavos (int). A comanda junta serviços, produtos e gorjetas de uma cliente; só fecha com o caixa aberto
-- e com os pagamentos somando exatamente o total. Gorjeta não é receita do salão nem entra em comissão.

alter table servicos add column preco_centavos int not null default 0 check (preco_centavos between 0 and 10000000);

create table produtos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 120),
  preco_centavos int not null default 0 check (preco_centavos between 0 and 10000000),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (id, salao_id)
);
create index on produtos (salao_id, nome);

create type status_comanda as enum ('aberta', 'fechada', 'cancelada');
create type tipo_item as enum ('servico', 'produto', 'gorjeta');
create type forma_pagamento as enum ('dinheiro', 'pix', 'debito', 'credito', 'pacote', 'outro');

create table caixas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  aberto_por uuid default auth.uid(),
  aberto_em timestamptz not null default now(),
  troco_inicial_centavos int not null default 0 check (troco_inicial_centavos between 0 and 10000000),
  fechado_por uuid,
  fechado_em timestamptz,
  contado jsonb,          -- {"dinheiro": 12345, "pix": ...} informado no fechamento
  esperado jsonb,         -- o que o sistema calculou no fechamento
  observacao text check (length(observacao) <= 500),
  unique (id, salao_id)
);
-- um caixa aberto por salão
create unique index caixa_aberto_unico on caixas (salao_id) where fechado_em is null;

create table caixa_movimentos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  caixa_id uuid not null,
  tipo text not null check (tipo in ('sangria', 'suprimento')),
  valor_centavos int not null check (valor_centavos between 1 and 10000000),
  motivo text check (length(motivo) <= 200),
  feito_por uuid default auth.uid(),
  em timestamptz not null default now(),
  foreign key (caixa_id, salao_id) references caixas (id, salao_id)
);
create index on caixa_movimentos (caixa_id);

create table comandas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  numero bigint generated always as identity,
  cliente_id uuid,
  status status_comanda not null default 'aberta',
  desconto_centavos int not null default 0 check (desconto_centavos between 0 and 10000000),
  caixa_id uuid,
  aberta_por uuid default auth.uid(),
  aberta_em timestamptz not null default now(),
  fechada_por uuid,
  fechada_em timestamptz,
  observacao text check (length(observacao) <= 500),
  unique (id, salao_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id),
  foreign key (caixa_id, salao_id) references caixas (id, salao_id),
  check ((status = 'fechada') = (fechada_em is not null and caixa_id is not null) or status = 'cancelada')
);
create index on comandas (salao_id, status, aberta_em desc);
create index on comandas (cliente_id);
create index on comandas (caixa_id);

create table comanda_itens (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  comanda_id uuid not null,
  tipo tipo_item not null,
  servico_id uuid,
  produto_id uuid,
  agendamento_id uuid,
  descricao text not null check (length(descricao) between 1 and 160),
  profissional_id uuid,            -- quem fez o serviço, recebe a gorjeta ou vendeu o produto
  assistente_id uuid,              -- quem ajudou (lavou, aplicou): divide a comissão
  quantidade int not null default 1 check (quantidade between 1 and 999),
  preco_centavos int not null check (preco_centavos between 0 and 10000000),   -- unitário
  desconto_centavos int not null default 0 check (desconto_centavos >= 0),
  criado_em timestamptz not null default now(),
  check (desconto_centavos <= preco_centavos * quantidade),
  check (tipo <> 'servico' or (servico_id is not null and profissional_id is not null)),
  check (tipo <> 'produto' or produto_id is not null),
  check (tipo <> 'gorjeta' or (profissional_id is not null and desconto_centavos = 0 and quantidade = 1)),
  check (assistente_id is null or (tipo = 'servico' and assistente_id <> profissional_id)),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade,
  foreign key (servico_id, salao_id) references servicos (id, salao_id),
  foreign key (produto_id, salao_id) references produtos (id, salao_id),
  foreign key (agendamento_id, salao_id) references agendamentos (id, salao_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id),
  foreign key (assistente_id, salao_id) references membros (user_id, salao_id)
);
create index on comanda_itens (comanda_id);
create index on comanda_itens (agendamento_id);
create index on comanda_itens (profissional_id, salao_id);

create table comanda_pagamentos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  comanda_id uuid not null,
  forma forma_pagamento not null,
  valor_centavos int not null check (valor_centavos between 1 and 10000000),
  parcelas int not null default 1 check (parcelas between 1 and 24),
  criado_em timestamptz not null default now(),
  check (parcelas = 1 or forma = 'credito'),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade
);
create index on comanda_pagamentos (comanda_id);

-- ───────────── totais ─────────────

-- Total que a cliente paga (serviços + produtos + gorjetas − descontos) e a receita do salão (sem gorjeta).
create function total_comanda(p_comanda uuid) returns table (total int, receita int, gorjetas int, pago int)
language sql stable set search_path = public, pg_temp as
$$
  select
    (coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos), 0) - c.desconto_centavos)::int,
    (coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo <> 'gorjeta'), 0) - c.desconto_centavos)::int,
    coalesce(sum(i.preco_centavos) filter (where i.tipo = 'gorjeta'), 0)::int,
    (select coalesce(sum(valor_centavos), 0)::int from comanda_pagamentos p where p.comanda_id = c.id)
  from comandas c left join comanda_itens i on i.comanda_id = c.id
  where c.id = p_comanda
  group by c.id, c.desconto_centavos
$$;

-- ───────────── travas ─────────────

-- Itens e pagamentos só mudam com a comanda aberta.
create function trava_comanda_aberta() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
declare
  v_id uuid := coalesce(new.comanda_id, old.comanda_id);
begin
  if (select status from comandas where id = v_id) <> 'aberta' then
    raise exception 'comanda_fechada' using errcode = '55000';
  end if;
  return coalesce(new, old);
end
$$;
create trigger trava_itens before insert or update or delete on comanda_itens for each row execute function trava_comanda_aberta();
create trigger trava_pagamentos before insert or update or delete on comanda_pagamentos for each row execute function trava_comanda_aberta();

-- Comanda fechada ou cancelada não volta pela API (só pela função reabrir_comanda, do administrador).
create function trava_comanda() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if old.status <> 'aberta' and current_setting('belezando.reabrindo', true) is distinct from 'sim' then
    raise exception 'comanda_fechada' using errcode = '55000';
  end if;
  if new.status = 'fechada' and old.status = 'aberta' and current_setting('belezando.fechando', true) is distinct from 'sim' then
    raise exception 'use fechar_comanda' using errcode = '42501';
  end if;
  if new.status = 'cancelada' and old.status = 'aberta' and auth.uid() is not null and meu_papel() <> 'admin'
     and exists (select 1 from comanda_pagamentos where comanda_id = old.id) then
    raise exception 'só o administrador cancela comanda com pagamento' using errcode = '42501';
  end if;
  return new;
end
$$;
create trigger trava_comanda before update on comandas for each row execute function trava_comanda();

create function trava_caixa() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if old.fechado_em is not null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  return new;
end
$$;
create trigger trava_caixa before update on caixas for each row execute function trava_caixa();

create function trava_movimento() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if (select fechado_em from caixas where id = new.caixa_id) is not null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  return new;
end
$$;
create trigger trava_movimento before insert on caixa_movimentos for each row execute function trava_movimento();

-- ───────────── ações ─────────────

-- Fecha a comanda no caixa aberto. Pagamentos precisam somar o total. Os horários ligados viram "concluído".
create function fechar_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v_caixa uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  if c.status <> 'aberta' then raise exception 'comanda_fechada' using errcode = '55000'; end if;
  select id into v_caixa from caixas where salao_id = c.salao_id and fechado_em is null;
  if v_caixa is null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  select * into t from total_comanda(p_comanda);
  if not exists (select 1 from comanda_itens where comanda_id = p_comanda) then raise exception 'comanda_vazia' using errcode = '22023'; end if;
  if t.total < 0 then raise exception 'desconto_maior_que_total' using errcode = '22023'; end if;
  if t.pago <> t.total then raise exception 'pagamento_diferente' using errcode = '22023'; end if;
  perform set_config('belezando.fechando', 'sim', true);
  update comandas set status = 'fechada', caixa_id = v_caixa, fechada_em = now(), fechada_por = auth.uid() where id = p_comanda;
  perform set_config('belezando.fechando', '', true);
  update agendamentos set status = 'concluido'
  where id in (select agendamento_id from comanda_itens where comanda_id = p_comanda and agendamento_id is not null)
    and status not in ('cancelado', 'faltou', 'concluido');
end
$$;

-- O administrador reabre uma comanda fechada por engano (fica na auditoria). Só enquanto o caixa dela está aberto.
create function reabrir_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador reabre comanda' using errcode = '42501'; end if;
  if not exists (select 1 from comandas c join caixas x on x.id = c.caixa_id
                 where c.id = p_comanda and c.salao_id = meu_salao() and c.status = 'fechada' and x.fechado_em is null) then
    raise exception 'comanda_nao_reabre' using errcode = '55000';
  end if;
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set status = 'aberta', caixa_id = null, fechada_em = null, fechada_por = null where id = p_comanda;
  perform set_config('belezando.reabrindo', '', true);
end
$$;

-- Resumo do caixa: entradas por forma de pagamento, gorjetas, sangrias, suprimentos e o dinheiro esperado na gaveta.
create function resumo_caixa(p_caixa uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  with cx as (select * from caixas where id = p_caixa and salao_id = meu_salao()),
  pags as (
    select p.forma, sum(p.valor_centavos)::int v from comanda_pagamentos p join comandas c on c.id = p.comanda_id
    where c.caixa_id = p_caixa and c.status = 'fechada' group by p.forma
  ),
  mov as (select tipo, sum(valor_centavos)::int v from caixa_movimentos where caixa_id = p_caixa group by tipo),
  com as (select count(*)::int n, coalesce(sum((select receita from total_comanda(c.id))), 0)::int receita,
                 coalesce(sum((select gorjetas from total_comanda(c.id))), 0)::int gorjetas
          from comandas c where c.caixa_id = p_caixa and c.status = 'fechada')
  select jsonb_build_object(
    'formas', coalesce((select jsonb_object_agg(forma, v) from pags), '{}'::jsonb),
    'comandas', com.n, 'receita', com.receita, 'gorjetas', com.gorjetas,
    'troco_inicial', cx.troco_inicial_centavos,
    'sangrias', coalesce((select v from mov where tipo = 'sangria'), 0),
    'suprimentos', coalesce((select v from mov where tipo = 'suprimento'), 0),
    'dinheiro_esperado', cx.troco_inicial_centavos + coalesce((select v from pags where forma = 'dinheiro'), 0)
       + coalesce((select v from mov where tipo = 'suprimento'), 0) - coalesce((select v from mov where tipo = 'sangria'), 0)
  ) from cx, com
$$;

-- Fecha o caixa guardando o que foi contado e o que era esperado. Comandas abertas continuam abertas para o próximo caixa.
create function fechar_caixa(p_caixa uuid, p_contado jsonb, p_obs text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v jsonb;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção fecham o caixa' using errcode = '42501'; end if;
  if not exists (select 1 from caixas where id = p_caixa and salao_id = meu_salao() and fechado_em is null) then
    raise exception 'caixa_fechado' using errcode = '55000';
  end if;
  v := resumo_caixa(p_caixa);
  update caixas set fechado_em = now(), fechado_por = auth.uid(), contado = p_contado, esperado = v, observacao = left(p_obs, 500)
  where id = p_caixa;
  return v;
end
$$;

revoke all on function total_comanda(uuid), fechar_comanda(uuid), reabrir_comanda(uuid), resumo_caixa(uuid), fechar_caixa(uuid, jsonb, text) from public, anon;
grant execute on function total_comanda(uuid), fechar_comanda(uuid), reabrir_comanda(uuid), resumo_caixa(uuid), fechar_caixa(uuid, jsonb, text) to authenticated;
revoke execute on function trava_comanda_aberta(), trava_comanda(), trava_caixa(), trava_movimento() from public, anon, authenticated;

-- ───────────── RLS e permissões ─────────────

alter table produtos enable row level security;
alter table caixas enable row level security;
alter table caixa_movimentos enable row level security;
alter table comandas enable row level security;
alter table comanda_itens enable row level security;
alter table comanda_pagamentos enable row level security;

create policy produtos_ler on produtos for select to authenticated using (salao_id = meu_salao());
create policy produtos_escrever on produtos for all to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');

create policy caixas_ler on caixas for select to authenticated using (salao_id = meu_salao());
create policy caixas_abrir on caixas for insert to authenticated with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
create policy mov_ler on caixa_movimentos for select to authenticated using (salao_id = meu_salao());
create policy mov_criar on caixa_movimentos for insert to authenticated with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));

create policy comandas_ler on comandas for select to authenticated using (salao_id = meu_salao());
create policy comandas_criar on comandas for insert to authenticated with check (salao_id = meu_salao());
create policy comandas_editar on comandas for update to authenticated using (salao_id = meu_salao()) with check (salao_id = meu_salao());
create policy itens_ler on comanda_itens for select to authenticated using (salao_id = meu_salao());
create policy itens_escrever on comanda_itens for all to authenticated using (salao_id = meu_salao()) with check (salao_id = meu_salao());
create policy pags_ler on comanda_pagamentos for select to authenticated using (salao_id = meu_salao());
create policy pags_escrever on comanda_pagamentos for all to authenticated using (salao_id = meu_salao()) with check (salao_id = meu_salao());

revoke all on produtos, caixas, caixa_movimentos, comandas, comanda_itens, comanda_pagamentos from anon, authenticated;
grant select, insert, update, delete on produtos to authenticated;
grant select on caixas to authenticated;
grant insert (troco_inicial_centavos) on caixas to authenticated;
grant select on caixa_movimentos to authenticated;
grant insert (caixa_id, tipo, valor_centavos, motivo) on caixa_movimentos to authenticated;
grant select on comandas to authenticated;
grant insert (cliente_id, observacao) on comandas to authenticated;
grant update (cliente_id, desconto_centavos, observacao, status) on comandas to authenticated;
grant select, delete on comanda_itens, comanda_pagamentos to authenticated;
grant insert (comanda_id, tipo, servico_id, produto_id, agendamento_id, descricao, profissional_id, assistente_id, quantidade, preco_centavos, desconto_centavos) on comanda_itens to authenticated;
grant update (profissional_id, assistente_id, quantidade, preco_centavos, desconto_centavos) on comanda_itens to authenticated;
grant insert (comanda_id, forma, valor_centavos, parcelas) on comanda_pagamentos to authenticated;
grant update (preco_centavos) on servicos to authenticated;

create trigger aud_comandas after insert or update or delete on comandas for each row execute function auditar();
create trigger aud_comanda_itens after insert or update or delete on comanda_itens for each row execute function auditar();
create trigger aud_comanda_pagamentos after insert or update or delete on comanda_pagamentos for each row execute function auditar();
create trigger aud_caixas after insert or update on caixas for each row execute function auditar();
create trigger aud_caixa_movimentos after insert on caixa_movimentos for each row execute function auditar();
create trigger aud_produtos after insert or update or delete on produtos for each row execute function auditar();
-- Belezando · comissão, vales, fechamento de pagamento e Salão Parceiro (Lei 13.352/2016).
-- A comissão de cada item nasce quando a comanda fecha e fica congelada (mudar a regra não mexe no passado).
-- Base = valor do item − parte do desconto da comanda − (se o salão escolher e o vínculo permitir) taxa do cartão e custo do produto.
-- Para profissional CLT a taxa do cartão e o custo de produto nunca são descontados (convenções coletivas proíbem).

create type vinculo as enum ('socio', 'clt', 'parceiro', 'autonomo');

alter table membros add column vinculo vinculo not null default 'parceiro';
alter table membros add column documento text check (length(documento) <= 20);      -- CPF ou CNPJ (parceiro precisa de CNPJ)
alter table membros add column contrato_inicio date;
alter table membros add column contrato_fim date;
alter table membros add column contrato_homologado_em date;
alter table membros add constraint contrato_ok check (contrato_fim is null or contrato_inicio is null or contrato_fim > contrato_inicio);
grant update (vinculo, documento, contrato_inicio, contrato_fim, contrato_homologado_em) on membros to authenticated;
update membros set vinculo = 'socio' where papel = 'admin';
update membros set vinculo = 'clt' where papel = 'recepcao';  -- a Lei do Salão Parceiro não cobre recepção

alter table saloes add column taxa_debito numeric(5,2) not null default 0 check (taxa_debito between 0 and 20);
alter table saloes add column taxa_credito numeric(5,2) not null default 0 check (taxa_credito between 0 and 20);
alter table saloes add column taxa_credito_parcelado numeric(5,2) not null default 0 check (taxa_credito_parcelado between 0 and 30);
alter table saloes add column taxa_pix numeric(5,2) not null default 0 check (taxa_pix between 0 and 20);
alter table saloes add column comissao_desconta_taxa boolean not null default false;
alter table saloes add column comissao_desconta_custo boolean not null default false;
grant update (taxa_debito, taxa_credito, taxa_credito_parcelado, taxa_pix, comissao_desconta_taxa, comissao_desconta_custo) on saloes to authenticated;

alter table servicos add column custo_produto_centavos int not null default 0 check (custo_produto_centavos between 0 and 10000000);

-- Regra mais específica vence: profissional + serviço > profissional > serviço > padrão do salão.
create table regras_comissao (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  tipo text not null check (tipo in ('servico', 'produto')),
  profissional_id uuid,
  servico_id uuid,
  percentual numeric(5,2) not null check (percentual between 0 and 100),
  assistente_percentual numeric(5,2) not null default 0 check (assistente_percentual between 0 and 100),
  check (tipo = 'servico' or (servico_id is null and assistente_percentual = 0)),
  check (percentual + assistente_percentual <= 100),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id) on delete cascade,
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade
);
create unique index regra_unica on regras_comissao (salao_id, tipo, coalesce(profissional_id, '00000000-0000-0000-0000-000000000000'), coalesce(servico_id, '00000000-0000-0000-0000-000000000000'));

create table fechamentos_comissao (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  profissional_id uuid not null,
  periodo_inicio date not null,
  periodo_fim date not null,
  comissoes_centavos int not null,
  gorjetas_centavos int not null,
  vales_centavos int not null,
  pago_centavos int not null,
  forma text check (length(forma) <= 40),
  pago_por uuid default auth.uid(),
  pago_em timestamptz not null default now(),
  unique (id, salao_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id)
);
create index on fechamentos_comissao (salao_id, pago_em desc);

create table comissoes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  comanda_id uuid not null,
  item_id uuid not null,
  profissional_id uuid not null,
  papel text not null check (papel in ('profissional', 'assistente', 'vendedor', 'gorjeta')),
  competencia date not null,                 -- dia em que a comanda fechou (no fuso do salão)
  descricao text not null,
  bruto_centavos int not null,               -- valor do item depois dos descontos
  taxa_centavos int not null default 0,      -- parte da taxa do cartão descontada da base
  custo_centavos int not null default 0,     -- custo de produto descontado da base
  base_centavos int not null,
  percentual numeric(5,2) not null,
  valor_centavos int not null,
  fechamento_id uuid,
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade,
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id),
  foreign key (fechamento_id, salao_id) references fechamentos_comissao (id, salao_id)
);
create index on comissoes (salao_id, profissional_id, competencia);
create index on comissoes (comanda_id);
create index on comissoes (fechamento_id);

create table vales (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  profissional_id uuid not null,
  valor_centavos int not null check (valor_centavos between 1 and 10000000),
  data date not null default current_date,
  motivo text check (length(motivo) <= 200),
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  fechamento_id uuid,
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id),
  foreign key (fechamento_id, salao_id) references fechamentos_comissao (id, salao_id)
);
create index on vales (salao_id, profissional_id, data);

-- ───────────── cálculo ─────────────

create function percentual_comissao(p_salao uuid, p_tipo text, p_prof uuid, p_servico uuid) returns regras_comissao
language sql stable set search_path = public, pg_temp as
$$
  select r.* from regras_comissao r
  where r.salao_id = p_salao and r.tipo = p_tipo
    and (r.profissional_id is null or r.profissional_id = p_prof)
    and (r.servico_id is null or r.servico_id = p_servico)
  order by (r.profissional_id is not null and r.servico_id is not null) desc, (r.profissional_id is not null) desc, (r.servico_id is not null) desc
  limit 1
$$;

create function gerar_comissoes(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  s saloes;
  i comanda_itens;
  r regras_comissao;
  v_total int;           -- o que a cliente pagou (com gorjeta)
  v_itens int;           -- soma dos itens sem gorjeta, antes do desconto da comanda
  v_taxa numeric;        -- taxa total do cartão/pix nesta comanda
  v_bruto int; v_taxa_item int; v_custo int; v_base int;
  v_prof_vinc vinculo;
  v_dia date;
begin
  select * into c from comandas where id = p_comanda;
  select * into s from saloes where id = c.salao_id;
  delete from comissoes where comanda_id = p_comanda and fechamento_id is null;
  v_dia := (coalesce(c.fechada_em, now()) at time zone s.fuso)::date;
  select total into v_total from total_comanda(p_comanda);
  select coalesce(sum(preco_centavos * quantidade - desconto_centavos), 0) into v_itens from comanda_itens where comanda_id = p_comanda and tipo <> 'gorjeta';
  select coalesce(sum(valor_centavos * case forma
           when 'debito' then s.taxa_debito when 'pix' then s.taxa_pix
           when 'credito' then case when parcelas > 1 then s.taxa_credito_parcelado else s.taxa_credito end
           else 0 end / 100.0), 0)
    into v_taxa from comanda_pagamentos where comanda_id = p_comanda;

  for i in select * from comanda_itens where comanda_id = p_comanda order by criado_em loop
    if i.tipo = 'gorjeta' then
      insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, base_centavos, percentual, valor_centavos)
      values (c.salao_id, c.id, i.id, i.profissional_id, 'gorjeta', v_dia, i.descricao, i.preco_centavos, i.preco_centavos, 100, i.preco_centavos);
      continue;
    end if;
    if i.profissional_id is null then continue; end if;
    select vinculo into v_prof_vinc from membros where user_id = i.profissional_id and salao_id = c.salao_id;
    if v_prof_vinc = 'socio' then continue; end if;
    -- parte do desconto da comanda proporcional ao item
    v_bruto := i.preco_centavos * i.quantidade - i.desconto_centavos;
    if v_itens > 0 then v_bruto := v_bruto - round(c.desconto_centavos::numeric * v_bruto / v_itens)::int; end if;
    v_taxa_item := case when s.comissao_desconta_taxa and v_prof_vinc <> 'clt' and v_total > 0 then round(v_taxa * v_bruto / v_total)::int else 0 end;
    v_custo := case when s.comissao_desconta_custo and v_prof_vinc <> 'clt' and i.tipo = 'servico'
                    then i.quantidade * coalesce((select custo_produto_centavos from servicos where id = i.servico_id), 0) else 0 end;
    v_base := greatest(v_bruto - v_taxa_item - v_custo, 0);
    r := percentual_comissao(c.salao_id, i.tipo::text, i.profissional_id, i.servico_id);
    if r.id is null then continue; end if;
    insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
    values (c.salao_id, c.id, i.id, i.profissional_id, case when i.tipo = 'produto' then 'vendedor' else 'profissional' end, v_dia, i.descricao,
            v_bruto, v_taxa_item, v_custo, v_base, r.percentual, round(v_base * r.percentual / 100)::int);
    if i.assistente_id is not null and r.assistente_percentual > 0 then
      insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
      values (c.salao_id, c.id, i.id, i.assistente_id, 'assistente', v_dia, i.descricao || ' (assistente)',
              v_bruto, v_taxa_item, v_custo, v_base, r.assistente_percentual, round(v_base * r.assistente_percentual / 100)::int);
    end if;
  end loop;
end
$$;
revoke all on function gerar_comissoes(uuid) from public, anon, authenticated;
revoke all on function percentual_comissao(uuid, text, uuid, uuid) from public, anon;
grant execute on function percentual_comissao(uuid, text, uuid, uuid) to authenticated;

-- Fechar a comanda passa a gerar as comissões; reabrir apaga as que ainda não foram pagas.
create or replace function fechar_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v_caixa uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  if c.status <> 'aberta' then raise exception 'comanda_fechada' using errcode = '55000'; end if;
  select id into v_caixa from caixas where salao_id = c.salao_id and fechado_em is null;
  if v_caixa is null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  select * into t from total_comanda(p_comanda);
  if not exists (select 1 from comanda_itens where comanda_id = p_comanda) then raise exception 'comanda_vazia' using errcode = '22023'; end if;
  if t.total < 0 then raise exception 'desconto_maior_que_total' using errcode = '22023'; end if;
  if t.pago <> t.total then raise exception 'pagamento_diferente' using errcode = '22023'; end if;
  perform set_config('belezando.fechando', 'sim', true);
  update comandas set status = 'fechada', caixa_id = v_caixa, fechada_em = now(), fechada_por = auth.uid() where id = p_comanda;
  perform set_config('belezando.fechando', '', true);
  update agendamentos set status = 'concluido'
  where id in (select agendamento_id from comanda_itens where comanda_id = p_comanda and agendamento_id is not null)
    and status not in ('cancelado', 'faltou', 'concluido');
  perform gerar_comissoes(p_comanda);
end
$$;

create or replace function reabrir_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador reabre comanda' using errcode = '42501'; end if;
  if not exists (select 1 from comandas c join caixas x on x.id = c.caixa_id
                 where c.id = p_comanda and c.salao_id = meu_salao() and c.status = 'fechada' and x.fechado_em is null) then
    raise exception 'comanda_nao_reabre' using errcode = '55000';
  end if;
  if exists (select 1 from comissoes where comanda_id = p_comanda and fechamento_id is not null) then
    raise exception 'comissao_ja_paga' using errcode = '55000';
  end if;
  delete from comissoes where comanda_id = p_comanda;
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set status = 'aberta', caixa_id = null, fechada_em = null, fechada_por = null where id = p_comanda;
  perform set_config('belezando.reabrindo', '', true);
end
$$;

-- Comanda cancelada depois de fechada não existe (só aberta vira cancelada), mas por garantia: cancelar limpa comissões não pagas.

-- ───────────── pagamento ao profissional ─────────────

-- Junta comissões e gorjetas do período ainda não pagas, desconta os vales e registra o pagamento.
create function pagar_profissional(p_prof uuid, p_inicio date, p_fim date, p_forma text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_com int; v_gor int; v_val int;
  v_id uuid;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador registra pagamento' using errcode = '42501'; end if;
  if p_fim < p_inicio then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from membros where user_id = p_prof and salao_id = v_salao) then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
  select coalesce(sum(valor_centavos) filter (where papel <> 'gorjeta'), 0), coalesce(sum(valor_centavos) filter (where papel = 'gorjeta'), 0)
    into v_com, v_gor from comissoes
  where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  select coalesce(sum(valor_centavos), 0) into v_val from vales
  where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and data <= p_fim;
  if v_com + v_gor = 0 and v_val = 0 then raise exception 'nada_a_pagar' using errcode = '22023'; end if;
  insert into fechamentos_comissao (salao_id, profissional_id, periodo_inicio, periodo_fim, comissoes_centavos, gorjetas_centavos, vales_centavos, pago_centavos, forma)
  values (v_salao, p_prof, p_inicio, p_fim, v_com, v_gor, v_val, v_com + v_gor - v_val, left(p_forma, 40)) returning id into v_id;
  update comissoes set fechamento_id = v_id where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  update vales set fechamento_id = v_id where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and data <= p_fim;
  return v_id;
end
$$;

-- Comprovação da parceria (Lei 13.352): por parceiro, quanto entrou de serviço, quanto ficou com o salão (cota-parte) e quanto foi repassado.
create function relatorio_parceria(p_inicio date, p_fim date) returns table (
  profissional_id uuid, nome text, documento text, contrato_inicio date, contrato_fim date, contrato_homologado_em date,
  servicos_centavos bigint, cota_profissional_centavos bigint, cota_salao_centavos bigint, gorjetas_centavos bigint, repassado_centavos bigint
)
language sql stable security definer set search_path = public, pg_temp as
$$
  select m.user_id, m.nome, m.documento, m.contrato_inicio, m.contrato_fim, m.contrato_homologado_em,
    coalesce(sum(x.bruto_centavos) filter (where x.papel = 'profissional'), 0),
    coalesce(sum(x.valor_centavos) filter (where x.papel in ('profissional', 'assistente', 'vendedor')), 0),
    coalesce(sum(x.bruto_centavos - x.valor_centavos) filter (where x.papel = 'profissional'), 0),
    coalesce(sum(x.valor_centavos) filter (where x.papel = 'gorjeta'), 0),
    (select coalesce(sum(f.pago_centavos), 0) from fechamentos_comissao f
      where f.profissional_id = m.user_id and f.salao_id = m.salao_id and (f.pago_em at time zone s.fuso)::date between p_inicio and p_fim)
  from membros m join saloes s on s.id = m.salao_id
  left join comissoes x on x.profissional_id = m.user_id and x.salao_id = m.salao_id and x.competencia between p_inicio and p_fim
  where m.salao_id = meu_salao() and meu_papel() = 'admin' and m.vinculo = 'parceiro' and m.papel <> 'recepcao'
  group by m.user_id, m.nome, m.documento, m.contrato_inicio, m.contrato_fim, m.contrato_homologado_em, m.salao_id, s.fuso
  order by m.nome
$$;

revoke all on function pagar_profissional(uuid, date, date, text), relatorio_parceria(date, date) from public, anon;
grant execute on function pagar_profissional(uuid, date, date, text), relatorio_parceria(date, date) to authenticated;

-- ───────────── RLS ─────────────

alter table regras_comissao enable row level security;
alter table comissoes enable row level security;
alter table vales enable row level security;
alter table fechamentos_comissao enable row level security;

-- Regras são transparentes para a equipe; só o administrador muda.
create policy regras_ler on regras_comissao for select to authenticated using (salao_id = meu_salao());
create policy regras_escrever on regras_comissao for all to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');
-- Cada profissional vê só o próprio dinheiro; o administrador vê tudo.
create policy comissoes_ler on comissoes for select to authenticated
  using (salao_id = meu_salao() and (meu_papel() = 'admin' or profissional_id = auth.uid()));
create policy fech_ler on fechamentos_comissao for select to authenticated
  using (salao_id = meu_salao() and (meu_papel() = 'admin' or profissional_id = auth.uid()));
create policy vales_ler on vales for select to authenticated
  using (salao_id = meu_salao() and (meu_papel() in ('admin', 'recepcao') or profissional_id = auth.uid()));
create policy vales_criar on vales for insert to authenticated with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
create policy vales_apagar on vales for delete to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin' and fechamento_id is null);

revoke all on regras_comissao, comissoes, vales, fechamentos_comissao from anon, authenticated;
grant select, insert, update, delete on regras_comissao to authenticated;
grant select on comissoes, fechamentos_comissao to authenticated;
grant select, delete on vales to authenticated;
grant insert (profissional_id, valor_centavos, data, motivo) on vales to authenticated;
grant update (custo_produto_centavos) on servicos to authenticated;

create trigger aud_regras after insert or update or delete on regras_comissao for each row execute function auditar();
create trigger aud_vales after insert or delete on vales for each row execute function auditar();
create trigger aud_fechamentos after insert on fechamentos_comissao for each row execute function auditar();

-- Salão novo nasce com 40% em serviço e 10% em produto (o administrador ajusta em Comissões).
insert into regras_comissao (salao_id, tipo, percentual) select id, 'servico', 40 from saloes;
insert into regras_comissao (salao_id, tipo, percentual) select id, 'produto', 10 from saloes;
create function regras_iniciais() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  insert into regras_comissao (salao_id, tipo, percentual) values (new.id, 'servico', 40), (new.id, 'produto', 10);
  return new;
end
$$;
revoke all on function regras_iniciais() from public, anon, authenticated;
create trigger regras_salao after insert on saloes for each row execute function regras_iniciais();

-- Quem cria o salão é sócio (não comissionado). Recepção não pode ser parceira: entra como CLT.
create function socio_fundador() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.papel = 'admin' and not exists (select 1 from membros where salao_id = new.salao_id) then new.vinculo := 'socio'; end if;
  if new.papel = 'recepcao' and new.vinculo = 'parceiro' then new.vinculo := 'clt'; end if;
  return new;
end
$$;
revoke all on function socio_fundador() from public, anon, authenticated;
create trigger socio_fundador before insert on membros for each row execute function socio_fundador();
-- Belezando · ficha da cliente: dados de salão, ficha técnica de química, testes de alergia e de mecha, fotos e união de cadastros.
-- A ficha técnica é o que faz a cor sair igual na próxima vez, prova o teste feito e fica com o salão mesmo se o profissional sair.

alter table clientes add column alergias text check (length(alergias) <= 500);
alter table clientes add column tipo_cabelo text check (tipo_cabelo in ('liso', 'ondulado', 'cacheado', 'crespo'));
alter table clientes add column preferencias text check (length(preferencias) <= 1000);
alter table clientes add column origem text check (origem in ('indicacao', 'instagram', 'google', 'whatsapp', 'passante', 'facebook', 'tiktok', 'outro'));
alter table clientes add column indicado_por uuid;
alter table clientes add column consentimento_imagem_em timestamptz;   -- uso de fotos antes/depois no portfólio do salão
alter table clientes add constraint indicado_ok foreign key (indicado_por, salao_id) references clientes (id, salao_id) on delete set null (indicado_por);
grant insert (alergias, tipo_cabelo, preferencias, origem, indicado_por) on clientes to authenticated;
grant update (alergias, tipo_cabelo, preferencias, origem, indicado_por) on clientes to authenticated;

-- Fórmula: lista de {"zona": "raiz", "produto": "Koleston 7.1", "gramas": 30, "oxidante": 20, "oxidante_gramas": 45}.
create function formula_valida(f jsonb) returns boolean
language sql immutable set search_path = public, pg_temp as
$$
  select jsonb_typeof(f) = 'array' and jsonb_array_length(f) <= 20
    and not exists (select 1 from jsonb_array_elements(f) e
                    where jsonb_typeof(e) <> 'object' or coalesce(length(e ->> 'produto'), 0) not between 1 and 120
                       or length(coalesce(e ->> 'zona', '')) > 60)
$$;
revoke all on function formula_valida(jsonb) from public, anon;
grant execute on function formula_valida(jsonb) to authenticated, service_role;

create table fichas_tecnicas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  agendamento_id uuid,
  profissional_id uuid default auth.uid(),
  data date not null default current_date,
  servico text not null check (length(servico) between 2 and 120),
  tecnica text check (length(tecnica) <= 200),        -- ex.: mechas no papel, babylights, retoque de raiz
  formula jsonb not null default '[]' check (formula_valida(formula)),
  pausa_min int check (pausa_min between 0 and 240),
  resultado text check (length(resultado) <= 1000),
  observacoes text check (length(observacoes) <= 2000),
  criado_em timestamptz not null default now(),
  unique (id, salao_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (agendamento_id, salao_id) references agendamentos (id, salao_id) on delete set null (agendamento_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id)
);
create index on fichas_tecnicas (cliente_id, data desc);
create index on fichas_tecnicas (salao_id);

-- Testes de alergia (toque) e de mecha: data e resultado guardados são a prova de que o salão fez o teste.
create table testes_cliente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  tipo text not null check (tipo in ('alergia', 'mecha')),
  produto text not null check (length(produto) between 2 and 120),
  resultado text not null check (resultado in ('sem_reacao', 'reacao', 'nao_recomendado', 'aprovado')),
  feito_em date not null default current_date,
  observacoes text check (length(observacoes) <= 500),
  registrado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on testes_cliente (cliente_id, feito_em desc);

-- Fotos ficam no Storage (balde "fotos", pasta <salao_id>/); aqui só o caminho.
create table fotos_cliente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  ficha_id uuid,
  momento text not null check (momento in ('antes', 'depois', 'referencia')),
  caminho text not null check (length(caminho) between 5 and 300),
  enviado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (ficha_id, salao_id) references fichas_tecnicas (id, salao_id) on delete set null (ficha_id)
);
create index on fotos_cliente (cliente_id, criado_em desc);

-- O caminho da foto precisa estar na pasta do próprio salão.
create function foto_na_pasta() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if split_part(new.caminho, '/', 1) <> new.salao_id::text then raise exception 'caminho fora da pasta do salão' using errcode = '42501'; end if;
  return new;
end
$$;
create trigger foto_na_pasta before insert or update on fotos_cliente for each row execute function foto_na_pasta();
revoke execute on function foto_na_pasta() from public, anon, authenticated;

alter table fichas_tecnicas enable row level security;
alter table testes_cliente enable row level security;
alter table fotos_cliente enable row level security;

-- A equipe toda lê (a recepção prepara o atendimento); quem atende escreve; só o administrador apaga.
create policy fichas_ler on fichas_tecnicas for select to authenticated using (salao_id = meu_salao());
create policy fichas_criar on fichas_tecnicas for insert to authenticated with check (salao_id = meu_salao());
create policy fichas_editar on fichas_tecnicas for update to authenticated
  using (salao_id = meu_salao() and (meu_papel() = 'admin' or profissional_id = auth.uid())) with check (salao_id = meu_salao());
create policy fichas_apagar on fichas_tecnicas for delete to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin');
create policy testes_ler on testes_cliente for select to authenticated using (salao_id = meu_salao());
create policy testes_criar on testes_cliente for insert to authenticated with check (salao_id = meu_salao());
create policy fotos_ler on fotos_cliente for select to authenticated using (salao_id = meu_salao());
create policy fotos_criar on fotos_cliente for insert to authenticated with check (salao_id = meu_salao());
create policy fotos_apagar on fotos_cliente for delete to authenticated using (salao_id = meu_salao() and (meu_papel() = 'admin' or enviado_por = auth.uid()));

revoke all on fichas_tecnicas, testes_cliente, fotos_cliente from anon, authenticated;
grant select, delete on fichas_tecnicas to authenticated;
grant insert (cliente_id, agendamento_id, profissional_id, data, servico, tecnica, formula, pausa_min, resultado, observacoes) on fichas_tecnicas to authenticated;
grant update (data, servico, tecnica, formula, pausa_min, resultado, observacoes) on fichas_tecnicas to authenticated;
grant select on testes_cliente to authenticated;           -- teste registrado não muda nem some: é prova
grant insert (cliente_id, tipo, produto, resultado, feito_em, observacoes) on testes_cliente to authenticated;
grant select, delete on fotos_cliente to authenticated;
grant insert (cliente_id, ficha_id, momento, caminho) on fotos_cliente to authenticated;

create trigger aud_fichas after insert or update or delete on fichas_tecnicas for each row execute function auditar();
create trigger aud_testes after insert on testes_cliente for each row execute function auditar();
create trigger aud_fotos after insert or delete on fotos_cliente for each row execute function auditar();

-- Aceite de uso de imagem: só por função (fica auditado). Retirar o aceite também é registrado.
create function registrar_aceite_imagem(p_cliente uuid, p_aceita boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update clientes set consentimento_imagem_em = case when p_aceita then coalesce(consentimento_imagem_em, now()) else null end
  where id = p_cliente and salao_id = meu_salao();
  if not found then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
end
$$;
revoke all on function registrar_aceite_imagem(uuid, boolean) from public, anon;
grant execute on function registrar_aceite_imagem(uuid, boolean) to authenticated;

-- Une dois cadastros da mesma pessoa: tudo do duplicado passa para o que fica, e o duplicado some.
create function unir_clientes(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  a clientes; b clientes;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção unem cadastros' using errcode = '42501'; end if;
  if p_manter = p_remover then raise exception 'mesmo cadastro' using errcode = '22023'; end if;
  select * into a from clientes where id = p_manter and salao_id = v_salao for update;
  select * into b from clientes where id = p_remover and salao_id = v_salao for update;
  if a.id is null or b.id is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update agendamentos set cliente_id = a.id where cliente_id = b.id;
  update comandas set cliente_id = a.id where cliente_id = b.id;
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;
revoke all on function unir_clientes(uuid, uuid) from public, anon;
grant execute on function unir_clientes(uuid, uuid) to authenticated;

-- Storage: balde privado de fotos, cada salão só na própria pasta. Só existe no Supabase (o teste local não tem o schema storage).
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('fotos', 'fotos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
    on conflict (id) do nothing;
    execute $p$create policy fotos_salao_ler on storage.objects for select to authenticated
      using (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.meu_salao()::text)$p$;
    execute $p$create policy fotos_salao_enviar on storage.objects for insert to authenticated
      with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.meu_salao()::text)$p$;
    execute $p$create policy fotos_salao_apagar on storage.objects for delete to authenticated
      using (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.meu_salao()::text)$p$;
  end if;
end $$;
-- Belezando · agendamento online pelo link do salão (sem app e sem senha) e sinal via Pix.
-- O horário fica segurado enquanto o sinal não é pago (30 min); sem pagamento, ele é cancelado sozinho.
-- O aceite da política de cancelamento fica guardado com o texto, a hora, o IP e o aparelho: é a prova contra contestação.

alter type origem_agendamento add value if not exists 'online';
alter type forma_pagamento add value if not exists 'sinal';

alter table saloes add column agendamento_online boolean not null default true;
alter table saloes add column politica_cancelamento text check (length(politica_cancelamento) <= 1000);
alter table saloes add column cancelamento_horas int not null default 24 check (cancelamento_horas between 0 and 168);
alter table saloes add column pix_chave text check (length(pix_chave) <= 77);
alter table saloes add column pix_nome text check (length(pix_nome) <= 25);
alter table saloes add column pix_cidade text check (length(pix_cidade) <= 15);
grant update (agendamento_online, politica_cancelamento, cancelamento_horas, pix_chave, pix_nome, pix_cidade) on saloes to authenticated;

alter table servicos add column sinal_percentual int not null default 0 check (sinal_percentual between 0 and 100);
alter table servicos add column online boolean not null default true;   -- aparece no link público
grant update (sinal_percentual, online) on servicos to authenticated;

-- Token que a cliente recebe para ver e cancelar o próprio horário sem login.
alter table agendamentos add column token uuid not null default gen_random_uuid();
create unique index on agendamentos (token);

-- Token do Mercado Pago (opcional): só a chave de serviço lê.
create table pagamentos_contas (
  salao_id uuid primary key references saloes (id) on delete cascade,
  mp_access_token text check (length(mp_access_token) between 20 and 300),
  atualizado_em timestamptz not null default now()
);
alter table pagamentos_contas enable row level security;
revoke all on pagamentos_contas from anon, authenticated;

create table sinais (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  agendamento_id uuid not null unique,
  valor_centavos int not null check (valor_centavos between 1 and 10000000),
  status text not null default 'pendente' check (status in ('pendente', 'pago', 'expirado', 'credito', 'devolvido', 'usado')),
  modo text not null check (modo in ('pix_manual', 'mercadopago')),
  txid text check (length(txid) <= 35),
  copia_cola text check (length(copia_cola) <= 600),
  mp_payment_id text,
  expira_em timestamptz not null default now() + interval '30 minutes',
  pago_em timestamptz,
  confirmado_por uuid,
  criado_em timestamptz not null default now(),
  foreign key (agendamento_id, salao_id) references agendamentos (id, salao_id) on delete cascade
);
create index on sinais (status, expira_em);
create unique index on sinais (mp_payment_id) where mp_payment_id is not null;

create table aceites_politica (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  agendamento_id uuid not null,
  cliente_id uuid not null,
  texto text not null,
  ip text check (length(ip) <= 64),
  agente text check (length(agente) <= 300),
  aceito_em timestamptz not null default now(),
  foreign key (agendamento_id, salao_id) references agendamentos (id, salao_id) on delete cascade,
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on aceites_politica (agendamento_id);

alter table sinais enable row level security;
alter table aceites_politica enable row level security;
create policy sinais_ler on sinais for select to authenticated using (salao_id = meu_salao());
create policy aceites_ler on aceites_politica for select to authenticated using (salao_id = meu_salao());
revoke all on sinais, aceites_politica from anon, authenticated;
grant select on sinais, aceites_politica to authenticated;
create trigger aud_sinais after insert or update on sinais for each row execute function auditar();

-- O teto de 3 horários futuros por cliente vale também para o link público.
create or replace function limitar_agendamentos_whatsapp() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if new.origem in ('whatsapp', 'online') and new.status in ('agendado', 'confirmado') and
     (select count(*) from agendamentos a
      where a.cliente_id = new.cliente_id and a.status in ('agendado', 'confirmado') and a.inicio > now()) >= 3 then
    raise exception 'limite_agendamentos' using errcode = '22023';
  end if;
  return new;
end
$$;

-- ───────────── funções do link público (só o servidor, com a chave de serviço) ─────────────

create function agendar_online(
  p_slug text, p_servico uuid, p_profissional uuid, p_inicio timestamptz,
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
  v_texto text;
begin
  select * into c from saloes where slug = lower(p_slug) and agendamento_online;
  if c.id is null then raise exception 'salao_indisponivel' using errcode = 'P0002'; end if;
  select * into v_srv from servicos where id = p_servico and salao_id = c.id and ativo and online;
  if v_srv.id is null or not exists (select 1 from membros where user_id = p_profissional and salao_id = c.id and ativo and papel in ('admin', 'profissional')) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_nome, ''))) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if not coalesce(p_aceite_contato, false) then raise exception 'consentimento obrigatório' using errcode = '22023'; end if;
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(c.id, p_profissional, p_inicio, v_srv.fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  select id into v_cli from clientes where salao_id = c.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli is null then
    insert into clientes (salao_id, nome, telefone, consentimento_em, origem) values (c.id, left(trim(p_nome), 120), v_tel, now(), 'outro') returning id into v_cli;
  else
    update clientes set consentimento_em = coalesce(consentimento_em, now()) where id = v_cli;
  end if;

  v_sinal := round(coalesce(nullif(v_srv.preco_centavos, 0), 0) * v_srv.sinal_percentual / 100.0)::int;
  begin
    insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fases, origem, status)
    values (c.id, v_cli, p_profissional, p_servico, p_inicio, v_srv.fases, 'online', case when v_sinal > 0 then 'agendado' else 'confirmado' end::status_agendamento)
    returning * into v_ag;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;

  v_texto := coalesce(nullif(trim(c.politica_cancelamento), ''),
    format('Cancelamentos e remarcações até %s horas antes do horário. Depois disso, ou em caso de falta, o sinal não é devolvido.', c.cancelamento_horas));
  insert into aceites_politica (salao_id, agendamento_id, cliente_id, texto, ip, agente)
  values (c.id, v_ag.id, v_cli, v_texto, left(p_ip, 64), left(p_agente, 300));
  if v_sinal > 0 then
    insert into sinais (salao_id, agendamento_id, valor_centavos, modo)
    values (c.id, v_ag.id, v_sinal, case when exists (select 1 from pagamentos_contas where salao_id = c.id and mp_access_token is not null) then 'mercadopago' else 'pix_manual' end);
  end if;
  return jsonb_build_object('agendamento_id', v_ag.id, 'token', v_ag.token, 'sinal_centavos', v_sinal);
end
$$;

-- A cliente vê o próprio horário pelo token.
create function horario_publico(p_token uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object(
    'id', a.id, 'inicio', a.inicio, 'fim', a.fim, 'status', a.status, 'servico', s.nome, 'profissional', m.nome,
    'cliente', split_part(cl.nome, ' ', 1), 'salao', c.nome, 'slug', c.slug, 'fuso', c.fuso, 'endereco', c.endereco, 'telefone', c.telefone,
    'cancelamento_horas', c.cancelamento_horas,
    'pode_cancelar', a.status in ('agendado', 'confirmado') and a.inicio - now() >= make_interval(hours => c.cancelamento_horas),
    'sinal', (select jsonb_build_object('valor', x.valor_centavos, 'status', x.status, 'modo', x.modo, 'copia_cola', x.copia_cola, 'expira_em', x.expira_em)
              from sinais x where x.agendamento_id = a.id),
    'pix', jsonb_build_object('chave', c.pix_chave, 'nome', c.pix_nome, 'cidade', c.pix_cidade),
    'politica', (select texto from aceites_politica p where p.agendamento_id = a.id order by aceito_em desc limit 1)
  )
  from agendamentos a join saloes c on c.id = a.salao_id join servicos s on s.id = a.servico_id
  join membros m on m.user_id = a.profissional_id and m.salao_id = a.salao_id join clientes cl on cl.id = a.cliente_id
  where a.token = p_token
$$;

-- Cancelamento pela cliente: só dentro do prazo. Sinal pago vira crédito para a próxima visita.
create function cancelar_online(p_token uuid) returns text
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
  update agendamentos set status = 'cancelado' where id = a.id;
  update sinais set status = case status when 'pago' then 'credito' when 'pendente' then 'expirado' else status end where agendamento_id = a.id;
  return 'cancelado';
end
$$;

-- Guarda o Pix gerado para o sinal (copia e cola e, no Mercado Pago, o id do pagamento).
create function registrar_cobranca_sinal(p_agendamento uuid, p_txid text, p_copia_cola text, p_mp_payment_id text) returns void
language sql security definer set search_path = public, pg_temp as
$$
  update sinais set txid = left(p_txid, 35), copia_cola = left(p_copia_cola, 600), mp_payment_id = coalesce(p_mp_payment_id, mp_payment_id)
  where agendamento_id = p_agendamento and status = 'pendente'
$$;

-- Sinal pago (webhook do Mercado Pago depois de conferir o pagamento na API): confirma o horário.
create function sinal_pago_mp(p_payment_id text, p_valor_centavos int) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  x sinais;
begin
  select * into x from sinais where mp_payment_id = p_payment_id for update;
  if x.id is null or x.status not in ('pendente', 'expirado') or p_valor_centavos < x.valor_centavos then return false; end if;
  update sinais set status = 'pago', pago_em = now() where id = x.id;
  -- pago depois de expirar: tenta devolver o horário (se ainda estiver livre)
  begin
    update agendamentos set status = 'confirmado' where id = x.agendamento_id and status in ('agendado', 'cancelado');
  exception when exclusion_violation then
    update sinais set status = 'credito' where id = x.id;
  end;
  return true;
end
$$;

-- Expira sinais não pagos e libera o horário. Roda no mesmo cron dos lembretes.
create function expirar_sinais() returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  n int;
begin
  with e as (
    update sinais set status = 'expirado' where status = 'pendente' and expira_em < now() returning agendamento_id
  )
  update agendamentos a set status = 'cancelado' from e where a.id = e.agendamento_id and a.status = 'agendado';
  get diagnostics n = row_count;
  return n;
end
$$;

-- A recepção confirma que o Pix do sinal caiu na conta (modo manual).
create function confirmar_sinal(p_agendamento uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção confirmam sinal' using errcode = '42501'; end if;
  update sinais set status = 'pago', pago_em = now(), confirmado_por = auth.uid()
  where agendamento_id = p_agendamento and salao_id = meu_salao() and status in ('pendente', 'expirado');
  if not found then raise exception 'sinal_nao_encontrado' using errcode = 'P0002'; end if;
  update agendamentos set status = 'confirmado' where id = p_agendamento and status in ('agendado', 'cancelado');
end
$$;

-- Ao usar o sinal na comanda, ele sai do saldo da cliente.
create function usar_sinal(p_agendamento uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v int;
begin
  update sinais set status = 'usado' where agendamento_id = p_agendamento and salao_id = meu_salao() and status in ('pago', 'credito')
  returning valor_centavos into v;
  return coalesce(v, 0);
end
$$;

revoke all on function agendar_online(text, uuid, uuid, timestamptz, text, text, boolean, text, text), horario_publico(uuid), cancelar_online(uuid),
  registrar_cobranca_sinal(uuid, text, text, text), sinal_pago_mp(text, int), expirar_sinais() from public, anon, authenticated;
grant execute on function agendar_online(text, uuid, uuid, timestamptz, text, text, boolean, text, text), horario_publico(uuid), cancelar_online(uuid),
  registrar_cobranca_sinal(uuid, text, text, text), sinal_pago_mp(text, int), expirar_sinais() to service_role;
revoke all on function confirmar_sinal(uuid), usar_sinal(uuid) from public, anon;
grant execute on function confirmar_sinal(uuid), usar_sinal(uuid) to authenticated;

-- Token do Mercado Pago: grava só o administrador, ninguém lê pela API.
create function salvar_token_mp(p_token text) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador' using errcode = '42501'; end if;
  insert into pagamentos_contas (salao_id, mp_access_token) values (meu_salao(), nullif(trim(p_token), ''))
  on conflict (salao_id) do update set mp_access_token = excluded.mp_access_token, atualizado_em = now();
end
$$;
revoke all on function salvar_token_mp(text) from public, anon;
grant execute on function salvar_token_mp(text) to authenticated;
-- Belezando · painel do dono: os números que mostram se o salão está saudável.
-- Faturamento, ticket médio, % de produto, ocupação da agenda, faltas, retorno, retorno já marcado ao sair e clientes novos.

create function painel(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
  r jsonb;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador vê o painel' using errcode = '42501'; end if;
  if p_fim < p_inicio or p_fim - p_inicio > 400 then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  select * into s from saloes where id = v_salao;
  de := (p_inicio::timestamp) at time zone s.fuso;
  ate := ((p_fim + 1)::timestamp) at time zone s.fuso;

  with
  cmd as (
    select c.id, c.cliente_id, (c.fechada_em at time zone s.fuso)::date dia from comandas c
    where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate
  ),
  itens as (
    select i.*, cmd.dia from comanda_itens i join cmd on cmd.id = i.comanda_id
  ),
  vendas as (
    select
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'servico'), 0) servicos,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'produto'), 0) produtos,
      coalesce(sum(i.preco_centavos) filter (where i.tipo = 'gorjeta'), 0) gorjetas
    from itens i
  ),
  descontos as (select coalesce(sum(c.desconto_centavos), 0) v from comandas c join cmd on cmd.id = c.id),
  ags as (
    select a.* from agendamentos a where a.salao_id = v_salao and a.inicio >= de and a.inicio < ate
  ),
  atendidos as (select distinct cliente_id from ags where status = 'concluido'),
  -- cliente que já tinha vindo antes do período
  retornou as (
    select count(*) n from atendidos t
    where exists (select 1 from agendamentos x where x.cliente_id = t.cliente_id and x.status = 'concluido' and x.inicio < de)
  ),
  novos as (
    select c.id, c.origem from clientes c where c.salao_id = v_salao and c.criado_em >= de and c.criado_em < ate
  ),
  -- saiu com o próximo horário marcado: existe agendamento criado até o fim do dia do atendimento, para depois dele
  rebook as (
    select count(*) filter (where exists (
      select 1 from agendamentos x where x.cliente_id = a.cliente_id and x.inicio > a.fim and x.status <> 'cancelado'
        and x.criado_em < ((((a.inicio at time zone s.fuso)::date + 1)::timestamp) at time zone s.fuso)
    )) sim, count(*) total
    from (select distinct on (cliente_id) * from ags where status = 'concluido' order by cliente_id, inicio desc) a
  ),
  -- minutos disponíveis: jornada de cada profissional nos dias de trabalho, menos almoço e bloqueios
  dias as (select d::date dia from generate_series(p_inicio, p_fim, interval '1 day') d),
  jornada as (
    select m.user_id, m.nome, d.dia,
      greatest(extract(epoch from coalesce(m.saida, s.fecha) - coalesce(m.entrada, s.abre)) / 60
        - coalesce(extract(epoch from m.almoco_fim - m.almoco_inicio) / 60, 0), 0) minutos
    from membros m cross join dias d
    where m.salao_id = v_salao and m.ativo and m.papel in ('admin', 'profissional')
      and extract(isodow from d.dia)::int = any (coalesce(m.dias_semana, s.dias_semana))
  ),
  bloqueado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo * tstzrange(de, ate)) - lower(o.periodo * tstzrange(de, ate))) / 60) minutos
    from ocupacoes o where o.salao_id = v_salao and o.bloqueio_id is not null and o.periodo && tstzrange(de, ate) group by 1
  ),
  ocupado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo) - lower(o.periodo)) / 60) minutos
    from ocupacoes o join agendamentos a on a.id = o.agendamento_id
    where o.salao_id = v_salao and a.inicio >= de and a.inicio < ate and a.status <> 'faltou' group by 1
  ),
  por_prof as (
    select j.user_id, j.nome, sum(j.minutos) - coalesce(max(b.minutos), 0) disponivel, coalesce(max(o.minutos), 0) ocupado
    from jornada j left join bloqueado b on b.profissional_id = j.user_id left join ocupado o on o.profissional_id = j.user_id
    group by j.user_id, j.nome
  ),
  receita_prof as (
    select i.profissional_id, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) receita, count(distinct i.comanda_id) atendimentos
    from itens i where i.tipo = 'servico' group by 1
  ),
  comissao_prof as (
    select profissional_id, sum(valor_centavos) v from comissoes
    where salao_id = v_salao and papel <> 'gorjeta' and competencia between p_inicio and p_fim group by 1
  ),
  por_dia as (
    select i.dia, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo <> 'gorjeta') v from itens i group by 1
  ),
  top_servicos as (
    select i.descricao, count(*) n, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) v from itens i where i.tipo = 'servico'
    group by 1 order by v desc limit 8
  )
  select jsonb_build_object(
    'receita', (select servicos + produtos from vendas) - (select v from descontos),
    'servicos', (select servicos from vendas), 'produtos', (select produtos from vendas), 'gorjetas', (select gorjetas from vendas),
    'comandas', (select count(*) from cmd),
    'atendimentos', (select count(*) from ags where status = 'concluido'),
    'faltas', (select count(*) from ags where status = 'faltou'),
    'cancelados', (select count(*) from ags where status = 'cancelado'),
    'clientes_atendidos', (select count(*) from atendidos),
    'clientes_retorno', (select n from retornou),
    'clientes_novos', (select count(*) from novos),
    'origem_novos', coalesce((select jsonb_object_agg(coalesce(origem, 'nao_informado'), n) from (select origem, count(*) n from novos group by 1) o), '{}'::jsonb),
    'rebook', (select jsonb_build_object('sim', sim, 'total', total) from rebook),
    'ocupacao', (select jsonb_build_object('disponivel', coalesce(sum(disponivel), 0), 'ocupado', coalesce(sum(ocupado), 0)) from por_prof),
    'online', (select count(*) from ags where origem = 'online'), 'whatsapp', (select count(*) from ags where origem = 'whatsapp'),
    'profissionais', coalesce((select jsonb_agg(jsonb_build_object('id', p.user_id, 'nome', p.nome, 'disponivel', p.disponivel, 'ocupado', p.ocupado,
        'receita', coalesce(r.receita, 0), 'atendimentos', coalesce(r.atendimentos, 0), 'comissao', coalesce(c.v, 0)) order by coalesce(r.receita, 0) desc)
      from por_prof p left join receita_prof r on r.profissional_id = p.user_id left join comissao_prof c on c.profissional_id = p.user_id), '[]'::jsonb),
    'por_dia', coalesce((select jsonb_object_agg(dia, v) from por_dia), '{}'::jsonb),
    'top_servicos', coalesce((select jsonb_agg(jsonb_build_object('nome', descricao, 'n', n, 'v', v)) from top_servicos), '[]'::jsonb)
  ) into r;
  return r;
end
$$;

-- Clientes que passaram do tempo de voltar: sem horário futuro e com a última visita há mais de 1,5 vez o intervalo habitual
-- (ou mais de 60 dias, para quem veio uma vez só). É a lista para chamar no WhatsApp.
create function clientes_sumidos(p_limite int default 30) returns table (
  cliente_id uuid, nome text, telefone text, ultima date, visitas int, intervalo_dias int, dias_sem_vir int
)
language sql stable security definer set search_path = public, pg_temp as
$$
  with v as (
    select a.cliente_id, count(*)::int n, min(a.inicio) primeira, max(a.inicio) ultima
    from agendamentos a where a.salao_id = meu_salao() and a.status = 'concluido' group by 1
  )
  select c.id, c.nome, c.telefone, (v.ultima at time zone s.fuso)::date, v.n,
    case when v.n > 1 then round(extract(epoch from v.ultima - v.primeira) / 86400 / (v.n - 1))::int end,
    floor(extract(epoch from now() - v.ultima) / 86400)::int
  from v join clientes c on c.id = v.cliente_id join saloes s on s.id = c.salao_id
  where meu_papel() in ('admin', 'recepcao') and c.recusou_lembretes_em is null
    and not exists (select 1 from agendamentos f where f.cliente_id = c.id and f.inicio > now() and f.status in ('agendado', 'confirmado'))
    and now() - v.ultima > case when v.n > 1 then greatest((v.ultima - v.primeira) / (v.n - 1) * 1.5, interval '21 days') else interval '60 days' end
    and now() - v.ultima < interval '400 days'
  order by v.n desc, v.ultima desc
  limit least(greatest(p_limite, 1), 200)
$$;

revoke all on function painel(date, date), clientes_sumidos(int) from public, anon;
grant execute on function painel(date, date), clientes_sumidos(int) to authenticated;
-- Belezando · correções da revisão de 31/10/2026 (comanda, comissão, sinal, união de cadastros e link público).

-- ───────────── 1) Unir cadastros com comanda fechada e sem perder o aceite da política ─────────────
create or replace function unir_clientes(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  a clientes; b clientes;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção unem cadastros' using errcode = '42501'; end if;
  if p_manter = p_remover then raise exception 'mesmo cadastro' using errcode = '22023'; end if;
  select * into a from clientes where id = p_manter and salao_id = v_salao for update;
  select * into b from clientes where id = p_remover and salao_id = v_salao for update;
  if a.id is null or b.id is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update agendamentos set cliente_id = a.id where cliente_id = b.id;
  -- comandas fechadas também mudam de dono (só o cliente; valores continuam travados)
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', '', true);
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update aceites_politica set cliente_id = a.id where cliente_id = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;

-- ───────────── 2) Sinal: crédito da cliente usado em qualquer comanda dela, e devolvido se o pagamento sair ─────────────
alter table sinais drop constraint sinais_status_check;
alter table sinais add constraint sinais_status_check check (status in ('pendente', 'pago', 'expirado', 'cancelado', 'credito', 'devolvido', 'usado'));
alter table sinais add column comanda_pagamento_id uuid;
create index on sinais (comanda_pagamento_id);

drop function usar_sinal(uuid);

-- Lança na comanda o sinal pago (ou crédito) mais antigo da cliente dela. O sinal só vira "usado" junto com o pagamento.
create function usar_credito_sinal(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  x sinais;
  v_pag uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta';
  if c.id is null or c.cliente_id is null then return 0; end if;
  select s.* into x from sinais s join agendamentos a on a.id = s.agendamento_id
  where s.salao_id = c.salao_id and a.cliente_id = c.cliente_id and s.status in ('pago', 'credito')
  order by s.pago_em nulls last, s.criado_em limit 1 for update of s;
  if x.id is null then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'sinal', x.valor_centavos) returning id into v_pag;
  update sinais set status = 'usado', comanda_pagamento_id = v_pag where id = x.id;
  return x.valor_centavos;
end
$$;
revoke all on function usar_credito_sinal(uuid) from public, anon;
grant execute on function usar_credito_sinal(uuid) to authenticated;

-- Pagamento de sinal removido da comanda, ou comanda cancelada: o sinal volta a ser crédito da cliente.
create function devolver_sinal_pagamento() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update sinais set status = 'credito', comanda_pagamento_id = null where comanda_pagamento_id = old.id;
  return old;
end
$$;
create trigger devolve_sinal after delete on comanda_pagamentos for each row when (old.forma = 'sinal') execute function devolver_sinal_pagamento();

create function devolver_sinal_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update sinais set status = 'credito', comanda_pagamento_id = null
  where comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  return new;
end
$$;
create trigger devolve_sinal_cancelada after update of status on comandas for each row
  when (new.status = 'cancelada' and old.status is distinct from 'cancelada') execute function devolver_sinal_comanda();
revoke execute on function devolver_sinal_pagamento(), devolver_sinal_comanda() from public, anon, authenticated;

-- ───────────── 3) Comissão do assistente independente do profissional principal ─────────────
create or replace function gerar_comissoes(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  s saloes;
  i comanda_itens;
  r regras_comissao;
  v_total int; v_itens int; v_taxa numeric;
  v_bruto int; v_dia date;
  v_vinc vinculo; v_vinc_assist vinculo;

  -- base de um comissionado: desconta taxa e custo só se o salão escolheu e o vínculo permite (CLT nunca)
  v_taxa_item int; v_custo int; v_base int;
begin
  select * into c from comandas where id = p_comanda;
  select * into s from saloes where id = c.salao_id;
  delete from comissoes where comanda_id = p_comanda and fechamento_id is null;
  v_dia := (coalesce(c.fechada_em, now()) at time zone s.fuso)::date;
  select total into v_total from total_comanda(p_comanda);
  select coalesce(sum(preco_centavos * quantidade - desconto_centavos), 0) into v_itens from comanda_itens where comanda_id = p_comanda and tipo <> 'gorjeta';
  select coalesce(sum(valor_centavos * case forma
           when 'debito' then s.taxa_debito when 'pix' then s.taxa_pix
           when 'credito' then case when parcelas > 1 then s.taxa_credito_parcelado else s.taxa_credito end
           else 0 end / 100.0), 0)
    into v_taxa from comanda_pagamentos where comanda_id = p_comanda;

  for i in select * from comanda_itens where comanda_id = p_comanda order by criado_em loop
    if i.tipo = 'gorjeta' then
      insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, base_centavos, percentual, valor_centavos)
      values (c.salao_id, c.id, i.id, i.profissional_id, 'gorjeta', v_dia, i.descricao, i.preco_centavos, i.preco_centavos, 100, i.preco_centavos);
      continue;
    end if;
    v_bruto := i.preco_centavos * i.quantidade - i.desconto_centavos;
    if v_itens > 0 then v_bruto := v_bruto - round(c.desconto_centavos::numeric * v_bruto / v_itens)::int; end if;
    r := percentual_comissao(c.salao_id, i.tipo::text, i.profissional_id, i.servico_id);
    if r.id is null then continue; end if;

    if i.profissional_id is not null then
      select vinculo into v_vinc from membros where user_id = i.profissional_id and salao_id = c.salao_id;
      if v_vinc <> 'socio' then
        v_taxa_item := case when s.comissao_desconta_taxa and v_vinc <> 'clt' and v_total > 0 then round(v_taxa * v_bruto / v_total)::int else 0 end;
        v_custo := case when s.comissao_desconta_custo and v_vinc <> 'clt' and i.tipo = 'servico'
                        then i.quantidade * coalesce((select custo_produto_centavos from servicos where id = i.servico_id), 0) else 0 end;
        v_base := greatest(v_bruto - v_taxa_item - v_custo, 0);
        insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
        values (c.salao_id, c.id, i.id, i.profissional_id, case when i.tipo = 'produto' then 'vendedor' else 'profissional' end, v_dia, i.descricao,
                v_bruto, v_taxa_item, v_custo, v_base, r.percentual, round(v_base * r.percentual / 100)::int);
      end if;
    end if;

    if i.assistente_id is not null and r.assistente_percentual > 0 then
      select vinculo into v_vinc_assist from membros where user_id = i.assistente_id and salao_id = c.salao_id;
      if v_vinc_assist <> 'socio' then
        v_taxa_item := case when s.comissao_desconta_taxa and v_vinc_assist <> 'clt' and v_total > 0 then round(v_taxa * v_bruto / v_total)::int else 0 end;
        v_custo := case when s.comissao_desconta_custo and v_vinc_assist <> 'clt'
                        then i.quantidade * coalesce((select custo_produto_centavos from servicos where id = i.servico_id), 0) else 0 end;
        v_base := greatest(v_bruto - v_taxa_item - v_custo, 0);
        insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
        values (c.salao_id, c.id, i.id, i.assistente_id, 'assistente', v_dia, i.descricao || ' (assistente)',
                v_bruto, v_taxa_item, v_custo, v_base, r.assistente_percentual, round(v_base * r.assistente_percentual / 100)::int);
      end if;
    end if;
  end loop;
end
$$;

-- ───────────── 4) Vale maior que o período fica em aberto (não some) ─────────────
create or replace function pagar_profissional(p_prof uuid, p_inicio date, p_fim date, p_forma text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_com int; v_gor int; v_val int := 0;
  v_id uuid;
  x vales;
  v_quitar uuid[] := '{}';
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador registra pagamento' using errcode = '42501'; end if;
  if p_fim < p_inicio then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from membros where user_id = p_prof and salao_id = v_salao) then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
  select coalesce(sum(valor_centavos) filter (where papel <> 'gorjeta'), 0), coalesce(sum(valor_centavos) filter (where papel = 'gorjeta'), 0)
    into v_com, v_gor from comissoes
  where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  if v_com + v_gor = 0 then raise exception 'nada_a_pagar' using errcode = '22023'; end if;
  -- desconta os vales do mais antigo ao mais novo enquanto couberem; o que não couber fica para o próximo pagamento
  for x in select * from vales where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and data <= p_fim order by data, criado_em loop
    exit when v_val + x.valor_centavos > v_com + v_gor;
    v_val := v_val + x.valor_centavos;
    v_quitar := v_quitar || x.id;
  end loop;
  insert into fechamentos_comissao (salao_id, profissional_id, periodo_inicio, periodo_fim, comissoes_centavos, gorjetas_centavos, vales_centavos, pago_centavos, forma)
  values (v_salao, p_prof, p_inicio, p_fim, v_com, v_gor, v_val, v_com + v_gor - v_val, left(p_forma, 40)) returning id into v_id;
  update comissoes set fechamento_id = v_id where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  update vales set fechamento_id = v_id where id = any (v_quitar);
  return v_id;
end
$$;

-- ───────────── 6, 7 e 11) Link público: sinal só com meio de cobrança, nome digitado, aceite sem herdar cadastro alheio ─────────────
alter table aceites_politica add column nome_informado text check (length(nome_informado) <= 120);

create or replace function agendar_online(
  p_slug text, p_servico uuid, p_profissional uuid, p_inicio timestamptz,
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
begin
  select * into c from saloes where slug = lower(p_slug) and agendamento_online;
  if c.id is null then raise exception 'salao_indisponivel' using errcode = 'P0002'; end if;
  select * into v_srv from servicos where id = p_servico and salao_id = c.id and ativo and online;
  if v_srv.id is null or not exists (select 1 from membros where user_id = p_profissional and salao_id = c.id and ativo and papel in ('admin', 'profissional')) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_nome, ''))) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if not coalesce(p_aceite_contato, false) then raise exception 'consentimento obrigatório' using errcode = '22023'; end if;
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(c.id, p_profissional, p_inicio, v_srv.fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  -- Telefone já cadastrado: o horário entra nesse cadastro, mas o aceite de contato não é herdado de quem digitou
  -- (sem verificar o número, qualquer um poderia ligar lembretes no WhatsApp de outra pessoa).
  select id into v_cli from clientes where salao_id = c.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli is null then
    insert into clientes (salao_id, nome, telefone, consentimento_em, origem) values (c.id, left(trim(p_nome), 120), v_tel, now(), 'outro') returning id into v_cli;
  end if;

  v_mp := exists (select 1 from pagamentos_contas where salao_id = c.id and mp_access_token is not null);
  v_sinal := case when c.pix_chave is not null or v_mp then round(coalesce(v_srv.preco_centavos, 0) * v_srv.sinal_percentual / 100.0)::int else 0 end;
  begin
    insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fases, origem, status)
    values (c.id, v_cli, p_profissional, p_servico, p_inicio, v_srv.fases, 'online', case when v_sinal > 0 then 'agendado' else 'confirmado' end::status_agendamento)
    returning * into v_ag;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;

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

-- A página do horário mostra o nome digitado, nunca o do cadastro que tinha aquele telefone.
create or replace function horario_publico(p_token uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object(
    'id', a.id, 'inicio', a.inicio, 'fim', a.fim, 'status', a.status, 'servico', s.nome, 'profissional', m.nome,
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

-- Cancelado pela cliente: sinal pendente vira "cancelado" (diferente de expirado), pago vira crédito.
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
  update agendamentos set status = 'cancelado' where id = a.id;
  update sinais set status = case status when 'pago' then 'credito' when 'pendente' then 'cancelado' else status end where agendamento_id = a.id;
  return 'cancelado';
end
$$;

-- O modo passa a ser o que de fato foi gerado (se o Mercado Pago falhar e cair no Pix da chave, a página não promete confirmação automática).
drop function registrar_cobranca_sinal(uuid, text, text, text);
create function registrar_cobranca_sinal(p_agendamento uuid, p_txid text, p_copia_cola text, p_mp_payment_id text, p_modo text) returns void
language sql security definer set search_path = public, pg_temp as
$$
  update sinais set txid = left(p_txid, 35), copia_cola = left(p_copia_cola, 600), mp_payment_id = coalesce(p_mp_payment_id, mp_payment_id),
    modo = case when p_modo in ('pix_manual', 'mercadopago') then p_modo else modo end
  where agendamento_id = p_agendamento and status = 'pendente'
$$;

-- Webhook preso ao salão; pagamento atrasado de quem cancelou vira crédito em vez de ressuscitar o horário.
drop function sinal_pago_mp(text, int);
create function sinal_pago_mp(p_payment_id text, p_valor_centavos int, p_salao uuid) returns boolean
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
    update agendamentos set status = 'confirmado' where id = x.agendamento_id and status in ('agendado', 'cancelado');
  exception when exclusion_violation then
    update sinais set status = 'credito' where id = x.id;
  end;
  return true;
end
$$;

revoke all on function registrar_cobranca_sinal(uuid, text, text, text, text), sinal_pago_mp(text, int, uuid) from public, anon, authenticated;
grant execute on function registrar_cobranca_sinal(uuid, text, text, text, text), sinal_pago_mp(text, int, uuid) to service_role;

-- ───────────── 12) Vale tirado do caixa: vale e retirada juntos ou nenhum ─────────────
create function vale_do_caixa(p_caixa uuid, p_prof uuid, p_valor int, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_nome text;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção mexem no caixa' using errcode = '42501'; end if;
  if not exists (select 1 from caixas where id = p_caixa and salao_id = meu_salao() and fechado_em is null) then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  select nome into v_nome from membros where user_id = p_prof and salao_id = meu_salao();
  if v_nome is null then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
  insert into vales (salao_id, profissional_id, valor_centavos, motivo) values (meu_salao(), p_prof, p_valor, coalesce(nullif(trim(p_motivo), ''), 'Retirado do caixa'));
  insert into caixa_movimentos (salao_id, caixa_id, tipo, valor_centavos, motivo)
  values (meu_salao(), p_caixa, 'sangria', p_valor, left('Vale para ' || v_nome || coalesce(': ' || nullif(trim(p_motivo), ''), ''), 200));
end
$$;
revoke all on function vale_do_caixa(uuid, uuid, int, text) from public, anon;
grant execute on function vale_do_caixa(uuid, uuid, int, text) to authenticated;
-- Belezando · retorno automático e lista de espera, pelo WhatsApp.
-- Retorno: passou o tempo de voltar daquele serviço (ex.: 30 dias do corte) e a cliente não marcou? Ela recebe um convite com o link.
-- Lista de espera: quando um horário vaga, quem estava esperando aquele serviço naquele dia recebe o aviso; quem marcar primeiro fica.

alter table servicos add column retorno_dias int check (retorno_dias between 7 and 365);
grant update (retorno_dias) on servicos to authenticated;
update servicos set retorno_dias = case nome when 'Corte feminino' then 45 when 'Corte masculino' then 30 when 'Coloração' then 35
  when 'Hidratação' then 21 when 'Manicure' then 14 when 'Pedicure' then 21 else null end;

alter table saloes add column retorno_ativo boolean not null default false;   -- convite é mensagem de marketing na Meta (tem custo)
alter table saloes add column retorno_hora time not null default '10:00' check (retorno_hora between '08:00' and '20:00');
alter table saloes add column espera_ativa boolean not null default true;
grant update (retorno_ativo, retorno_hora, espera_ativa) on saloes to authenticated;

-- Retorno sugerido dos serviços de um salão novo.
create or replace function criar_salao(p_nome text, p_slug text, p_nome_usuario text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_id uuid;
  t constant text := 'trabalho';
  p constant text := 'pausa';
begin
  if auth.uid() is null then raise exception 'não autenticado' using errcode = '28000'; end if;
  if exists (select 1 from membros where user_id = auth.uid()) then raise exception 'usuário já pertence a um salão' using errcode = '23505'; end if;
  insert into saloes (nome, slug) values (trim(p_nome), lower(trim(p_slug))) returning id into v_id;
  insert into membros (user_id, salao_id, papel, nome) values (auth.uid(), v_id, 'admin', trim(p_nome_usuario));
  insert into servicos (salao_id, nome, duracao_min, fases, retorno_dias) values
    (v_id, 'Corte feminino', 60, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 60)), 45),
    (v_id, 'Corte masculino', 30, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 30)), 30),
    (v_id, 'Escova', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45)), null),
    (v_id, 'Coloração', 120, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 40), jsonb_build_object('tipo', p, 'min', 40), jsonb_build_object('tipo', t, 'min', 40)), 35),
    (v_id, 'Hidratação', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 15), jsonb_build_object('tipo', p, 'min', 20), jsonb_build_object('tipo', t, 'min', 10)), 21),
    (v_id, 'Manicure', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45)), 14),
    (v_id, 'Pedicure', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45)), 21);
  return v_id;
end
$$;

-- ───────────── lista de espera ─────────────

create table lista_espera (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  servico_id uuid not null,
  profissional_id uuid,                 -- vazio = qualquer profissional
  data_de date not null,
  data_ate date not null,
  periodo text not null default 'qualquer' check (periodo in ('qualquer', 'manha', 'tarde', 'noite')),
  estado text not null default 'aguardando' check (estado in ('aguardando', 'avisado', 'marcado', 'cancelado')),
  observacao text check (length(observacao) <= 300),
  avisado_em timestamptz,
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  check (data_ate >= data_de and data_ate - data_de <= 90),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade,
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id) on delete cascade
);
create index on lista_espera (salao_id, estado, data_de);
create index on lista_espera (cliente_id);

alter table lista_espera enable row level security;
create policy espera_ler on lista_espera for select to authenticated using (salao_id = meu_salao());
create policy espera_criar on lista_espera for insert to authenticated with check (salao_id = meu_salao());
create policy espera_editar on lista_espera for update to authenticated using (salao_id = meu_salao()) with check (salao_id = meu_salao());
revoke all on lista_espera from anon, authenticated;
grant select on lista_espera to authenticated;
grant insert (cliente_id, servico_id, profissional_id, data_de, data_ate, periodo, observacao) on lista_espera to authenticated;
grant update (estado) on lista_espera to authenticated;
create trigger aud_espera after insert or update on lista_espera for each row execute function auditar();

-- ───────────── fila de avisos (retorno e vaga) ─────────────

create table avisos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  tipo text not null check (tipo in ('retorno', 'vaga')),
  chave text not null,                  -- impede o mesmo aviso duas vezes (ex.: retorno daquela visita)
  dados jsonb not null default '{}',
  enviar_em timestamptz not null default now(),
  estado text not null default 'pendente' check (estado in ('pendente', 'enviando', 'enviado', 'falhou', 'cancelado')),
  tentativas int not null default 0,
  reservado_em timestamptz,
  wa_msg_id text,
  erro text check (length(erro) <= 500),
  enviado_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (salao_id, chave),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on avisos (enviar_em) where estado in ('pendente', 'enviando');
create index on avisos (cliente_id);
alter table avisos enable row level security;
create policy avisos_ler on avisos for select to authenticated using (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
revoke all on avisos from anon, authenticated;
grant select on avisos to authenticated;

-- Pode receber mensagem automática: tem telefone, aceitou e não pediu PARAR.
create function cliente_contatavel(c clientes) returns boolean
language sql immutable set search_path = public, pg_temp as
$$ select c.telefone is not null and c.consentimento_em is not null and c.recusou_lembretes_em is null $$;
revoke all on function cliente_contatavel(clientes) from public, anon;

-- Quando um horário futuro é cancelado, avisa até 3 pessoas da lista de espera que querem aquele serviço naquele dia e período.
create function avisar_lista_espera() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_local timestamp;
  v_periodo text;
  e record;
  n int := 0;
begin
  if new.status <> 'cancelado' or old.status = 'cancelado' or new.inicio < now() + interval '1 hour' then return new; end if;
  select * into s from saloes where id = new.salao_id;
  if not s.espera_ativa then return new; end if;
  v_local := new.inicio at time zone s.fuso;
  v_periodo := case when v_local::time < '12:00' then 'manha' when v_local::time < '18:00' then 'tarde' else 'noite' end;
  for e in
    select l.*, c.nome cliente_nome from lista_espera l join clientes c on c.id = l.cliente_id
    where l.salao_id = new.salao_id and l.estado = 'aguardando' and l.servico_id = new.servico_id
      and v_local::date between l.data_de and l.data_ate
      and (l.periodo = 'qualquer' or l.periodo = v_periodo)
      and (l.profissional_id is null or l.profissional_id = new.profissional_id)
      and l.cliente_id <> new.cliente_id and cliente_contatavel(c)
    order by l.criado_em limit 3
  loop
    insert into avisos (salao_id, cliente_id, tipo, chave, dados)
    values (new.salao_id, e.cliente_id, 'vaga', 'vaga:' || e.id || ':' || new.id,
            jsonb_build_object('servico_id', new.servico_id, 'profissional_id', new.profissional_id, 'inicio', new.inicio, 'espera_id', e.id))
    on conflict (salao_id, chave) do nothing;
    update lista_espera set estado = 'avisado', avisado_em = now() where id = e.id;
    n := n + 1;
  end loop;
  return new;
end
$$;
create trigger espera_vaga after update of status on agendamentos for each row execute function avisar_lista_espera();

-- Quem estava na espera e marcou aquele serviço sai da lista sozinha.
create function sair_da_espera() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update lista_espera set estado = 'marcado'
  where cliente_id = new.cliente_id and servico_id = new.servico_id and estado in ('aguardando', 'avisado')
    and (new.inicio at time zone (select fuso from saloes where id = new.salao_id))::date between data_de and data_ate;
  return new;
end
$$;
create trigger espera_marcou after insert on agendamentos for each row execute function sair_da_espera();
revoke execute on function avisar_lista_espera(), sair_da_espera() from public, anon, authenticated;

-- Programa os convites de retorno: a última visita da cliente com aquele serviço passou do prazo e não há nada marcado.
-- Um convite por visita, no máximo um a cada 30 dias por cliente, sempre no horário do salão.
create function programar_retornos() returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  n int;
begin
  with ultima as (
    select distinct on (a.cliente_id) a.id, a.salao_id, a.cliente_id, a.inicio, s.nome servico, s.retorno_dias, a.servico_id
    from agendamentos a join servicos s on s.id = a.servico_id
    where a.status = 'concluido' and s.retorno_dias is not null and a.inicio > now() - interval '400 days'
    order by a.cliente_id, a.inicio desc
  ), alvo as (
    select u.*, sa.fuso, sa.retorno_hora from ultima u
    join saloes sa on sa.id = u.salao_id and sa.retorno_ativo
    join clientes c on c.id = u.cliente_id and cliente_contatavel(c)
    where u.inicio + make_interval(days => u.retorno_dias) <= now()
      and u.inicio + make_interval(days => u.retorno_dias * 2) > now()      -- muito atrasada vira "cliente sumida", não convite automático
      and not exists (select 1 from agendamentos f where f.cliente_id = u.cliente_id and f.inicio > now() and f.status in ('agendado', 'confirmado'))
      and not exists (select 1 from avisos v where v.cliente_id = u.cliente_id and v.tipo = 'retorno' and v.criado_em > now() - interval '30 days')
  )
  insert into avisos (salao_id, cliente_id, tipo, chave, dados, enviar_em)
  select salao_id, cliente_id, 'retorno', 'retorno:' || id,
    jsonb_build_object('servico', servico, 'servico_id', servico_id, 'dias', floor(extract(epoch from now() - inicio) / 86400)::int),
    -- próximo horário de envio do salão (hoje, se ainda não passou)
    case when (now() at time zone fuso)::time < retorno_hora then ((now() at time zone fuso)::date + retorno_hora) at time zone fuso
         else (((now() at time zone fuso)::date + 1) + retorno_hora) at time zone fuso end
  from alvo
  on conflict (salao_id, chave) do nothing;
  get diagnostics n = row_count;
  return n;
end
$$;

-- Entrega os avisos da hora para o servidor enviar (cada aviso a uma execução só).
create function reservar_avisos(p_limite int) returns table (
  id uuid, salao_id uuid, tipo text, dados jsonb, wa_id text, cliente_nome text, salao_nome text, slug text, fuso text
)
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update avisos a set estado = 'pendente', tentativas = a.tentativas + 1 where a.estado = 'enviando' and a.reservado_em < now() - interval '15 minutes';
  -- vaga velha não serve mais; cliente que marcou ou pediu PARAR não recebe
  update avisos a set estado = 'cancelado', erro = 'passou da hora' where a.estado = 'pendente' and a.tipo = 'vaga' and a.criado_em < now() - interval '3 hours';
  update avisos a set estado = 'cancelado', erro = 'cliente não pode receber ou já marcou'
  where a.estado = 'pendente' and a.enviar_em <= now()
    and (not exists (select 1 from clientes c where c.id = a.cliente_id and cliente_contatavel(c))
         or (a.tipo = 'retorno' and exists (select 1 from agendamentos f where f.cliente_id = a.cliente_id and f.inicio > now() and f.status in ('agendado', 'confirmado'))));
  return query
  with alvo as (
    select v.id from avisos v where v.estado = 'pendente' and v.enviar_em <= now() and v.tentativas < 3
    order by v.enviar_em limit p_limite for update skip locked
  ), marcado as (
    update avisos v set estado = 'enviando', reservado_em = now() from alvo where v.id = alvo.id returning v.*
  )
  select m.id, m.salao_id, m.tipo, m.dados,
    coalesce((select cv.wa_id from conversas cv where cv.salao_id = m.salao_id and cv.cliente_id = c.id order by cv.ultima_msg_em desc limit 1), '55' || tel_nacional(c.telefone)),
    c.nome, s.nome, s.slug, s.fuso
  from marcado m join clientes c on c.id = m.cliente_id join saloes s on s.id = m.salao_id;
end
$$;

create function concluir_aviso(p_id uuid, p_ok boolean, p_wa_msg_id text, p_erro text, p_definitivo boolean default false) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if p_ok then
    update avisos set estado = 'enviado', wa_msg_id = p_wa_msg_id, enviado_em = now(), reservado_em = null, tentativas = tentativas + 1, erro = null
    where id = p_id and estado = 'enviando';
  else
    update avisos set tentativas = tentativas + 1, reservado_em = null, erro = left(p_erro, 500),
      estado = case when p_definitivo or tentativas + 1 >= 3 then 'falhou' else 'pendente' end,
      enviar_em = case when p_definitivo or tentativas + 1 >= 3 then enviar_em else now() + make_interval(mins => 10 * (tentativas + 1)) end
    where id = p_id and estado = 'enviando';
  end if;
end
$$;

revoke all on function programar_retornos(), reservar_avisos(int), concluir_aviso(uuid, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function programar_retornos(), reservar_avisos(int), concluir_aviso(uuid, boolean, text, text, boolean) to service_role;
-- Belezando · estoque: produto de revenda (sai na venda) e de uso interno (sai sozinho pelo consumo de cada serviço).
-- O saldo fica na unidade do produto (unidade, grama ou mililitro). Entrada é por embalagem: 2 tubos de 60 g = +120 g.

alter table produtos add column tipo text not null default 'revenda' check (tipo in ('revenda', 'uso', 'ambos'));
alter table produtos add column unidade text not null default 'un' check (unidade in ('un', 'g', 'ml'));
alter table produtos add column conteudo numeric(10,2) not null default 1 check (conteudo > 0);       -- quanto tem numa embalagem
alter table produtos add column custo_centavos int not null default 0 check (custo_centavos between 0 and 10000000);   -- custo da embalagem
alter table produtos add column estoque numeric(12,2) not null default 0;
alter table produtos add column estoque_minimo numeric(12,2) not null default 0 check (estoque_minimo >= 0);
-- o saldo só muda por movimento
revoke update on produtos from authenticated;
grant update (nome, preco_centavos, ativo, tipo, unidade, conteudo, custo_centavos, estoque_minimo) on produtos to authenticated;

-- Quanto de cada produto um serviço consome (ex.: Coloração usa 60 g de tinta e 90 ml de oxidante).
create table servico_insumos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  servico_id uuid not null,
  produto_id uuid not null,
  quantidade numeric(10,2) not null check (quantidade > 0),
  unique (servico_id, produto_id),
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade,
  foreign key (produto_id, salao_id) references produtos (id, salao_id) on delete cascade
);

create table movimentos_estoque (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  produto_id uuid not null,
  tipo text not null check (tipo in ('entrada', 'venda', 'uso', 'ajuste', 'perda', 'estorno')),
  quantidade numeric(12,2) not null check (quantidade <> 0),     -- positivo entra, negativo sai
  custo_centavos int check (custo_centavos >= 0),
  comanda_id uuid,
  motivo text check (length(motivo) <= 200),
  feito_por uuid default auth.uid(),
  em timestamptz not null default now(),
  foreign key (produto_id, salao_id) references produtos (id, salao_id) on delete cascade,
  foreign key (comanda_id, salao_id) references comandas (id, salao_id)
);
create index on movimentos_estoque (produto_id, em desc);
create index on movimentos_estoque (comanda_id);

create function aplicar_movimento() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update produtos set estoque = estoque + new.quantidade where id = new.produto_id;
  return new;
end
$$;
create trigger aplica_movimento after insert on movimentos_estoque for each row execute function aplicar_movimento();

-- Comanda fechada: sai o que foi vendido e o que os serviços consumiram. Reaberta: tudo volta (estorno).
create function baixar_estoque_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, comanda_id, feito_por)
    select i.salao_id, i.produto_id, 'venda', -(i.quantidade * case p.unidade when 'un' then 1 else p.conteudo end), new.id, auth.uid()
    from comanda_itens i join produtos p on p.id = i.produto_id
    where i.comanda_id = new.id and i.tipo = 'produto';
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, comanda_id, feito_por)
    select i.salao_id, si.produto_id, 'uso', -sum(si.quantidade * i.quantidade), new.id, auth.uid()
    from comanda_itens i join servico_insumos si on si.servico_id = i.servico_id
    where i.comanda_id = new.id and i.tipo = 'servico'
    group by i.salao_id, si.produto_id;
  elsif new.status = 'aberta' and old.status = 'fechada' then
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, comanda_id, motivo, feito_por)
    select salao_id, produto_id, 'estorno', -sum(quantidade), new.id, 'comanda reaberta', auth.uid()
    from movimentos_estoque where comanda_id = new.id group by salao_id, produto_id having sum(quantidade) <> 0;
  end if;
  return new;
end
$$;
create trigger estoque_comanda after update of status on comandas for each row execute function baixar_estoque_comanda();
revoke execute on function aplicar_movimento(), baixar_estoque_comanda() from public, anon, authenticated;

-- Contagem física: o administrador ou a recepção informa quanto tem de verdade e o sistema lança a diferença.
create function ajustar_estoque(p_produto uuid, p_contado numeric, p_motivo text) returns numeric
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_atual numeric;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção ajustam estoque' using errcode = '42501'; end if;
  if p_contado < 0 then raise exception 'contagem negativa' using errcode = '22023'; end if;
  select estoque into v_atual from produtos where id = p_produto and salao_id = meu_salao() for update;
  if v_atual is null then raise exception 'produto não encontrado' using errcode = 'P0002'; end if;
  if p_contado <> v_atual then
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, motivo) values (meu_salao(), p_produto, 'ajuste', p_contado - v_atual, left(coalesce(p_motivo, 'contagem'), 200));
  end if;
  return p_contado - v_atual;
end
$$;
revoke all on function ajustar_estoque(uuid, numeric, text) from public, anon;
grant execute on function ajustar_estoque(uuid, numeric, text) to authenticated;

alter table servico_insumos enable row level security;
alter table movimentos_estoque enable row level security;
create policy insumos_ler on servico_insumos for select to authenticated using (salao_id = meu_salao());
create policy insumos_escrever on servico_insumos for all to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');
create policy mov_estoque_ler on movimentos_estoque for select to authenticated using (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
-- pela API só entra mercadoria e registra perda; venda, uso, estorno e ajuste vêm do sistema
create policy mov_estoque_criar on movimentos_estoque for insert to authenticated
  with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao')
              and ((tipo = 'entrada' and quantidade > 0) or (tipo = 'perda' and quantidade < 0)) and comanda_id is null);
revoke all on servico_insumos, movimentos_estoque from anon, authenticated;
grant select, insert, update, delete on servico_insumos to authenticated;
grant select on movimentos_estoque to authenticated;
grant insert (produto_id, tipo, quantidade, custo_centavos, motivo) on movimentos_estoque to authenticated;
create trigger aud_insumos after insert or update or delete on servico_insumos for each row execute function auditar();

-- Produto comprado para uso interno não precisa de preço de venda.
alter table produtos drop constraint if exists produtos_preco_centavos_check;
alter table produtos add constraint produtos_preco_centavos_check check (preco_centavos between 0 and 10000000);
-- Belezando · pacotes, clube de assinatura e cashback.
-- Pacote: a cliente paga antes por várias sessões (ex.: 10 escovas) e vai usando; clube: o mesmo, renovado todo mês.
-- O serviço usado do pacote entra na comanda com o valor proporcional e é "pago" com o pacote: a comissão sai normalmente
-- e o faturamento não conta duas vezes (o dinheiro entrou na venda do pacote).
-- Cashback: parte do que a cliente gastou volta como crédito para a próxima visita, com validade.

alter type tipo_item add value if not exists 'pacote';
alter type forma_pagamento add value if not exists 'cashback';

create table pacotes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 120),
  tipo text not null default 'pacote' check (tipo in ('pacote', 'clube')),
  preco_centavos int not null check (preco_centavos between 1 and 10000000),
  validade_dias int not null default 180 check (validade_dias between 7 and 730),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (id, salao_id)
);
create table pacote_itens (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  pacote_id uuid not null,
  servico_id uuid not null,
  quantidade int not null check (quantidade between 1 and 100),
  unique (pacote_id, servico_id),
  foreign key (pacote_id, salao_id) references pacotes (id, salao_id) on delete cascade,
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade
);

alter table comanda_itens add column pacote_id uuid;
alter table comanda_itens add constraint item_pacote_fk foreign key (pacote_id, salao_id) references pacotes (id, salao_id);
alter table comanda_itens add constraint item_pacote_ok check (tipo::text <> 'pacote' or (pacote_id is not null and quantidade = 1));
grant insert (pacote_id) on comanda_itens to authenticated;

-- Pacote comprado por uma cliente, com o saldo de cada serviço.
create table pacotes_cliente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  pacote_id uuid not null,
  nome text not null,
  tipo text not null,
  comanda_id uuid not null,
  comprado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  estado text not null default 'ativo' check (estado in ('ativo', 'cancelado')),
  unique (id, salao_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (pacote_id, salao_id) references pacotes (id, salao_id),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id)
);
create index on pacotes_cliente (cliente_id);
create table pacote_saldos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  pacote_cliente_id uuid not null,
  servico_id uuid not null,
  total int not null check (total > 0),
  usado int not null default 0 check (usado >= 0),
  valor_unitario_centavos int not null check (valor_unitario_centavos >= 0),
  check (usado <= total),
  unique (pacote_cliente_id, servico_id),
  foreign key (pacote_cliente_id, salao_id) references pacotes_cliente (id, salao_id) on delete cascade
);
create table pacote_usos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  saldo_id uuid not null references pacote_saldos (id) on delete cascade,
  comanda_item_id uuid not null unique,
  comanda_pagamento_id uuid not null unique,
  preco_original_centavos int not null,
  desconto_original_centavos int not null,
  criado_em timestamptz not null default now()
);

-- ───────────── cashback ─────────────
alter table saloes add column cashback_percentual numeric(5,2) not null default 0 check (cashback_percentual between 0 and 30);
alter table saloes add column cashback_validade_dias int not null default 90 check (cashback_validade_dias between 7 and 365);
grant update (cashback_percentual, cashback_validade_dias) on saloes to authenticated;

create table cashback_movimentos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  tipo text not null check (tipo in ('credito', 'uso')),
  valor_centavos int not null check (valor_centavos <> 0),
  comanda_id uuid,
  comanda_pagamento_id uuid unique,
  expira_em timestamptz,
  criado_em timestamptz not null default now(),
  check ((tipo = 'credito') = (valor_centavos > 0 and expira_em is not null)),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on cashback_movimentos (cliente_id, criado_em);

-- Saldo: créditos ainda válidos menos o que foi usado desde o crédito válido mais antigo.
create function saldo_cashback(p_cliente uuid) returns int
language sql stable security definer set search_path = public, pg_temp as
$$
  with validos as (select coalesce(sum(valor_centavos), 0) v, min(criado_em) desde from cashback_movimentos
                   where cliente_id = p_cliente and tipo = 'credito' and expira_em > now() and salao_id = meu_salao())
  select greatest(0, v + coalesce((select sum(valor_centavos) from cashback_movimentos
                                   where cliente_id = p_cliente and tipo = 'uso' and salao_id = meu_salao() and criado_em >= desde), 0))::int
  from validos
$$;

-- ───────────── ao fechar e reabrir a comanda ─────────────
create function pacotes_e_cashback_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  i comanda_itens;
  p pacotes;
  v_pc uuid;
  v_soma numeric;
  v_base int;
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    select * into s from saloes where id = new.salao_id;
    if exists (select 1 from comanda_itens where comanda_id = new.id and tipo::text = 'pacote') and new.cliente_id is null then
      raise exception 'pacote_sem_cliente' using errcode = '22023';
    end if;
    -- venda de pacote: nasce o saldo, com o valor de cada sessão proporcional ao preço de tabela
    for i in select * from comanda_itens where comanda_id = new.id and tipo::text = 'pacote' loop
      select * into p from pacotes where id = i.pacote_id;
      insert into pacotes_cliente (salao_id, cliente_id, pacote_id, nome, tipo, comanda_id, expira_em)
      values (new.salao_id, new.cliente_id, p.id, p.nome, p.tipo, new.id, now() + make_interval(days => p.validade_dias)) returning id into v_pc;
      select sum(greatest(sv.preco_centavos, 1) * pi.quantidade) into v_soma from pacote_itens pi join servicos sv on sv.id = pi.servico_id where pi.pacote_id = p.id;
      insert into pacote_saldos (salao_id, pacote_cliente_id, servico_id, total, valor_unitario_centavos)
      select new.salao_id, v_pc, pi.servico_id, pi.quantidade,
             round((i.preco_centavos - i.desconto_centavos) * greatest(sv.preco_centavos, 1)::numeric / nullif(v_soma, 0))::int
      from pacote_itens pi join servicos sv on sv.id = pi.servico_id where pi.pacote_id = p.id;
    end loop;
    -- cashback sobre o que foi pago em dinheiro de verdade (sem gorjeta, pacote usado, cashback e sinal)
    if s.cashback_percentual > 0 and new.cliente_id is not null then
      select coalesce(sum(valor_centavos), 0) into v_base from comanda_pagamentos
      where comanda_id = new.id and forma::text not in ('pacote', 'cashback');
      v_base := v_base - coalesce((select sum(preco_centavos) from comanda_itens where comanda_id = new.id and tipo = 'gorjeta'), 0);
      if round(v_base * s.cashback_percentual / 100) >= 1 then
        insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, expira_em)
        values (new.salao_id, new.cliente_id, 'credito', round(v_base * s.cashback_percentual / 100)::int, new.id, now() + make_interval(days => s.cashback_validade_dias));
      end if;
    end if;
  elsif new.status = 'aberta' and old.status = 'fechada' then
    if exists (select 1 from pacotes_cliente pc join pacote_saldos ps on ps.pacote_cliente_id = pc.id where pc.comanda_id = new.id and ps.usado > 0) then
      raise exception 'pacote_ja_usado' using errcode = '55000';
    end if;
    delete from pacotes_cliente where comanda_id = new.id;
    delete from cashback_movimentos where comanda_id = new.id and tipo = 'credito';
  end if;
  return new;
end
$$;
create trigger pacotes_cashback after update of status on comandas for each row execute function pacotes_e_cashback_comanda();

-- Usa o pacote da cliente nos serviços desta comanda que ele cobre. O item passa a valer a sessão do pacote
-- (é sobre esse valor que sai a comissão) e é pago com o pacote; se o pagamento sair, o preço original volta.
create function usar_pacote(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  i comanda_itens;
  sd pacote_saldos;
  v_pag uuid;
  n int := 0;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta';
  if c.id is null or c.cliente_id is null then return 0; end if;
  for i in select * from comanda_itens it where it.comanda_id = c.id and it.tipo = 'servico' and it.quantidade = 1
             and not exists (select 1 from pacote_usos u where u.comanda_item_id = it.id) loop
    sd := null;
    select ps.* into sd from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id
    where pc.cliente_id = c.cliente_id and pc.estado = 'ativo' and pc.expira_em > now() and ps.servico_id = i.servico_id and ps.usado < ps.total
    order by pc.expira_em limit 1 for update of ps;
    continue when sd.id is null;
    update comanda_itens set preco_centavos = sd.valor_unitario_centavos, desconto_centavos = 0 where id = i.id;
    if sd.valor_unitario_centavos > 0 then
      insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'pacote', sd.valor_unitario_centavos) returning id into v_pag;
    else
      v_pag := gen_random_uuid();
    end if;
    update pacote_saldos set usado = usado + 1 where id = sd.id;
    insert into pacote_usos (salao_id, saldo_id, comanda_item_id, comanda_pagamento_id, preco_original_centavos, desconto_original_centavos)
    values (c.salao_id, sd.id, i.id, v_pag, i.preco_centavos, i.desconto_centavos);
    n := n + 1;
  end loop;
  return n;
end
$$;

-- Usa o cashback da cliente até o que falta pagar.
create function usar_cashback(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v int;
  v_pag uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta';
  if c.id is null or c.cliente_id is null then return 0; end if;
  select * into t from total_comanda(p_comanda);
  v := least(saldo_cashback(c.cliente_id), t.total - t.pago);
  if v <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'cashback', v) returning id into v_pag;
  insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, comanda_pagamento_id) values (c.salao_id, c.cliente_id, 'uso', -v, c.id, v_pag);
  return v;
end
$$;

-- Pagamento de pacote ou cashback removido, ou comanda cancelada: a sessão e o cashback voltam.
create function devolver_pacote_cashback() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  u pacote_usos;
begin
  select * into u from pacote_usos where comanda_pagamento_id = old.id;
  if u.id is not null then
    update pacote_saldos set usado = usado - 1 where id = u.saldo_id;
    update comanda_itens set preco_centavos = u.preco_original_centavos, desconto_centavos = u.desconto_original_centavos where id = u.comanda_item_id;
    delete from pacote_usos where id = u.id;
  end if;
  delete from cashback_movimentos where comanda_pagamento_id = old.id;
  return old;
end
$$;
create trigger devolve_pacote_cashback after delete on comanda_pagamentos for each row
  when (old.forma::text in ('pacote', 'cashback')) execute function devolver_pacote_cashback();

create function devolver_pacote_cashback_cancelada() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update pacote_saldos ps set usado = usado - 1 from pacote_usos u
  where u.saldo_id = ps.id and u.comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  delete from pacote_usos where comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  delete from cashback_movimentos where comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  return new;
end
$$;
create trigger devolve_pacote_cancelada after update of status on comandas for each row
  when (new.status = 'cancelada' and old.status is distinct from 'cancelada') execute function devolver_pacote_cashback_cancelada();

-- Item de serviço removido da comanda: se tinha sessão de pacote, o pagamento correspondente sai junto (e a sessão volta).
create function item_removido_pacote() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  u pacote_usos;
begin
  select * into u from pacote_usos where comanda_item_id = old.id;
  if u.id is not null then
    delete from pacote_usos where id = u.id;
    update pacote_saldos set usado = usado - 1 where id = u.saldo_id;
    delete from comanda_pagamentos where id = u.comanda_pagamento_id;
  end if;
  return old;
end
$$;
create trigger item_removido_pacote before delete on comanda_itens for each row execute function item_removido_pacote();

revoke execute on function pacotes_e_cashback_comanda(), devolver_pacote_cashback(), devolver_pacote_cashback_cancelada(), item_removido_pacote() from public, anon, authenticated;
revoke all on function usar_pacote(uuid), usar_cashback(uuid), saldo_cashback(uuid) from public, anon;
grant execute on function usar_pacote(uuid), usar_cashback(uuid), saldo_cashback(uuid) to authenticated;

alter table pacotes enable row level security;
alter table pacote_itens enable row level security;
alter table pacotes_cliente enable row level security;
alter table pacote_saldos enable row level security;
alter table pacote_usos enable row level security;
alter table cashback_movimentos enable row level security;
create policy pacotes_ler on pacotes for select to authenticated using (salao_id = meu_salao());
create policy pacotes_escrever on pacotes for all to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');
create policy pitens_ler on pacote_itens for select to authenticated using (salao_id = meu_salao());
create policy pitens_escrever on pacote_itens for all to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');
create policy pcli_ler on pacotes_cliente for select to authenticated using (salao_id = meu_salao());
create policy pcli_cancelar on pacotes_cliente for update to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao());
create policy psal_ler on pacote_saldos for select to authenticated using (salao_id = meu_salao());
create policy puso_ler on pacote_usos for select to authenticated using (salao_id = meu_salao());
create policy cb_ler on cashback_movimentos for select to authenticated using (salao_id = meu_salao());
revoke all on pacotes, pacote_itens, pacotes_cliente, pacote_saldos, pacote_usos, cashback_movimentos from anon, authenticated;
grant select, insert, update, delete on pacotes, pacote_itens to authenticated;
grant select on pacotes_cliente, pacote_saldos, pacote_usos, cashback_movimentos to authenticated;
grant update (estado) on pacotes_cliente to authenticated;
create trigger aud_pacotes after insert or update or delete on pacotes for each row execute function auditar();
create trigger aud_pacotes_cliente after insert or update or delete on pacotes_cliente for each row execute function auditar();

-- Painel: venda de pacote entra no faturamento; sessão de pacote usada e cashback não contam de novo.
create or replace function painel(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
  r jsonb;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador vê o painel' using errcode = '42501'; end if;
  if p_fim < p_inicio or p_fim - p_inicio > 400 then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  select * into s from saloes where id = v_salao;
  de := (p_inicio::timestamp) at time zone s.fuso;
  ate := ((p_fim + 1)::timestamp) at time zone s.fuso;

  with
  cmd as (
    select c.id, c.cliente_id, (c.fechada_em at time zone s.fuso)::date dia from comandas c
    where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate
  ),
  itens as (
    select i.*, cmd.dia from comanda_itens i join cmd on cmd.id = i.comanda_id
  ),
  vendas as (
    select
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'servico'), 0) servicos,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'produto'), 0) produtos,
      coalesce(sum(i.preco_centavos) filter (where i.tipo = 'gorjeta'), 0) gorjetas,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo::text = 'pacote'), 0) pacotes
    from itens i
  ),
  descontos as (select coalesce(sum(c.desconto_centavos), 0) v from comandas c join cmd on cmd.id = c.id),
  -- serviço usado do pacote ou pago com cashback não é dinheiro novo
  creditos as (select coalesce(sum(p.valor_centavos), 0) v from comanda_pagamentos p join cmd on cmd.id = p.comanda_id where p.forma::text in ('pacote', 'cashback')),
  ags as (
    select a.* from agendamentos a where a.salao_id = v_salao and a.inicio >= de and a.inicio < ate
  ),
  atendidos as (select distinct cliente_id from ags where status = 'concluido'),
  -- cliente que já tinha vindo antes do período
  retornou as (
    select count(*) n from atendidos t
    where exists (select 1 from agendamentos x where x.cliente_id = t.cliente_id and x.status = 'concluido' and x.inicio < de)
  ),
  novos as (
    select c.id, c.origem from clientes c where c.salao_id = v_salao and c.criado_em >= de and c.criado_em < ate
  ),
  -- saiu com o próximo horário marcado: existe agendamento criado até o fim do dia do atendimento, para depois dele
  rebook as (
    select count(*) filter (where exists (
      select 1 from agendamentos x where x.cliente_id = a.cliente_id and x.inicio > a.fim and x.status <> 'cancelado'
        and x.criado_em < ((((a.inicio at time zone s.fuso)::date + 1)::timestamp) at time zone s.fuso)
    )) sim, count(*) total
    from (select distinct on (cliente_id) * from ags where status = 'concluido' order by cliente_id, inicio desc) a
  ),
  -- minutos disponíveis: jornada de cada profissional nos dias de trabalho, menos almoço e bloqueios
  dias as (select d::date dia from generate_series(p_inicio, p_fim, interval '1 day') d),
  jornada as (
    select m.user_id, m.nome, d.dia,
      greatest(extract(epoch from coalesce(m.saida, s.fecha) - coalesce(m.entrada, s.abre)) / 60
        - coalesce(extract(epoch from m.almoco_fim - m.almoco_inicio) / 60, 0), 0) minutos
    from membros m cross join dias d
    where m.salao_id = v_salao and m.ativo and m.papel in ('admin', 'profissional')
      and extract(isodow from d.dia)::int = any (coalesce(m.dias_semana, s.dias_semana))
  ),
  bloqueado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo * tstzrange(de, ate)) - lower(o.periodo * tstzrange(de, ate))) / 60) minutos
    from ocupacoes o where o.salao_id = v_salao and o.bloqueio_id is not null and o.periodo && tstzrange(de, ate) group by 1
  ),
  ocupado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo) - lower(o.periodo)) / 60) minutos
    from ocupacoes o join agendamentos a on a.id = o.agendamento_id
    where o.salao_id = v_salao and a.inicio >= de and a.inicio < ate and a.status <> 'faltou' group by 1
  ),
  por_prof as (
    select j.user_id, j.nome, sum(j.minutos) - coalesce(max(b.minutos), 0) disponivel, coalesce(max(o.minutos), 0) ocupado
    from jornada j left join bloqueado b on b.profissional_id = j.user_id left join ocupado o on o.profissional_id = j.user_id
    group by j.user_id, j.nome
  ),
  receita_prof as (
    select i.profissional_id, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) receita, count(distinct i.comanda_id) atendimentos
    from itens i where i.tipo = 'servico' group by 1
  ),
  comissao_prof as (
    select profissional_id, sum(valor_centavos) v from comissoes
    where salao_id = v_salao and papel <> 'gorjeta' and competencia between p_inicio and p_fim group by 1
  ),
  por_dia as (
    select i.dia, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo <> 'gorjeta') v from itens i group by 1
  ),
  top_servicos as (
    select i.descricao, count(*) n, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) v from itens i where i.tipo = 'servico'
    group by 1 order by v desc limit 8
  )
  select jsonb_build_object(
    'receita', (select servicos + produtos + pacotes from vendas) - (select v from descontos) - (select v from creditos),
    'pacotes', (select pacotes from vendas),
    'servicos', (select servicos from vendas), 'produtos', (select produtos from vendas), 'gorjetas', (select gorjetas from vendas),
    'comandas', (select count(*) from cmd),
    'atendimentos', (select count(*) from ags where status = 'concluido'),
    'faltas', (select count(*) from ags where status = 'faltou'),
    'cancelados', (select count(*) from ags where status = 'cancelado'),
    'clientes_atendidos', (select count(*) from atendidos),
    'clientes_retorno', (select n from retornou),
    'clientes_novos', (select count(*) from novos),
    'origem_novos', coalesce((select jsonb_object_agg(coalesce(origem, 'nao_informado'), n) from (select origem, count(*) n from novos group by 1) o), '{}'::jsonb),
    'rebook', (select jsonb_build_object('sim', sim, 'total', total) from rebook),
    'ocupacao', (select jsonb_build_object('disponivel', coalesce(sum(disponivel), 0), 'ocupado', coalesce(sum(ocupado), 0)) from por_prof),
    'online', (select count(*) from ags where origem = 'online'), 'whatsapp', (select count(*) from ags where origem = 'whatsapp'),
    'profissionais', coalesce((select jsonb_agg(jsonb_build_object('id', p.user_id, 'nome', p.nome, 'disponivel', p.disponivel, 'ocupado', p.ocupado,
        'receita', coalesce(r.receita, 0), 'atendimentos', coalesce(r.atendimentos, 0), 'comissao', coalesce(c.v, 0)) order by coalesce(r.receita, 0) desc)
      from por_prof p left join receita_prof r on r.profissional_id = p.user_id left join comissao_prof c on c.profissional_id = p.user_id), '[]'::jsonb),
    'por_dia', coalesce((select jsonb_object_agg(dia, v) from por_dia), '{}'::jsonb),
    'top_servicos', coalesce((select jsonb_agg(jsonb_build_object('nome', descricao, 'n', n, 'v', v)) from top_servicos), '[]'::jsonb)
  ) into r;
  return r;
end
$$;
-- Belezando · correções da segunda revisão (pacotes, cashback, união de cadastros, lista de espera, painel).

-- 1) Pagamento com pacote, cashback ou sinal só pelas funções que descontam o saldo (nunca digitado na comanda).
create function trava_pagamento_credito() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.forma::text in ('pacote', 'cashback', 'sinal') and current_user in ('authenticated', 'anon') then
    raise exception 'use o botão de pacote, cashback ou sinal' using errcode = '42501';
  end if;
  return new;
end
$$;
create trigger trava_pagamento_credito before insert on comanda_pagamentos for each row execute function trava_pagamento_credito();
revoke execute on function trava_pagamento_credito() from public, anon, authenticated;

-- 2) Unir cadastros não pode apagar pacote pago, cashback, lista de espera nem avisos.
create or replace function unir_clientes(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  a clientes; b clientes;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção unem cadastros' using errcode = '42501'; end if;
  if p_manter = p_remover then raise exception 'mesmo cadastro' using errcode = '22023'; end if;
  select * into a from clientes where id = p_manter and salao_id = v_salao for update;
  select * into b from clientes where id = p_remover and salao_id = v_salao for update;
  if a.id is null or b.id is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update agendamentos set cliente_id = a.id where cliente_id = b.id;
  -- comandas fechadas também mudam de dono (só o cliente; valores continuam travados)
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', '', true);
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update aceites_politica set cliente_id = a.id where cliente_id = b.id;
  update pacotes_cliente set cliente_id = a.id where cliente_id = b.id;
  update cashback_movimentos set cliente_id = a.id where cliente_id = b.id;
  update lista_espera set cliente_id = a.id where cliente_id = b.id;
  update avisos set cliente_id = a.id where cliente_id = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;

-- 3 e 4) Cancelar a comanda devolve todas as sessões usadas nela (inclusive duas do mesmo saldo e as de valor zero).
create or replace function devolver_pacote_cashback_cancelada() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update pacote_saldos ps set usado = ps.usado - x.n
  from (select u.saldo_id, count(*) n from pacote_usos u join comanda_itens i on i.id = u.comanda_item_id where i.comanda_id = new.id group by u.saldo_id) x
  where ps.id = x.saldo_id;
  delete from pacote_usos where comanda_item_id in (select id from comanda_itens where comanda_id = new.id);
  delete from cashback_movimentos where comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  return new;
end
$$;

-- 5) Saldo de cashback: cada uso consome os créditos válidos mais antigos naquele momento; o que sobra e não venceu é o saldo.
create or replace function saldo_cashback(p_cliente uuid) returns int
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  m record;
  ids uuid[] := '{}';
  vence timestamptz[] := '{}';
  resto int[] := '{}';
  falta int;
  k int;
  total int := 0;
begin
  for m in select * from cashback_movimentos where cliente_id = p_cliente and salao_id = meu_salao() order by criado_em, tipo loop
    if m.tipo = 'credito' then
      ids := ids || m.id; vence := vence || m.expira_em; resto := resto || m.valor_centavos;
    else
      falta := -m.valor_centavos;
      for k in 1 .. coalesce(array_length(ids, 1), 0) loop
        exit when falta <= 0;
        if vence[k] > m.criado_em and resto[k] > 0 then
          if resto[k] >= falta then resto[k] := resto[k] - falta; falta := 0;
          else falta := falta - resto[k]; resto[k] := 0; end if;
        end if;
      end loop;
    end if;
  end loop;
  for k in 1 .. coalesce(array_length(ids, 1), 0) loop
    if vence[k] > now() then total := total + resto[k]; end if;
  end loop;
  return total;
end
$$;

-- 6) Sessão de pacote, cashback ou sinal de uma cliente não pode pagar a comanda de outra.
create or replace function trava_comanda() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if old.status <> 'aberta' and current_setting('belezando.reabrindo', true) is distinct from 'sim' then
    raise exception 'comanda_fechada' using errcode = '55000';
  end if;
  if new.status = 'fechada' and old.status = 'aberta' and current_setting('belezando.fechando', true) is distinct from 'sim' then
    raise exception 'use fechar_comanda' using errcode = '42501';
  end if;
  if new.status = 'cancelada' and old.status = 'aberta' and auth.uid() is not null and meu_papel() <> 'admin'
     and exists (select 1 from comanda_pagamentos where comanda_id = old.id) then
    raise exception 'só o administrador cancela comanda com pagamento' using errcode = '42501';
  end if;
  if new.cliente_id is distinct from old.cliente_id and current_setting('belezando.reabrindo', true) is distinct from 'sim'
     and exists (select 1 from comanda_pagamentos where comanda_id = old.id and forma::text in ('pacote', 'cashback', 'sinal')) then
    raise exception 'comanda_com_credito_da_cliente' using errcode = '55000';
  end if;
  return new;
end
$$;

-- 7) Quem foi avisada de uma vaga e não conseguiu marcar continua recebendo as próximas.
create or replace function avisar_lista_espera() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_local timestamp;
  v_periodo text;
  e record;
  n int := 0;
begin
  if new.status <> 'cancelado' or old.status = 'cancelado' or new.inicio < now() + interval '1 hour' then return new; end if;
  select * into s from saloes where id = new.salao_id;
  if not s.espera_ativa then return new; end if;
  v_local := new.inicio at time zone s.fuso;
  v_periodo := case when v_local::time < '12:00' then 'manha' when v_local::time < '18:00' then 'tarde' else 'noite' end;
  for e in
    select l.*, c.nome cliente_nome from lista_espera l join clientes c on c.id = l.cliente_id
    where l.salao_id = new.salao_id and l.estado in ('aguardando', 'avisado') and l.servico_id = new.servico_id
      and v_local::date between l.data_de and l.data_ate
      and (l.periodo = 'qualquer' or l.periodo = v_periodo)
      and (l.profissional_id is null or l.profissional_id = new.profissional_id)
      and l.cliente_id <> new.cliente_id and cliente_contatavel(c)
    order by l.criado_em limit 3
  loop
    insert into avisos (salao_id, cliente_id, tipo, chave, dados)
    values (new.salao_id, e.cliente_id, 'vaga', 'vaga:' || e.id || ':' || new.id,
            jsonb_build_object('servico_id', new.servico_id, 'profissional_id', new.profissional_id, 'inicio', new.inicio, 'espera_id', e.id))
    on conflict (salao_id, chave) do nothing;
    update lista_espera set estado = 'avisado', avisado_em = now() where id = e.id;
    n := n + 1;
  end loop;
  return new;
end
$$;

-- Aviso que travou três vezes no envio é dado como falha (não fica pendente para sempre).
create or replace function reservar_avisos(p_limite int) returns table (
  id uuid, salao_id uuid, tipo text, dados jsonb, wa_id text, cliente_nome text, salao_nome text, slug text, fuso text
)
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update avisos a set tentativas = a.tentativas + 1, estado = case when a.tentativas + 1 >= 3 then 'falhou' else 'pendente' end
  where a.estado = 'enviando' and a.reservado_em < now() - interval '15 minutes';
  -- vaga velha não serve mais; cliente que marcou ou pediu PARAR não recebe
  update avisos a set estado = 'cancelado', erro = 'passou da hora' where a.estado = 'pendente' and a.tipo = 'vaga' and a.criado_em < now() - interval '3 hours';
  update avisos a set estado = 'cancelado', erro = 'cliente não pode receber ou já marcou'
  where a.estado = 'pendente' and a.enviar_em <= now()
    and (not exists (select 1 from clientes c where c.id = a.cliente_id and cliente_contatavel(c))
         or (a.tipo = 'retorno' and exists (select 1 from agendamentos f where f.cliente_id = a.cliente_id and f.inicio > now() and f.status in ('agendado', 'confirmado'))));
  return query
  with alvo as (
    select v.id from avisos v where v.estado = 'pendente' and v.enviar_em <= now() and v.tentativas < 3
    order by v.enviar_em limit p_limite for update skip locked
  ), marcado as (
    update avisos v set estado = 'enviando', reservado_em = now() from alvo where v.id = alvo.id returning v.*
  )
  select m.id, m.salao_id, m.tipo, m.dados,
    coalesce((select cv.wa_id from conversas cv where cv.salao_id = m.salao_id and cv.cliente_id = c.id order by cv.ultima_msg_em desc limit 1), '55' || tel_nacional(c.telefone)),
    c.nome, s.nome, s.slug, s.fuso
  from marcado m join clientes c on c.id = m.cliente_id join saloes s on s.id = m.salao_id;
end
$$;

-- 8) O faturamento por dia bate com a receita do período.
create or replace function painel(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
  r jsonb;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador vê o painel' using errcode = '42501'; end if;
  if p_fim < p_inicio or p_fim - p_inicio > 400 then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  select * into s from saloes where id = v_salao;
  de := (p_inicio::timestamp) at time zone s.fuso;
  ate := ((p_fim + 1)::timestamp) at time zone s.fuso;

  with
  cmd as (
    select c.id, c.cliente_id, (c.fechada_em at time zone s.fuso)::date dia from comandas c
    where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate
  ),
  itens as (
    select i.*, cmd.dia from comanda_itens i join cmd on cmd.id = i.comanda_id
  ),
  vendas as (
    select
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'servico'), 0) servicos,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'produto'), 0) produtos,
      coalesce(sum(i.preco_centavos) filter (where i.tipo = 'gorjeta'), 0) gorjetas,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo::text = 'pacote'), 0) pacotes
    from itens i
  ),
  descontos as (select coalesce(sum(c.desconto_centavos), 0) v from comandas c join cmd on cmd.id = c.id),
  -- serviço usado do pacote ou pago com cashback não é dinheiro novo
  creditos as (select coalesce(sum(p.valor_centavos), 0) v from comanda_pagamentos p join cmd on cmd.id = p.comanda_id where p.forma::text in ('pacote', 'cashback')),
  ags as (
    select a.* from agendamentos a where a.salao_id = v_salao and a.inicio >= de and a.inicio < ate
  ),
  atendidos as (select distinct cliente_id from ags where status = 'concluido'),
  -- cliente que já tinha vindo antes do período
  retornou as (
    select count(*) n from atendidos t
    where exists (select 1 from agendamentos x where x.cliente_id = t.cliente_id and x.status = 'concluido' and x.inicio < de)
  ),
  novos as (
    select c.id, c.origem from clientes c where c.salao_id = v_salao and c.criado_em >= de and c.criado_em < ate
  ),
  -- saiu com o próximo horário marcado: existe agendamento criado até o fim do dia do atendimento, para depois dele
  rebook as (
    select count(*) filter (where exists (
      select 1 from agendamentos x where x.cliente_id = a.cliente_id and x.inicio > a.fim and x.status <> 'cancelado'
        and x.criado_em < ((((a.inicio at time zone s.fuso)::date + 1)::timestamp) at time zone s.fuso)
    )) sim, count(*) total
    from (select distinct on (cliente_id) * from ags where status = 'concluido' order by cliente_id, inicio desc) a
  ),
  -- minutos disponíveis: jornada de cada profissional nos dias de trabalho, menos almoço e bloqueios
  dias as (select d::date dia from generate_series(p_inicio, p_fim, interval '1 day') d),
  jornada as (
    select m.user_id, m.nome, d.dia,
      greatest(extract(epoch from coalesce(m.saida, s.fecha) - coalesce(m.entrada, s.abre)) / 60
        - coalesce(extract(epoch from m.almoco_fim - m.almoco_inicio) / 60, 0), 0) minutos
    from membros m cross join dias d
    where m.salao_id = v_salao and m.ativo and m.papel in ('admin', 'profissional')
      and extract(isodow from d.dia)::int = any (coalesce(m.dias_semana, s.dias_semana))
  ),
  bloqueado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo * tstzrange(de, ate)) - lower(o.periodo * tstzrange(de, ate))) / 60) minutos
    from ocupacoes o where o.salao_id = v_salao and o.bloqueio_id is not null and o.periodo && tstzrange(de, ate) group by 1
  ),
  ocupado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo) - lower(o.periodo)) / 60) minutos
    from ocupacoes o join agendamentos a on a.id = o.agendamento_id
    where o.salao_id = v_salao and a.inicio >= de and a.inicio < ate and a.status <> 'faltou' group by 1
  ),
  por_prof as (
    select j.user_id, j.nome, sum(j.minutos) - coalesce(max(b.minutos), 0) disponivel, coalesce(max(o.minutos), 0) ocupado
    from jornada j left join bloqueado b on b.profissional_id = j.user_id left join ocupado o on o.profissional_id = j.user_id
    group by j.user_id, j.nome
  ),
  receita_prof as (
    select i.profissional_id, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) receita, count(distinct i.comanda_id) atendimentos
    from itens i where i.tipo = 'servico' group by 1
  ),
  comissao_prof as (
    select profissional_id, sum(valor_centavos) v from comissoes
    where salao_id = v_salao and papel <> 'gorjeta' and competencia between p_inicio and p_fim group by 1
  ),
  por_dia as (
    select d.dia, sum(d.v) v from (
      select i.dia, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo <> 'gorjeta') v from itens i group by 1
      union all
      select cmd.dia, -sum(c.desconto_centavos) from comandas c join cmd on cmd.id = c.id group by 1
      union all
      select cmd.dia, -sum(p.valor_centavos) from comanda_pagamentos p join cmd on cmd.id = p.comanda_id where p.forma::text in ('pacote', 'cashback') group by 1
    ) d group by 1
  ),
  top_servicos as (
    select i.descricao, count(*) n, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) v from itens i where i.tipo = 'servico'
    group by 1 order by v desc limit 8
  )
  select jsonb_build_object(
    'receita', (select servicos + produtos + pacotes from vendas) - (select v from descontos) - (select v from creditos),
    'pacotes', (select pacotes from vendas),
    'servicos', (select servicos from vendas), 'produtos', (select produtos from vendas), 'gorjetas', (select gorjetas from vendas),
    'comandas', (select count(*) from cmd),
    'atendimentos', (select count(*) from ags where status = 'concluido'),
    'faltas', (select count(*) from ags where status = 'faltou'),
    'cancelados', (select count(*) from ags where status = 'cancelado'),
    'clientes_atendidos', (select count(*) from atendidos),
    'clientes_retorno', (select n from retornou),
    'clientes_novos', (select count(*) from novos),
    'origem_novos', coalesce((select jsonb_object_agg(coalesce(origem, 'nao_informado'), n) from (select origem, count(*) n from novos group by 1) o), '{}'::jsonb),
    'rebook', (select jsonb_build_object('sim', sim, 'total', total) from rebook),
    'ocupacao', (select jsonb_build_object('disponivel', coalesce(sum(disponivel), 0), 'ocupado', coalesce(sum(ocupado), 0)) from por_prof),
    'online', (select count(*) from ags where origem = 'online'), 'whatsapp', (select count(*) from ags where origem = 'whatsapp'),
    'profissionais', coalesce((select jsonb_agg(jsonb_build_object('id', p.user_id, 'nome', p.nome, 'disponivel', p.disponivel, 'ocupado', p.ocupado,
        'receita', coalesce(r.receita, 0), 'atendimentos', coalesce(r.atendimentos, 0), 'comissao', coalesce(c.v, 0)) order by coalesce(r.receita, 0) desc)
      from por_prof p left join receita_prof r on r.profissional_id = p.user_id left join comissao_prof c on c.profissional_id = p.user_id), '[]'::jsonb),
    'por_dia', coalesce((select jsonb_object_agg(dia, v) from por_dia), '{}'::jsonb),
    'top_servicos', coalesce((select jsonb_agg(jsonb_build_object('nome', descricao, 'n', n, 'v', v)) from top_servicos), '[]'::jsonb)
  ) into r;
  return r;
end
$$;
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
-- Belezando · avaliação depois do atendimento (NPS).
-- No dia seguinte à comanda fechada, a cliente recebe "de 0 a 10, quanto recomendaria?" com um link.
-- Nota 9 ou 10 é convidada a avaliar no Google; nota até 6 vira alerta para o dono. No máximo uma pergunta a cada 30 dias.

alter table saloes add column avaliacao_ativa boolean not null default false;
alter table saloes add column google_avaliacao_url text check (google_avaliacao_url ~ '^https://');
grant update (avaliacao_ativa, google_avaliacao_url) on saloes to authenticated;

alter table avisos drop constraint avisos_tipo_check;
alter table avisos add constraint avisos_tipo_check check (tipo in ('retorno', 'vaga', 'avaliacao'));

create table avaliacoes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  comanda_id uuid not null unique,
  profissionais text,                     -- quem atendeu, para o dono ver
  token_hash text not null unique,
  nota int check (nota between 0 and 10),
  comentario text check (length(comentario) <= 1000),
  respondida_em timestamptz,
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade
);
create index on avaliacoes (salao_id, respondida_em desc);
alter table avaliacoes enable row level security;
create policy avaliacoes_ler on avaliacoes for select to authenticated using (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
revoke all on avaliacoes from anon, authenticated;
grant select (id, salao_id, cliente_id, comanda_id, profissionais, nota, comentario, respondida_em, criado_em) on avaliacoes to authenticated;

-- Comanda fechada: agenda a pergunta para o dia seguinte, no horário de mensagens do salão.
create function pedir_avaliacao() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not (new.status = 'fechada' and old.status = 'aberta') or new.cliente_id is null then return new; end if;
  select * into s from saloes where id = new.salao_id;
  if not s.avaliacao_ativa then return new; end if;
  if not exists (select 1 from clientes c where c.id = new.cliente_id and cliente_contatavel(c)) then return new; end if;
  if exists (select 1 from avaliacoes a where a.cliente_id = new.cliente_id and a.criado_em > now() - interval '30 days') then return new; end if;
  if not exists (select 1 from comanda_itens i where i.comanda_id = new.id and i.tipo = 'servico') then return new; end if;
  insert into avaliacoes (salao_id, cliente_id, comanda_id, profissionais, token_hash)
  values (new.salao_id, new.cliente_id, new.id,
          (select string_agg(distinct m.nome, ', ') from comanda_itens i join membros m on m.user_id = i.profissional_id where i.comanda_id = new.id and i.tipo = 'servico'),
          encode(sha256(convert_to(v_token, 'UTF8')), 'hex'))
  on conflict (comanda_id) do nothing;
  insert into avisos (salao_id, cliente_id, tipo, chave, dados, enviar_em)
  values (new.salao_id, new.cliente_id, 'avaliacao', 'avaliacao:' || new.id, jsonb_build_object('token', v_token),
          (((now() at time zone s.fuso)::date + 1) + s.retorno_hora) at time zone s.fuso)
  on conflict (salao_id, chave) do nothing;
  return new;
end
$$;
create trigger pedir_avaliacao after update of status on comandas for each row execute function pedir_avaliacao();
revoke execute on function pedir_avaliacao() from public, anon, authenticated;

create function avaliacao_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'cliente', split_part(c.nome, ' ', 1), 'nota', a.nota, 'respondida', a.respondida_em is not null,
    'google', s.google_avaliacao_url, 'expirada', a.respondida_em is null and a.criado_em < now() - interval '15 days')
  from avaliacoes a join saloes s on s.id = a.salao_id join clientes c on c.id = a.cliente_id
  where a.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;

create function responder_avaliacao(p_token text, p_nota int, p_comentario text) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a avaliacoes;
begin
  select * into a from avaliacoes where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if a.id is null then return 'nao_encontrada'; end if;
  if a.respondida_em is not null then return 'ja_respondida'; end if;
  if a.criado_em < now() - interval '15 days' then return 'expirada'; end if;
  if p_nota is null or p_nota not between 0 and 10 then return 'invalida'; end if;
  update avaliacoes set nota = p_nota, comentario = left(nullif(trim(p_comentario), ''), 1000), respondida_em = now() where id = a.id;
  return 'respondida';
end
$$;

-- NPS do período: % de promotores (9-10) menos % de detratores (0-6).
create function nps(p_inicio date, p_fim date) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  with r as (
    select a.nota from avaliacoes a join saloes s on s.id = a.salao_id
    where a.salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao') and a.nota is not null
      and (a.respondida_em at time zone s.fuso)::date between p_inicio and p_fim
  )
  select jsonb_build_object('respostas', count(*), 'promotores', count(*) filter (where nota >= 9), 'detratores', count(*) filter (where nota <= 6),
    'nps', case when count(*) > 0 then round(100.0 * (count(*) filter (where nota >= 9) - count(*) filter (where nota <= 6)) / count(*)) end,
    'media', round(avg(nota), 1))
  from r
$$;

revoke all on function avaliacao_publica(text), responder_avaliacao(text, int, text) from public, anon, authenticated;
grant execute on function avaliacao_publica(text), responder_avaliacao(text, int, text) to service_role;
revoke all on function nps(date, date) from public, anon;
grant execute on function nps(date, date) to authenticated;
-- Belezando · vale-presente.
-- Vendido na comanda (ex.: Dia das Mães); ao fechar nasce um código. Quem ganhou usa o código como pagamento, até acabar o saldo.
-- A venda entra no faturamento; o uso não conta de novo (o dinheiro entrou na venda).

alter type tipo_item add value if not exists 'vale_presente';
alter type forma_pagamento add value if not exists 'vale_presente';

alter table comanda_itens add column presente_para text check (length(presente_para) <= 80);
alter table comanda_itens add column presente_mensagem text check (length(presente_mensagem) <= 200);
grant insert (presente_para, presente_mensagem) on comanda_itens to authenticated;

create table vales_presente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  codigo text not null check (codigo ~ '^[A-Z2-9]{8}$'),
  valor_centavos int not null check (valor_centavos > 0),
  saldo_centavos int not null check (saldo_centavos >= 0),
  para text,
  mensagem text,
  comprado_por uuid,
  comanda_id uuid not null,
  item_id uuid not null unique,
  expira_em timestamptz not null default now() + interval '1 year',
  estado text not null default 'ativo' check (estado in ('ativo', 'cancelado')),
  criado_em timestamptz not null default now(),
  check (saldo_centavos <= valor_centavos),
  unique (salao_id, codigo),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id)
);
create table vale_presente_usos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  vale_id uuid not null references vales_presente (id) on delete cascade,
  comanda_pagamento_id uuid not null unique,
  valor_centavos int not null check (valor_centavos > 0),
  criado_em timestamptz not null default now()
);
alter table vales_presente enable row level security;
alter table vale_presente_usos enable row level security;
create policy vp_ler on vales_presente for select to authenticated using (salao_id = meu_salao());
create policy vpu_ler on vale_presente_usos for select to authenticated using (salao_id = meu_salao());
create policy vp_cancelar on vales_presente for update to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao());
revoke all on vales_presente, vale_presente_usos from anon, authenticated;
grant select on vales_presente, vale_presente_usos to authenticated;
grant update (estado) on vales_presente to authenticated;
create trigger aud_vales_presente after insert or update on vales_presente for each row execute function auditar();

-- Código fácil de ditar: 8 letras e números sem 0, O, 1 e I.
create function novo_codigo_vale() returns text
language plpgsql volatile set search_path = public, pg_temp as
$$
declare
  letras constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v text := '';
begin
  for k in 1 .. 8 loop
    v := v || substr(letras, 1 + floor(random() * length(letras))::int, 1);
  end loop;
  return v;
end
$$;

-- Ao fechar a comanda nasce o vale; ao reabrir, some (se ainda não foi usado).
create function vales_presente_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  i comanda_itens;
  v_codigo text;
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    for i in select * from comanda_itens where comanda_id = new.id and tipo::text = 'vale_presente' loop
      loop
        v_codigo := novo_codigo_vale();
        exit when not exists (select 1 from vales_presente where salao_id = new.salao_id and codigo = v_codigo);
      end loop;
      insert into vales_presente (salao_id, codigo, valor_centavos, saldo_centavos, para, mensagem, comprado_por, comanda_id, item_id)
      values (new.salao_id, v_codigo, i.preco_centavos - i.desconto_centavos, i.preco_centavos - i.desconto_centavos, i.presente_para, i.presente_mensagem, new.cliente_id, new.id, i.id);
    end loop;
  elsif new.status = 'aberta' and old.status = 'fechada' then
    if exists (select 1 from vales_presente v where v.comanda_id = new.id and v.saldo_centavos < v.valor_centavos) then
      raise exception 'vale_ja_usado' using errcode = '55000';
    end if;
    delete from vales_presente where comanda_id = new.id;
  end if;
  return new;
end
$$;
create trigger vales_presente_comanda after update of status on comandas for each row execute function vales_presente_comanda();

-- Usa o vale (pelo código) até o que falta pagar.
create function usar_vale_presente(p_comanda uuid, p_codigo text) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  v vales_presente;
  t record;
  x int;
  v_pag uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta';
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  select * into v from vales_presente where salao_id = c.salao_id and codigo = upper(trim(p_codigo)) for update;
  if v.id is null then raise exception 'vale_nao_encontrado' using errcode = 'P0002'; end if;
  if v.estado <> 'ativo' or v.expira_em < now() then raise exception 'vale_vencido' using errcode = '55000'; end if;
  if v.comanda_id = c.id then raise exception 'vale_da_propria_comanda' using errcode = '22023'; end if;
  select * into t from total_comanda(p_comanda);
  x := least(v.saldo_centavos, t.total - t.pago);
  if x <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'vale_presente', x) returning id into v_pag;
  update vales_presente set saldo_centavos = saldo_centavos - x where id = v.id;
  insert into vale_presente_usos (salao_id, vale_id, comanda_pagamento_id, valor_centavos) values (c.salao_id, v.id, v_pag, x);
  return x;
end
$$;

-- Pagamento com vale removido, ou comanda cancelada: o saldo volta.
create function devolver_vale_presente() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  u vale_presente_usos;
begin
  select * into u from vale_presente_usos where comanda_pagamento_id = old.id;
  if u.id is not null then
    update vales_presente set saldo_centavos = saldo_centavos + u.valor_centavos where id = u.vale_id;
    delete from vale_presente_usos where id = u.id;
  end if;
  return old;
end
$$;
create trigger devolve_vale after delete on comanda_pagamentos for each row when (old.forma::text = 'vale_presente') execute function devolver_vale_presente();

create function devolver_vale_cancelada() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update vales_presente vp set saldo_centavos = vp.saldo_centavos + x.v
  from (select u.vale_id, sum(u.valor_centavos) v from vale_presente_usos u join comanda_pagamentos p on p.id = u.comanda_pagamento_id
        where p.comanda_id = new.id group by u.vale_id) x
  where vp.id = x.vale_id;
  delete from vale_presente_usos where comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  return new;
end
$$;
create trigger devolve_vale_cancelada after update of status on comandas for each row
  when (new.status = 'cancelada' and old.status is distinct from 'cancelada') execute function devolver_vale_cancelada();

revoke execute on function novo_codigo_vale(), vales_presente_comanda(), devolver_vale_presente(), devolver_vale_cancelada() from public, anon, authenticated;
revoke all on function usar_vale_presente(uuid, text) from public, anon;
grant execute on function usar_vale_presente(uuid, text) to authenticated;

alter table comanda_itens add constraint item_vale_ok check (tipo::text <> 'vale_presente' or (quantidade = 1 and presente_para is not null));

-- Vale-presente também só entra como pagamento pela função (que desconta o saldo).
create or replace function trava_pagamento_credito() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.forma::text in ('pacote', 'cashback', 'sinal', 'vale_presente') and current_user in ('authenticated', 'anon') then
    raise exception 'use o botão de pacote, cashback ou sinal' using errcode = '42501';
  end if;
  return new;
end
$$;

-- Cashback não nasce sobre o que foi pago com vale-presente (já gerou na venda).
create or replace function pacotes_e_cashback_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  i comanda_itens;
  p pacotes;
  v_pc uuid;
  v_soma numeric;
  v_base int;
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    select * into s from saloes where id = new.salao_id;
    if exists (select 1 from comanda_itens where comanda_id = new.id and tipo::text = 'pacote') and new.cliente_id is null then
      raise exception 'pacote_sem_cliente' using errcode = '22023';
    end if;
    -- venda de pacote: nasce o saldo, com o valor de cada sessão proporcional ao preço de tabela
    for i in select * from comanda_itens where comanda_id = new.id and tipo::text = 'pacote' loop
      select * into p from pacotes where id = i.pacote_id;
      insert into pacotes_cliente (salao_id, cliente_id, pacote_id, nome, tipo, comanda_id, expira_em)
      values (new.salao_id, new.cliente_id, p.id, p.nome, p.tipo, new.id, now() + make_interval(days => p.validade_dias)) returning id into v_pc;
      select sum(greatest(sv.preco_centavos, 1) * pi.quantidade) into v_soma from pacote_itens pi join servicos sv on sv.id = pi.servico_id where pi.pacote_id = p.id;
      insert into pacote_saldos (salao_id, pacote_cliente_id, servico_id, total, valor_unitario_centavos)
      select new.salao_id, v_pc, pi.servico_id, pi.quantidade,
             round((i.preco_centavos - i.desconto_centavos) * greatest(sv.preco_centavos, 1)::numeric / nullif(v_soma, 0))::int
      from pacote_itens pi join servicos sv on sv.id = pi.servico_id where pi.pacote_id = p.id;
    end loop;
    -- cashback sobre o que foi pago em dinheiro de verdade (sem gorjeta, pacote usado, cashback e sinal)
    if s.cashback_percentual > 0 and new.cliente_id is not null then
      select coalesce(sum(valor_centavos), 0) into v_base from comanda_pagamentos
      where comanda_id = new.id and forma::text not in ('pacote', 'cashback', 'vale_presente');
      v_base := v_base - coalesce((select sum(preco_centavos) from comanda_itens where comanda_id = new.id and tipo = 'gorjeta'), 0);
      if round(v_base * s.cashback_percentual / 100) >= 1 then
        insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, expira_em)
        values (new.salao_id, new.cliente_id, 'credito', round(v_base * s.cashback_percentual / 100)::int, new.id, now() + make_interval(days => s.cashback_validade_dias));
      end if;
    end if;
  elsif new.status = 'aberta' and old.status = 'fechada' then
    if exists (select 1 from pacotes_cliente pc join pacote_saldos ps on ps.pacote_cliente_id = pc.id where pc.comanda_id = new.id and ps.usado > 0) then
      raise exception 'pacote_ja_usado' using errcode = '55000';
    end if;
    delete from pacotes_cliente where comanda_id = new.id;
    delete from cashback_movimentos where comanda_id = new.id and tipo = 'credito';
  end if;
  return new;
end
$$;

-- Painel: venda de vale-presente entra no faturamento; o uso não conta de novo.
create or replace function painel(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
  r jsonb;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador vê o painel' using errcode = '42501'; end if;
  if p_fim < p_inicio or p_fim - p_inicio > 400 then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  select * into s from saloes where id = v_salao;
  de := (p_inicio::timestamp) at time zone s.fuso;
  ate := ((p_fim + 1)::timestamp) at time zone s.fuso;

  with
  cmd as (
    select c.id, c.cliente_id, (c.fechada_em at time zone s.fuso)::date dia from comandas c
    where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate
  ),
  itens as (
    select i.*, cmd.dia from comanda_itens i join cmd on cmd.id = i.comanda_id
  ),
  vendas as (
    select
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'servico'), 0) servicos,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'produto'), 0) produtos,
      coalesce(sum(i.preco_centavos) filter (where i.tipo = 'gorjeta'), 0) gorjetas,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo::text = 'pacote'), 0) pacotes,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo::text = 'vale_presente'), 0) vales_presente
    from itens i
  ),
  descontos as (select coalesce(sum(c.desconto_centavos), 0) v from comandas c join cmd on cmd.id = c.id),
  -- serviço usado do pacote ou pago com cashback não é dinheiro novo
  creditos as (select coalesce(sum(p.valor_centavos), 0) v from comanda_pagamentos p join cmd on cmd.id = p.comanda_id where p.forma::text in ('pacote', 'cashback', 'vale_presente')),
  ags as (
    select a.* from agendamentos a where a.salao_id = v_salao and a.inicio >= de and a.inicio < ate
  ),
  atendidos as (select distinct cliente_id from ags where status = 'concluido'),
  -- cliente que já tinha vindo antes do período
  retornou as (
    select count(*) n from atendidos t
    where exists (select 1 from agendamentos x where x.cliente_id = t.cliente_id and x.status = 'concluido' and x.inicio < de)
  ),
  novos as (
    select c.id, c.origem from clientes c where c.salao_id = v_salao and c.criado_em >= de and c.criado_em < ate
  ),
  -- saiu com o próximo horário marcado: existe agendamento criado até o fim do dia do atendimento, para depois dele
  rebook as (
    select count(*) filter (where exists (
      select 1 from agendamentos x where x.cliente_id = a.cliente_id and x.inicio > a.fim and x.status <> 'cancelado'
        and x.criado_em < ((((a.inicio at time zone s.fuso)::date + 1)::timestamp) at time zone s.fuso)
    )) sim, count(*) total
    from (select distinct on (cliente_id) * from ags where status = 'concluido' order by cliente_id, inicio desc) a
  ),
  -- minutos disponíveis: jornada de cada profissional nos dias de trabalho, menos almoço e bloqueios
  dias as (select d::date dia from generate_series(p_inicio, p_fim, interval '1 day') d),
  jornada as (
    select m.user_id, m.nome, d.dia,
      greatest(extract(epoch from coalesce(m.saida, s.fecha) - coalesce(m.entrada, s.abre)) / 60
        - coalesce(extract(epoch from m.almoco_fim - m.almoco_inicio) / 60, 0), 0) minutos
    from membros m cross join dias d
    where m.salao_id = v_salao and m.ativo and m.papel in ('admin', 'profissional')
      and extract(isodow from d.dia)::int = any (coalesce(m.dias_semana, s.dias_semana))
  ),
  bloqueado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo * tstzrange(de, ate)) - lower(o.periodo * tstzrange(de, ate))) / 60) minutos
    from ocupacoes o where o.salao_id = v_salao and o.bloqueio_id is not null and o.periodo && tstzrange(de, ate) group by 1
  ),
  ocupado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo) - lower(o.periodo)) / 60) minutos
    from ocupacoes o join agendamentos a on a.id = o.agendamento_id
    where o.salao_id = v_salao and a.inicio >= de and a.inicio < ate and a.status <> 'faltou' group by 1
  ),
  por_prof as (
    select j.user_id, j.nome, sum(j.minutos) - coalesce(max(b.minutos), 0) disponivel, coalesce(max(o.minutos), 0) ocupado
    from jornada j left join bloqueado b on b.profissional_id = j.user_id left join ocupado o on o.profissional_id = j.user_id
    group by j.user_id, j.nome
  ),
  receita_prof as (
    select i.profissional_id, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) receita, count(distinct i.comanda_id) atendimentos
    from itens i where i.tipo = 'servico' group by 1
  ),
  comissao_prof as (
    select profissional_id, sum(valor_centavos) v from comissoes
    where salao_id = v_salao and papel <> 'gorjeta' and competencia between p_inicio and p_fim group by 1
  ),
  por_dia as (
    select d.dia, sum(d.v) v from (
      select i.dia, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo <> 'gorjeta') v from itens i group by 1
      union all
      select cmd.dia, -sum(c.desconto_centavos) from comandas c join cmd on cmd.id = c.id group by 1
      union all
      select cmd.dia, -sum(p.valor_centavos) from comanda_pagamentos p join cmd on cmd.id = p.comanda_id where p.forma::text in ('pacote', 'cashback', 'vale_presente') group by 1
    ) d group by 1
  ),
  top_servicos as (
    select i.descricao, count(*) n, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) v from itens i where i.tipo = 'servico'
    group by 1 order by v desc limit 8
  )
  select jsonb_build_object(
    'receita', (select servicos + produtos + pacotes + vales_presente from vendas) - (select v from descontos) - (select v from creditos),
    'pacotes', (select pacotes from vendas),
    'servicos', (select servicos from vendas), 'produtos', (select produtos from vendas), 'gorjetas', (select gorjetas from vendas),
    'comandas', (select count(*) from cmd),
    'atendimentos', (select count(*) from ags where status = 'concluido'),
    'faltas', (select count(*) from ags where status = 'faltou'),
    'cancelados', (select count(*) from ags where status = 'cancelado'),
    'clientes_atendidos', (select count(*) from atendidos),
    'clientes_retorno', (select n from retornou),
    'clientes_novos', (select count(*) from novos),
    'origem_novos', coalesce((select jsonb_object_agg(coalesce(origem, 'nao_informado'), n) from (select origem, count(*) n from novos group by 1) o), '{}'::jsonb),
    'rebook', (select jsonb_build_object('sim', sim, 'total', total) from rebook),
    'ocupacao', (select jsonb_build_object('disponivel', coalesce(sum(disponivel), 0), 'ocupado', coalesce(sum(ocupado), 0)) from por_prof),
    'online', (select count(*) from ags where origem = 'online'), 'whatsapp', (select count(*) from ags where origem = 'whatsapp'),
    'profissionais', coalesce((select jsonb_agg(jsonb_build_object('id', p.user_id, 'nome', p.nome, 'disponivel', p.disponivel, 'ocupado', p.ocupado,
        'receita', coalesce(r.receita, 0), 'atendimentos', coalesce(r.atendimentos, 0), 'comissao', coalesce(c.v, 0)) order by coalesce(r.receita, 0) desc)
      from por_prof p left join receita_prof r on r.profissional_id = p.user_id left join comissao_prof c on c.profissional_id = p.user_id), '[]'::jsonb),
    'por_dia', coalesce((select jsonb_object_agg(dia, v) from por_dia), '{}'::jsonb),
    'top_servicos', coalesce((select jsonb_agg(jsonb_build_object('nome', descricao, 'n', n, 'v', v)) from top_servicos), '[]'::jsonb)
  ) into r;
  return r;
end
$$;
-- Belezando · correções da terceira revisão (atendimento com vários serviços, ficha de primeira visita, união de cadastros, vale-presente).

-- Quem marca pelo link com o telefone de alguém já cadastrado não recebe a ficha dela; cliente nova nasce sem origem (a ficha preenche).
create or replace function agendar_online_grupo(
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
  v_novo boolean := false;
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
    insert into clientes (salao_id, nome, telefone, consentimento_em) values (c.id, left(trim(p_nome), 120), v_tel, now()) returning id into v_cli;
    v_novo := true;
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
  return jsonb_build_object('agendamento_id', v_ag.id, 'token', v_ag.token, 'sinal_centavos', v_sinal, 'cliente_novo', v_novo);
end
$$;

create or replace function criar_link_ficha_online(p_agendamento uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_cli uuid;
begin
  select a.cliente_id into v_cli from agendamentos a join clientes c on c.id = a.cliente_id
  where a.id = p_agendamento and c.criado_em > now() - interval '10 minutes'
    and not exists (select 1 from agendamentos o where o.cliente_id = a.cliente_id and o.id not in (select id from do_grupo(a.id)));
  if v_cli is null or exists (select 1 from fichas_previas where cliente_id = v_cli) then return null; end if;
  return criar_link_ficha_interno(v_cli);
end
$$;

create or replace function responder_ficha(p_token text, p_respostas jsonb) returns text
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
    origem = coalesce(nullif(c.origem, 'outro'), case when r ->> 'origem' in ('indicacao', 'instagram', 'google', 'whatsapp', 'passante', 'facebook', 'tiktok', 'outro') then r ->> 'origem' end),
    nascimento = coalesce(c.nascimento, case when (r ->> 'nascimento') ~ '^\d{4}-\d{2}-\d{2}$' and (r ->> 'nascimento')::date between date '1900-01-01' and current_date then (r ->> 'nascimento')::date end),
    observacoes = left(concat_ws(E'\n', c.observacoes, v_resumo), 2000)
  where c.id = f.cliente_id;
  return 'respondida';
end
$$;

-- Qualquer mudança num serviço do atendimento refaz os lembretes do grupo (o "primeiro" pode ter mudado).
create or replace function trg_lembretes_agendamento() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare r record;
begin
  for r in select id from do_grupo(new.id) loop
    perform programar_lembretes(r.id);
  end loop;
  return new;
end
$$;

-- Cancelar pelo robô cancela todos os serviços do atendimento.
create or replace function cancelar_whatsapp(p_salao uuid, p_conversa uuid, p_agendamento uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare n int;
begin
  if not exists (select 1 from agendamentos_whatsapp(p_salao, p_conversa) x where x.id = p_agendamento) then return false; end if;
  update agendamentos set status = 'cancelado'
  where id in (select id from do_grupo(p_agendamento)) and salao_id = p_salao and status in ('agendado', 'confirmado') and inicio > now();
  get diagnostics n = row_count;
  return n > 0;
end
$$;

-- Atendimento com profissionais diferentes é remarcado pela recepção (pelo link, todos iriam para um só).
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

create or replace function horario_publico(p_token uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object(
    'id', a.id, 'inicio', a.inicio, 'fim', (select max(g.fim) from do_grupo(a.id) g where g.status <> 'cancelado'), 'status', a.status,
    'servico', (select string_agg(sv.nome, ' + ' order by g.inicio) from do_grupo(a.id) g join servicos sv on sv.id = g.servico_id where g.status <> 'cancelado' or a.status = 'cancelado'),
    'servico_ids', (select jsonb_agg(g.servico_id order by g.inicio) from do_grupo(a.id) g where g.status in ('agendado', 'confirmado')),
    'varios_profissionais', (select count(distinct g.profissional_id) > 1 from do_grupo(a.id) g where g.status in ('agendado', 'confirmado')),
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

create or replace function unir_clientes(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  a clientes; b clientes;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção unem cadastros' using errcode = '42501'; end if;
  if p_manter = p_remover then raise exception 'mesmo cadastro' using errcode = '22023'; end if;
  select * into a from clientes where id = p_manter and salao_id = v_salao for update;
  select * into b from clientes where id = p_remover and salao_id = v_salao for update;
  if a.id is null or b.id is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update agendamentos set cliente_id = a.id where cliente_id = b.id;
  -- comandas fechadas também mudam de dono (só o cliente; valores continuam travados)
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', '', true);
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update aceites_politica set cliente_id = a.id where cliente_id = b.id;
  update pacotes_cliente set cliente_id = a.id where cliente_id = b.id;
  update cashback_movimentos set cliente_id = a.id where cliente_id = b.id;
  update lista_espera set cliente_id = a.id where cliente_id = b.id;
  update avisos set cliente_id = a.id where cliente_id = b.id;
  update fichas_previas set cliente_id = a.id where cliente_id = b.id;
  update avaliacoes set cliente_id = a.id where cliente_id = b.id;
  update vales_presente set comprado_por = a.id where comprado_por = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;

-- O vale vale o que foi pago por ele (com a parte do desconto da comanda).
create or replace function vales_presente_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  i comanda_itens;
  v_codigo text;
  v_itens int;
  v_valor int;
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    select coalesce(sum(preco_centavos * quantidade - desconto_centavos), 0) into v_itens from comanda_itens where comanda_id = new.id and tipo <> 'gorjeta';
    for i in select * from comanda_itens where comanda_id = new.id and tipo::text = 'vale_presente' loop
      v_valor := i.preco_centavos - i.desconto_centavos;
      if v_itens > 0 then v_valor := v_valor - round(new.desconto_centavos::numeric * v_valor / v_itens)::int; end if;
      continue when v_valor <= 0;
      loop
        v_codigo := novo_codigo_vale();
        exit when not exists (select 1 from vales_presente where salao_id = new.salao_id and codigo = v_codigo);
      end loop;
      insert into vales_presente (salao_id, codigo, valor_centavos, saldo_centavos, para, mensagem, comprado_por, comanda_id, item_id)
      values (new.salao_id, v_codigo, v_valor, v_valor, i.presente_para, i.presente_mensagem, new.cliente_id, new.id, i.id);
    end loop;
  elsif new.status = 'aberta' and old.status = 'fechada' then
    if exists (select 1 from vales_presente v where v.comanda_id = new.id and v.saldo_centavos < v.valor_centavos) then
      raise exception 'vale_ja_usado' using errcode = '55000';
    end if;
    delete from vales_presente where comanda_id = new.id;
  end if;
  return new;
end
$$;
-- Belezando · correções da quarta revisão (cashback ao reabrir comanda, desconto na venda de pacote, uso simultâneo de crédito).

create or replace function pacotes_e_cashback_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  i comanda_itens;
  p pacotes;
  v_pc uuid;
  v_soma numeric;
  v_base int;
  v_itens int;
  v_cb int;
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    select * into s from saloes where id = new.salao_id;
    if exists (select 1 from comanda_itens where comanda_id = new.id and tipo::text = 'pacote') and new.cliente_id is null then
      raise exception 'pacote_sem_cliente' using errcode = '22023';
    end if;
    -- venda de pacote: nasce o saldo, com o valor de cada sessão proporcional ao preço de tabela (e com a parte do desconto da comanda)
    select coalesce(sum(preco_centavos * quantidade - desconto_centavos), 0) into v_itens from comanda_itens where comanda_id = new.id and tipo <> 'gorjeta';
    for i in select * from comanda_itens where comanda_id = new.id and tipo::text = 'pacote' loop
      select * into p from pacotes where id = i.pacote_id;
      insert into pacotes_cliente (salao_id, cliente_id, pacote_id, nome, tipo, comanda_id, expira_em)
      values (new.salao_id, new.cliente_id, p.id, p.nome, p.tipo, new.id, now() + make_interval(days => p.validade_dias)) returning id into v_pc;
      select sum(greatest(sv.preco_centavos, 1) * pi.quantidade) into v_soma from pacote_itens pi join servicos sv on sv.id = pi.servico_id where pi.pacote_id = p.id;
      insert into pacote_saldos (salao_id, pacote_cliente_id, servico_id, total, valor_unitario_centavos)
      select new.salao_id, v_pc, pi.servico_id, pi.quantidade,
             round((i.preco_centavos - i.desconto_centavos
                    - case when v_itens > 0 then new.desconto_centavos::numeric * (i.preco_centavos - i.desconto_centavos) / v_itens else 0 end)
                   * greatest(sv.preco_centavos, 1)::numeric / nullif(v_soma, 0))::int
      from pacote_itens pi join servicos sv on sv.id = pi.servico_id where pi.pacote_id = p.id;
    end loop;
    -- cashback sobre o que foi pago em dinheiro de verdade (sem gorjeta, pacote usado, cashback e sinal)
    if s.cashback_percentual > 0 and new.cliente_id is not null then
      select coalesce(sum(valor_centavos), 0) into v_base from comanda_pagamentos
      where comanda_id = new.id and forma::text not in ('pacote', 'cashback', 'vale_presente');
      v_base := v_base - coalesce((select sum(preco_centavos) from comanda_itens where comanda_id = new.id and tipo = 'gorjeta'), 0);
      if round(v_base * s.cashback_percentual / 100) >= 1 then
        insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, expira_em)
        values (new.salao_id, new.cliente_id, 'credito', round(v_base * s.cashback_percentual / 100)::int, new.id, now() + make_interval(days => s.cashback_validade_dias));
      end if;
    end if;
  elsif new.status = 'aberta' and old.status = 'fechada' then
    if exists (select 1 from pacotes_cliente pc join pacote_saldos ps on ps.pacote_cliente_id = pc.id where pc.comanda_id = new.id and ps.usado > 0) then
      raise exception 'pacote_ja_usado' using errcode = '55000';
    end if;
    -- cashback desta comanda que já foi gasto: não dá para desfazer
    select coalesce(sum(valor_centavos), 0) into v_cb from cashback_movimentos where comanda_id = new.id and tipo = 'credito' and expira_em > now();
    if v_cb > 0 and saldo_cashback(old.cliente_id) < v_cb then
      raise exception 'cashback_ja_usado' using errcode = '55000';
    end if;
    delete from pacotes_cliente where comanda_id = new.id;
    delete from cashback_movimentos where comanda_id = new.id and tipo = 'credito';
  end if;
  return new;
end
$$;

-- Um uso de cashback de cada vez por cliente e por comanda.
create or replace function usar_cashback(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v int;
  v_pag uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null or c.cliente_id is null then return 0; end if;
  perform 1 from clientes where id = c.cliente_id for update;  -- um uso de cada vez por cliente
  select * into t from total_comanda(p_comanda);
  v := least(saldo_cashback(c.cliente_id), t.total - t.pago);
  if v <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'cashback', v) returning id into v_pag;
  insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, comanda_pagamento_id) values (c.salao_id, c.cliente_id, 'uso', -v, c.id, v_pag);
  return v;
end
$$;

create or replace function usar_vale_presente(p_comanda uuid, p_codigo text) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  v vales_presente;
  t record;
  x int;
  v_pag uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  select * into v from vales_presente where salao_id = c.salao_id and codigo = upper(trim(p_codigo)) for update;
  if v.id is null then raise exception 'vale_nao_encontrado' using errcode = 'P0002'; end if;
  if v.estado <> 'ativo' or v.expira_em < now() then raise exception 'vale_vencido' using errcode = '55000'; end if;
  if v.comanda_id = c.id then raise exception 'vale_da_propria_comanda' using errcode = '22023'; end if;
  select * into t from total_comanda(p_comanda);
  x := least(v.saldo_centavos, t.total - t.pago);
  if x <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'vale_presente', x) returning id into v_pag;
  update vales_presente set saldo_centavos = saldo_centavos - x where id = v.id;
  insert into vale_presente_usos (salao_id, vale_id, comanda_pagamento_id, valor_centavos) values (c.salao_id, v.id, v_pag, x);
  return x;
end
$$;

create or replace function usar_pacote(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  i comanda_itens;
  sd pacote_saldos;
  v_pag uuid;
  n int := 0;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null or c.cliente_id is null then return 0; end if;
  for i in select * from comanda_itens it where it.comanda_id = c.id and it.tipo = 'servico' and it.quantidade = 1
             and not exists (select 1 from pacote_usos u where u.comanda_item_id = it.id) loop
    sd := null;
    select ps.* into sd from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id
    where pc.cliente_id = c.cliente_id and pc.estado = 'ativo' and pc.expira_em > now() and ps.servico_id = i.servico_id and ps.usado < ps.total
    order by pc.expira_em limit 1 for update of ps;
    continue when sd.id is null;
    update comanda_itens set preco_centavos = sd.valor_unitario_centavos, desconto_centavos = 0 where id = i.id;
    if sd.valor_unitario_centavos > 0 then
      insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'pacote', sd.valor_unitario_centavos) returning id into v_pag;
    else
      v_pag := gen_random_uuid();
    end if;
    update pacote_saldos set usado = usado + 1 where id = sd.id;
    insert into pacote_usos (salao_id, saldo_id, comanda_item_id, comanda_pagamento_id, preco_original_centavos, desconto_original_centavos)
    values (c.salao_id, sd.id, i.id, v_pag, i.preco_centavos, i.desconto_centavos);
    n := n + 1;
  end loop;
  return n;
end
$$;
-- Belezando · correções da quinta revisão (robô com atendimento de vários serviços, pagamento de comissão em dobro).

-- Um item por atendimento: serviços juntos ("Coloração + Corte"), com o id do primeiro.
create or replace function agendamentos_whatsapp(p_salao uuid, p_conversa uuid)
returns table (id uuid, inicio timestamptz, servico text, profissional text)
language sql stable security definer set search_path = public, pg_temp as
$$
  select (array_agg(a.id order by a.inicio))[1], min(a.inicio),
         string_agg(s.nome, ' + ' order by a.inicio), string_agg(distinct m.nome, ', ')
  from conversas v
  join clientes p on p.salao_id = v.salao_id
    and (p.id = v.cliente_id or tel_nacional(p.telefone) = v.telefone)
  join agendamentos a on a.cliente_id = p.id and a.salao_id = v.salao_id
  join servicos s on s.id = a.servico_id
  join membros m on m.user_id = a.profissional_id
  where v.id = p_conversa and v.salao_id = p_salao
    and a.status in ('agendado', 'confirmado') and a.inicio > now()
  group by coalesce(a.grupo_id, a.id)
  order by min(a.inicio)
  limit 10
$$;

create or replace function pagar_profissional(p_prof uuid, p_inicio date, p_fim date, p_forma text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_com int; v_gor int; v_val int := 0;
  v_id uuid;
  x vales;
  v_quitar uuid[] := '{}';
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador registra pagamento' using errcode = '42501'; end if;
  if p_fim < p_inicio then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  perform 1 from membros where user_id = p_prof and salao_id = v_salao for update;  -- um pagamento de cada vez por profissional
  if not found then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
  select coalesce(sum(valor_centavos) filter (where papel <> 'gorjeta'), 0), coalesce(sum(valor_centavos) filter (where papel = 'gorjeta'), 0)
    into v_com, v_gor from comissoes
  where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  if v_com + v_gor = 0 then raise exception 'nada_a_pagar' using errcode = '22023'; end if;
  -- desconta os vales do mais antigo ao mais novo enquanto couberem; o que não couber fica para o próximo pagamento
  for x in select * from vales where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and data <= p_fim order by data, criado_em loop
    exit when v_val + x.valor_centavos > v_com + v_gor;
    v_val := v_val + x.valor_centavos;
    v_quitar := v_quitar || x.id;
  end loop;
  insert into fechamentos_comissao (salao_id, profissional_id, periodo_inicio, periodo_fim, comissoes_centavos, gorjetas_centavos, vales_centavos, pago_centavos, forma)
  values (v_salao, p_prof, p_inicio, p_fim, v_com, v_gor, v_val, v_com + v_gor - v_val, left(p_forma, 40)) returning id into v_id;
  update comissoes set fechamento_id = v_id where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  update vales set fechamento_id = v_id where id = any (v_quitar);
  return v_id;
end
$$;
-- Belezando · correções da sexta revisão.

-- Sinal pago por Pix depois do prazo, com o horário já ocupado por outra cliente: antes dava erro e a recepção não conseguia registrar o pagamento.
create or replace function confirmar_sinal(p_agendamento uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção confirmam sinal' using errcode = '42501'; end if;
  update sinais set status = 'pago', pago_em = now(), confirmado_por = auth.uid()
  where agendamento_id = p_agendamento and salao_id = meu_salao() and status in ('pendente', 'expirado');
  if not found then raise exception 'sinal_nao_encontrado' using errcode = 'P0002'; end if;
  begin
    update agendamentos set status = 'confirmado' where id in (select id from do_grupo(p_agendamento)) and status in ('agendado', 'cancelado');
  exception when exclusion_violation then
    -- pagou depois do prazo e o horário já foi ocupado: o sinal vira crédito
    update sinais set status = 'credito' where agendamento_id = p_agendamento and salao_id = meu_salao();
  end;
end
$$;
-- Belezando · segurança do agendamento online (limite de marcações por endereço e por salão).

create index if not exists aceites_ip_idx on aceites_politica (ip, aceito_em);
create index if not exists aceites_salao_idx on aceites_politica (salao_id, aceito_em);

create or replace function agendar_online_grupo(
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
  v_novo boolean := false;
  v_fases jsonb := '[]';
  v_grupo uuid;
  v_t timestamptz;
  v_lider agendamentos;
  v_sid uuid;
  k int;
begin
  select * into c from saloes where slug = lower(p_slug) and agendamento_online;
  if c.id is null then raise exception 'salao_indisponivel' using errcode = 'P0002'; end if;
  -- Contra robô que lota a agenda com clientes falsas (e manda WhatsApp para números de estranhos):
  -- até 5 marcações por hora do mesmo endereço e 40 por hora no salão.
  if p_ip is not null and (select count(distinct agendamento_id) from aceites_politica where ip = p_ip and aceito_em > now() - interval '1 hour') >= 5 then
    raise exception 'muitas_tentativas' using errcode = '54000';
  end if;
  if (select count(distinct agendamento_id) from aceites_politica where salao_id = c.id and aceito_em > now() - interval '1 hour') >= 40 then
    raise exception 'muitas_tentativas' using errcode = '54000';
  end if;
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
    insert into clientes (salao_id, nome, telefone, consentimento_em) values (c.id, left(trim(p_nome), 120), v_tel, now()) returning id into v_cli;
    v_novo := true;
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
  return jsonb_build_object('agendamento_id', v_ag.id, 'token', v_ag.token, 'sinal_centavos', v_sinal, 'cliente_novo', v_novo);
end
$$;
-- Belezando · limite de tentativas (login, cadastro). O login passa pelo servidor do app, então o Supabase
-- vê todas as tentativas vindo do mesmo endereço: o limite por pessoa (endereço e e-mail) fica aqui.

create table tentativas (
  chave text not null check (length(chave) <= 200),
  em timestamptz not null default now()
);
create index on tentativas (chave, em);
alter table tentativas enable row level security;
revoke all on tentativas from anon, authenticated;

-- Registra uma tentativa e diz se ainda está dentro do limite. Só o servidor (chave de serviço) chama.
create function registrar_tentativa(p_chave text, p_limite int, p_janela_min int) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  n int;
begin
  perform pg_advisory_xact_lock(hashtext(p_chave));
  delete from tentativas where chave = p_chave and em < now() - make_interval(mins => p_janela_min);
  select count(*) into n from tentativas where chave = p_chave;
  if n >= p_limite then return false; end if;
  insert into tentativas (chave) values (left(p_chave, 200));
  return true;
end
$$;
revoke all on function registrar_tentativa(text, int, int) from public, anon, authenticated;
grant execute on function registrar_tentativa(text, int, int) to service_role;

-- Limpeza do que já passou da janela (chamada pelo agendador junto com os lembretes).
create function limpar_tentativas() returns void
language sql security definer set search_path = public, pg_temp as
$$ delete from tentativas where em < now() - interval '1 day' $$;
revoke all on function limpar_tentativas() from public, anon, authenticated;
grant execute on function limpar_tentativas() to service_role;
-- Belezando · Barba masculina entre os serviços de partida, e serviço avulso ("Outro") na agenda.

-- Serviço avulso: digitado na hora da marcação. Não aparece no catálogo, no link nem no robô.
alter table servicos add column avulso boolean not null default false;

-- A recepção marca "Outro" com nome e duração: reaproveita o avulso igual ou cria um (só o administrador mexe no catálogo,
-- então a criação passa por esta função, que só cria serviço inativo e fora do link).
create function servico_avulso(p_nome text, p_min int) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_nome text := left(regexp_replace(trim(coalesce(p_nome, '')), '\s+', ' ', 'g'), 120);
  v_id uuid;
begin
  if v_salao is null then raise exception 'não autenticado' using errcode = '42501'; end if;
  if length(v_nome) < 2 then raise exception 'nome_servico' using errcode = '22023'; end if;
  if p_min is null or p_min not between 5 and 480 or p_min % 5 <> 0 then raise exception 'duracao_servico' using errcode = '22023'; end if;
  select id into v_id from servicos where salao_id = v_salao and avulso and lower(nome) = lower(v_nome) and duracao_min = p_min limit 1;
  if v_id is null then
    insert into servicos (salao_id, nome, duracao_min, fases, ativo, online, avulso)
    values (v_salao, v_nome, p_min, jsonb_build_array(jsonb_build_object('tipo', 'trabalho', 'min', p_min)), false, false, true)
    returning id into v_id;
  end if;
  return v_id;
end
$$;
revoke all on function servico_avulso(text, int) from public, anon;
grant execute on function servico_avulso(text, int) to authenticated;

-- Salão novo já nasce com Barba masculina.
create or replace function criar_salao(p_nome text, p_slug text, p_nome_usuario text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_id uuid;
  t constant text := 'trabalho';
  p constant text := 'pausa';
begin
  if auth.uid() is null then raise exception 'não autenticado' using errcode = '28000'; end if;
  if exists (select 1 from membros where user_id = auth.uid()) then raise exception 'usuário já pertence a um salão' using errcode = '23505'; end if;
  insert into saloes (nome, slug) values (trim(p_nome), lower(trim(p_slug))) returning id into v_id;
  insert into membros (user_id, salao_id, papel, nome) values (auth.uid(), v_id, 'admin', trim(p_nome_usuario));
  insert into servicos (salao_id, nome, duracao_min, fases, retorno_dias) values
    (v_id, 'Corte feminino', 60, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 60)), 45),
    (v_id, 'Corte masculino', 30, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 30)), 30),
    (v_id, 'Barba masculina', 30, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 30)), 21),
    (v_id, 'Escova', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45)), null),
    (v_id, 'Coloração', 120, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 40), jsonb_build_object('tipo', p, 'min', 40), jsonb_build_object('tipo', t, 'min', 40)), 35),
    (v_id, 'Hidratação', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 15), jsonb_build_object('tipo', p, 'min', 20), jsonb_build_object('tipo', t, 'min', 10)), 21),
    (v_id, 'Manicure', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45)), 14),
    (v_id, 'Pedicure', 45, jsonb_build_array(jsonb_build_object('tipo', t, 'min', 45)), 21);
  return v_id;
end
$$;

-- Salões que já existem ganham Barba masculina (se ainda não tiverem uma barba no catálogo).
insert into servicos (salao_id, nome, duracao_min, fases, retorno_dias)
select s.id, 'Barba masculina', 30, jsonb_build_array(jsonb_build_object('tipo', 'trabalho', 'min', 30)), 21
from saloes s where not exists (select 1 from servicos v where v.salao_id = s.id and v.nome ilike '%barba%');
-- Belezando · aniversário com presente, robô que remarca o atendimento inteiro e lista de espera avisada em remarcações.

-- ───────────── 1) Aniversário ─────────────
-- No dia do aniversário (no horário de mensagens do salão) a cliente recebe parabéns e, se o salão quiser,
-- um crédito de presente que entra como cashback (já desconta sozinho na comanda pelo botão de cashback).
alter table saloes add column aniversario_ativo boolean not null default false;
alter table saloes add column aniversario_credito_centavos int not null default 2000 check (aniversario_credito_centavos between 0 and 100000);
alter table saloes add column aniversario_validade_dias int not null default 30 check (aniversario_validade_dias between 7 and 90);
grant update (aniversario_ativo, aniversario_credito_centavos, aniversario_validade_dias) on saloes to authenticated;

alter table avisos drop constraint avisos_tipo_check;
alter table avisos add constraint avisos_tipo_check check (tipo in ('retorno', 'vaga', 'avaliacao', 'aniversario'));

create function programar_aniversarios() returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  n int;
begin
  with alvo as (
    select c.id cliente_id, c.salao_id, c.nascimento, s.aniversario_credito_centavos credito, s.aniversario_validade_dias validade, s.fuso, s.retorno_hora,
           (now() at time zone s.fuso)::date hoje
    from clientes c join saloes s on s.id = c.salao_id and s.aniversario_ativo
    where c.nascimento is not null and cliente_contatavel(c)
  ), aniversariantes as (
    select * from alvo
    where to_char(nascimento, 'MM-DD') = to_char(hoje, 'MM-DD')
       -- quem nasceu em 29/02 comemora em 28/02 nos anos que não são bissextos
       or (to_char(nascimento, 'MM-DD') = '02-29' and to_char(hoje, 'MM-DD') = '02-28'
           and extract(day from (date_trunc('year', hoje) + interval '2 months' - interval '1 day')) = 28)
  ), novos as (
    insert into avisos (salao_id, cliente_id, tipo, chave, dados, enviar_em)
    select salao_id, cliente_id, 'aniversario', 'aniversario:' || cliente_id || ':' || extract(year from hoje),
      jsonb_build_object('credito', credito, 'ate', to_char(hoje + validade, 'DD/MM')),
      greatest(now(), (hoje + retorno_hora) at time zone fuso)
    from aniversariantes
    on conflict (salao_id, chave) do nothing
    returning salao_id, cliente_id
  ), presentes as (
    insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, expira_em)
    select a.salao_id, a.cliente_id, 'credito', a.credito, now() + make_interval(days => a.validade)
    from novos x join aniversariantes a on a.cliente_id = x.cliente_id where a.credito > 0
    returning 1
  )
  select count(*) into n from novos;
  return n;
end
$$;

revoke all on function programar_aniversarios() from public, anon, authenticated;
grant execute on function programar_aniversarios() to service_role;

-- ───────────── 2) Robô remarca o atendimento inteiro ─────────────
-- Mesma regra do link: tudo muda junto, o horário antigo só sai se o novo couber. Profissionais diferentes ficam com a equipe.
create function remarcar_whatsapp(p_salao uuid, p_conversa uuid, p_agendamento uuid, p_inicio timestamptz, p_profissional uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a agendamentos;
  v_fases jsonb := '[]';
  r record;
  v_t timestamptz;
begin
  if not exists (select 1 from agendamentos_whatsapp(p_salao, p_conversa) x where x.id = p_agendamento) then return 'nao_encontrado'; end if;
  select * into a from agendamentos where id = p_agendamento and salao_id = p_salao for update;
  if a.id is null or a.status not in ('agendado', 'confirmado') then return 'nao_encontrado'; end if;
  if (select count(distinct profissional_id) from do_grupo(a.id) where status in ('agendado', 'confirmado')) > 1 then return 'varios_profissionais'; end if;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = p_salao and ativo and papel in ('admin', 'profissional')) then return 'dados_invalidos'; end if;
  select coalesce(jsonb_agg(f order by g.inicio, ord), '[]') into v_fases
  from do_grupo(a.id) g, jsonb_array_elements(g.fases) with ordinality as e(f, ord) where g.status in ('agendado', 'confirmado');
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(p_salao, p_profissional, p_inicio, v_fases) then return 'horario_indisponivel'; end if;
  v_t := p_inicio;
  begin
    delete from ocupacoes where agendamento_id in (select id from do_grupo(a.id));
    for r in select * from do_grupo(a.id) where status in ('agendado', 'confirmado') order by inicio loop
      update agendamentos set inicio = v_t, profissional_id = p_profissional where id = r.id returning fim into v_t;
    end loop;
  exception when exclusion_violation then
    return 'horario_indisponivel';
  end;
  return 'remarcado';
end
$$;
revoke all on function remarcar_whatsapp(uuid, uuid, uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function remarcar_whatsapp(uuid, uuid, uuid, timestamptz, uuid) to service_role;

-- ───────────── 3) Lista de espera também quando alguém remarca ─────────────
-- O horário que vagou é o antigo (old): vale para cancelamento e para mudança de dia, hora ou profissional.
create or replace function avisar_lista_espera() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_local timestamp;
  v_periodo text;
  e record;
begin
  if old.status not in ('agendado', 'confirmado') or old.inicio < now() + interval '1 hour' then return new; end if;
  if not ((new.status = 'cancelado')
          or (new.status in ('agendado', 'confirmado') and (new.inicio <> old.inicio or new.profissional_id <> old.profissional_id))) then
    return new;
  end if;
  select * into s from saloes where id = old.salao_id;
  if not s.espera_ativa then return new; end if;
  v_local := old.inicio at time zone s.fuso;
  v_periodo := case when v_local::time < '12:00' then 'manha' when v_local::time < '18:00' then 'tarde' else 'noite' end;
  for e in
    select l.* from lista_espera l join clientes c on c.id = l.cliente_id
    where l.salao_id = old.salao_id and l.estado in ('aguardando', 'avisado') and l.servico_id = old.servico_id
      and v_local::date between l.data_de and l.data_ate
      and (l.periodo = 'qualquer' or l.periodo = v_periodo)
      and (l.profissional_id is null or l.profissional_id = old.profissional_id)
      and l.cliente_id <> old.cliente_id and cliente_contatavel(c)
    order by l.criado_em limit 3
  loop
    insert into avisos (salao_id, cliente_id, tipo, chave, dados)
    values (old.salao_id, e.cliente_id, 'vaga', 'vaga:' || e.id || ':' || old.id || ':' || extract(epoch from old.inicio)::bigint,
            jsonb_build_object('servico_id', old.servico_id, 'profissional_id', old.profissional_id, 'inicio', old.inicio, 'espera_id', e.id))
    on conflict (salao_id, chave) do nothing;
    update lista_espera set estado = 'avisado', avisado_em = now() where id = e.id;
  end loop;
  return new;
end
$$;
drop trigger espera_vaga on agendamentos;
create trigger espera_vaga after update of status, inicio, profissional_id on agendamentos for each row execute function avisar_lista_espera();
-- Belezando · desempenho das regras de acesso (RLS).
-- meu_salao(), meu_papel() e auth.uid() dentro de "(select ...)" são calculados uma vez por consulta, não uma vez por linha.
-- Com milhares de agendamentos e comandas, isso é a diferença entre a tela abrir na hora ou demorar.
do $$
declare
  p record;
  usar text;
  conferir text;
  troca constant text[] := array['meu_salao()', 'meu_papel()', 'auth.uid()'];
  f text;
begin
  for p in select schemaname, tablename, policyname, qual, with_check from pg_policies where schemaname = 'public' loop
    usar := p.qual;
    conferir := p.with_check;
    foreach f in array troca loop
      -- só o que ainda não está dentro de um select
      usar := regexp_replace(usar, '(?<![Ss][Ee][Ll][Ee][Cc][Tt] )' || replace(replace(f, '(', '\('), ')', '\)'), '(select ' || f || ')', 'g');
      conferir := regexp_replace(conferir, '(?<![Ss][Ee][Ll][Ee][Cc][Tt] )' || replace(replace(f, '(', '\('), ')', '\)'), '(select ' || f || ')', 'g');
    end loop;
    if usar is distinct from p.qual then
      execute format('alter policy %I on %I.%I using (%s)', p.policyname, p.schemaname, p.tablename, usar);
    end if;
    if conferir is distinct from p.with_check then
      execute format('alter policy %I on %I.%I with check (%s)', p.policyname, p.schemaname, p.tablename, conferir);
    end if;
  end loop;
end $$;

-- Tabela de tentativas ganha chave primária (o Supabase recomenda; ajuda na limpeza).
alter table tentativas add column id bigint generated always as identity primary key;
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
-- A ficha só pede a data de nascimento quando o cadastro ainda não tem (quem marcou sozinha pelo link ou WhatsApp).
create or replace function ficha_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'slug', s.slug, 'cliente', split_part(c.nome, ' ', 1), 'respondida', f.respondida_em is not null,
    'expirada', f.expira_em < now() and f.respondida_em is null, 'pedir_nascimento', c.nascimento is null)
  from fichas_previas f join clientes c on c.id = f.cliente_id join saloes s on s.id = f.salao_id
  where f.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;
-- Promoções e horários vazios, etiquetas e campanhas no WhatsApp, vitrine pública do salão, avisos para a equipe,
-- nota fiscal de serviço e termos com assinatura digital.

-- ───────────── promoções (dia/horário fixo ou última hora) ─────────────
create table promocoes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 60),
  tipo text not null check (tipo in ('horario', 'ultima_hora')),
  percentual int not null check (percentual between 5 and 70),
  dias_semana int[] not null default '{1,2,3,4,5,6,7}' check (dias_semana <@ '{1,2,3,4,5,6,7}' and cardinality(dias_semana) between 1 and 7),
  hora_inicio time,
  hora_fim time,
  horas_antes int check (horas_antes between 1 and 72),   -- última hora: vale para horários que começam em até X horas
  servico_ids uuid[] check (servico_ids is null or cardinality(servico_ids) between 1 and 50),   -- nulo = todos os serviços
  valida_ate date,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  check (hora_inicio is null or hora_fim is null or hora_fim > hora_inicio),
  check (tipo <> 'ultima_hora' or horas_antes is not null)
);
create index on promocoes (salao_id) where ativa;
alter table promocoes enable row level security;
create policy promo_ler on promocoes for select to authenticated using (salao_id = (select meu_salao()));
create policy promo_criar on promocoes for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy promo_editar on promocoes for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy promo_apagar on promocoes for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on promocoes from anon, authenticated;
grant select, delete on promocoes to authenticated;
grant insert (nome, tipo, percentual, dias_semana, hora_inicio, hora_fim, horas_antes, servico_ids, valida_ate, ativa) on promocoes to authenticated;
grant update (ativa) on promocoes to authenticated;

-- A maior promoção que vale para aquele serviço naquele horário (no fuso do salão). Promoções são públicas (aparecem no link).
create function promocao_em(p_salao uuid, p_servico uuid, p_inicio timestamptz, p_agora timestamptz default now()) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('id', p.id, 'nome', p.nome, 'percentual', p.percentual)
  from promocoes p join saloes s on s.id = p.salao_id
  cross join lateral (select p_inicio at time zone s.fuso as l) t
  where p.salao_id = p_salao and p.ativa
    and (p.valida_ate is null or t.l::date <= p.valida_ate)
    and (p.servico_ids is null or p_servico = any (p.servico_ids))
    and extract(isodow from t.l)::int = any (p.dias_semana)
    and (p.hora_inicio is null or t.l::time >= p.hora_inicio)
    and (p.hora_fim is null or t.l::time < p.hora_fim)
    and (p.tipo = 'horario' or (p_inicio > p_agora and p_inicio <= p_agora + make_interval(hours => p.horas_antes)))
  order by p.percentual desc, p.criado_em
  limit 1
$$;
revoke all on function promocao_em(uuid, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function promocao_em(uuid, uuid, timestamptz, timestamptz) to authenticated, service_role;

-- O desconto fica gravado no horário quando ele é marcado (ou remarcado): a comanda usa esse valor.
alter table agendamentos add column promocao_percentual int not null default 0 check (promocao_percentual between 0 and 70);
alter table agendamentos add column promocao_nome text check (length(promocao_nome) <= 60);
create function aplicar_promocao() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v jsonb;
begin
  if tg_op = 'UPDATE' and new.inicio = old.inicio and new.servico_id = old.servico_id then return new; end if;
  v := promocao_em(new.salao_id, new.servico_id, new.inicio);
  new.promocao_percentual := coalesce((v ->> 'percentual')::int, 0);
  new.promocao_nome := v ->> 'nome';
  return new;
end
$$;
revoke execute on function aplicar_promocao() from public, anon, authenticated;
create trigger aplicar_promocao before insert or update of inicio, servico_id on agendamentos for each row execute function aplicar_promocao();

-- ───────────── etiquetas e campanhas pelo WhatsApp ─────────────
create function etiquetas_ok(e text[]) returns boolean
language sql immutable as
$$ select cardinality(e) <= 10 and coalesce((select bool_and(length(x) between 1 and 30 and x = lower(trim(x))) from unnest(e) x), true) $$;
alter table clientes add column etiquetas text[] not null default '{}' check (etiquetas_ok(etiquetas));
create index on clientes using gin (etiquetas);
grant insert (etiquetas) on clientes to authenticated;
grant update (etiquetas) on clientes to authenticated;

create table campanhas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 60),
  mensagem text not null check (length(mensagem) between 10 and 500),
  etiquetas text[] not null default '{}' check (etiquetas_ok(etiquetas)),   -- vazio = todas as clientes
  sumidas_dias int check (sumidas_dias between 30 and 730),                -- só quem não vem há tantos dias
  total int not null default 0,
  criada_por uuid default auth.uid(),
  criada_em timestamptz not null default now(),
  disparada_em timestamptz
);
create index on campanhas (salao_id, criada_em desc);
alter table campanhas enable row level security;
create policy camp_ler on campanhas for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy camp_criar on campanhas for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy camp_apagar on campanhas for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin' and disparada_em is null);
revoke all on campanhas from anon, authenticated;
grant select, delete on campanhas to authenticated;
grant insert (nome, mensagem, etiquetas, sumidas_dias) on campanhas to authenticated;

-- Quem recebe: aceitou mensagens, não pediu PARAR, não está bloqueada; com etiqueta (se houver) e sumida (se pedido).
create function publico_campanha(p_salao uuid, p_etiquetas text[], p_sumidas_dias int) returns setof uuid
language sql stable security definer set search_path = public, pg_temp as
$$
  select c.id from clientes c
  where c.salao_id = p_salao and cliente_contatavel(c) and not c.bloqueada
    and (cardinality(coalesce(p_etiquetas, '{}')) = 0 or c.etiquetas && p_etiquetas)
    and (p_sumidas_dias is null or not exists (
      select 1 from agendamentos a where a.cliente_id = c.id and a.status not in ('cancelado', 'faltou')
        and a.inicio > now() - make_interval(days => p_sumidas_dias)))
$$;
revoke all on function publico_campanha(uuid, text[], int) from public, anon, authenticated;

create function contar_publico_campanha(p_etiquetas text[], p_sumidas_dias int) returns int
language plpgsql stable security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador faz campanhas' using errcode = '42501'; end if;
  return (select count(*) from publico_campanha(meu_salao(), p_etiquetas, p_sumidas_dias));
end
$$;
revoke all on function contar_publico_campanha(text[], int) from public, anon;
grant execute on function contar_publico_campanha(text[], int) to authenticated;

alter table avisos drop constraint avisos_tipo_check;
alter table avisos add constraint avisos_tipo_check check (tipo in ('retorno', 'vaga', 'avaliacao', 'aniversario', 'campanha'));

-- Dispara: uma campanha por dia no máximo (protege o número do salão de bloqueio por excesso), até 2.000 clientes.
create function disparar_campanha(p_id uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v campanhas;
  v_n int;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador faz campanhas' using errcode = '42501'; end if;
  select * into v from campanhas where id = p_id and salao_id = meu_salao() for update;
  if v.id is null then raise exception 'campanha não encontrada' using errcode = 'P0002'; end if;
  if v.disparada_em is not null then raise exception 'campanha_ja_disparada' using errcode = '23505'; end if;
  if exists (select 1 from campanhas where salao_id = v.salao_id and disparada_em > now() - interval '24 hours') then
    raise exception 'uma_campanha_por_dia' using errcode = '54000';
  end if;
  insert into avisos (salao_id, cliente_id, tipo, chave, dados, enviar_em)
  select v.salao_id, x.id, 'campanha', 'camp:' || v.id || ':' || x.id, jsonb_build_object('campanha_id', v.id, 'texto', v.mensagem),
         now() + make_interval(secs => (row_number() over () / 30) * 60)
  from (select p.id from publico_campanha(v.salao_id, v.etiquetas, v.sumidas_dias) as p(id) limit 2000) x
  on conflict (salao_id, chave) do nothing;
  get diagnostics v_n = row_count;
  update campanhas set disparada_em = now(), total = v_n where id = v.id;
  return v_n;
end
$$;
revoke all on function disparar_campanha(uuid) from public, anon;
grant execute on function disparar_campanha(uuid) to authenticated;

-- ───────────── vitrine pública: fotos, descrição e avaliações ─────────────
alter table saloes add column descricao text check (length(descricao) <= 600);
alter table saloes add column instagram text check (instagram ~ '^[A-Za-z0-9._]{1,30}$');
alter table saloes add column vitrine_ativa boolean not null default true;
grant update (descricao, instagram, vitrine_ativa) on saloes to authenticated;

create table vitrine_fotos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  caminho text not null check (length(caminho) between 5 and 300),
  legenda text check (length(legenda) <= 80),
  foto_cliente_id uuid references fotos_cliente (id) on delete cascade,   -- veio da ficha de uma cliente (que autorizou)
  criado_em timestamptz not null default now()
);
create index on vitrine_fotos (salao_id, criado_em desc);
create trigger foto_na_pasta before insert or update on vitrine_fotos for each row execute function foto_na_pasta();
alter table vitrine_fotos enable row level security;
create policy vit_ler on vitrine_fotos for select to authenticated using (salao_id = (select meu_salao()));
create policy vit_criar on vitrine_fotos for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao') and foto_cliente_id is null);
create policy vit_apagar on vitrine_fotos for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao'));
revoke all on vitrine_fotos from anon, authenticated;
grant select, delete on vitrine_fotos to authenticated;
grant insert (caminho, legenda) on vitrine_fotos to authenticated;

-- No máximo 40 fotos na vitrine.
create function limite_vitrine() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if (select count(*) from vitrine_fotos where salao_id = new.salao_id) >= 40 then raise exception 'vitrine_cheia' using errcode = '54000'; end if;
  return new;
end
$$;
revoke execute on function limite_vitrine() from public, anon, authenticated;
create trigger limite_vitrine before insert on vitrine_fotos for each row execute function limite_vitrine();

-- Foto da ficha vai para a vitrine só com a autorização de uso de imagem da cliente.
create function publicar_foto_cliente(p_foto uuid, p_legenda text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  f fotos_cliente;
  v_id uuid;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  select * into f from fotos_cliente where id = p_foto and salao_id = meu_salao();
  if f.id is null then raise exception 'foto não encontrada' using errcode = 'P0002'; end if;
  if not exists (select 1 from clientes where id = f.cliente_id and consentimento_imagem_em is not null) then
    raise exception 'sem_autorizacao_imagem' using errcode = '42501';
  end if;
  select id into v_id from vitrine_fotos where foto_cliente_id = f.id;
  if v_id is not null then return v_id; end if;
  insert into vitrine_fotos (salao_id, caminho, legenda, foto_cliente_id) values (f.salao_id, f.caminho, left(nullif(trim(p_legenda), ''), 80), f.id) returning id into v_id;
  return v_id;
end
$$;
revoke all on function publicar_foto_cliente(uuid, text) from public, anon;
grant execute on function publicar_foto_cliente(uuid, text) to authenticated;

-- Retirar a autorização de imagem tira as fotos dela da vitrine.
create function vitrine_sem_autorizacao() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if old.consentimento_imagem_em is not null and new.consentimento_imagem_em is null then
    delete from vitrine_fotos v using fotos_cliente f where v.foto_cliente_id = f.id and f.cliente_id = new.id;
  end if;
  return null;
end
$$;
revoke execute on function vitrine_sem_autorizacao() from public, anon, authenticated;
create trigger vitrine_sem_autorizacao after update of consentimento_imagem_em on clientes for each row execute function vitrine_sem_autorizacao();

-- O comentário só aparece na página do salão se a cliente deixar.
alter table avaliacoes add column publica boolean not null default false;
grant select (publica) on avaliacoes to authenticated;
drop function responder_avaliacao(text, int, text);
create function responder_avaliacao(p_token text, p_nota int, p_comentario text, p_publica boolean default false) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a avaliacoes;
begin
  select * into a from avaliacoes where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if a.id is null then return 'nao_encontrada'; end if;
  if a.respondida_em is not null then return 'ja_respondida'; end if;
  if a.criado_em < now() - interval '15 days' then return 'expirada'; end if;
  if p_nota is null or p_nota not between 0 and 10 then return 'invalida'; end if;
  update avaliacoes set nota = p_nota, comentario = left(nullif(trim(p_comentario), ''), 1000), respondida_em = now(),
    publica = coalesce(p_publica, false) and nullif(trim(p_comentario), '') is not null
  where id = a.id;
  return 'respondida';
end
$$;
revoke all on function responder_avaliacao(text, int, text, boolean) from public, anon, authenticated;
grant execute on function responder_avaliacao(text, int, text, boolean) to service_role;

-- ───────────── avisos para a equipe (no sistema e no WhatsApp do profissional) ─────────────
alter table membros add column telefone text check (telefone ~ '^[0-9]{10,13}$');
alter table membros add column avisos_whatsapp boolean not null default false;
grant update (telefone, avisos_whatsapp) on membros to authenticated;

create table avisos_equipe (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  membro_id uuid not null,
  agendamento_id uuid,
  tipo text not null check (tipo in ('novo', 'mudou', 'cancelou')),
  dados jsonb not null default '{}',
  criado_em timestamptz not null default now(),
  lido_em timestamptz,
  whatsapp text not null default 'nao' check (whatsapp in ('nao', 'pendente', 'enviando', 'enviado', 'falhou')),
  tentativas int not null default 0,
  reservado_em timestamptz,
  wa_msg_id text,
  erro text check (length(erro) <= 500),
  foreign key (membro_id, salao_id) references membros (user_id, salao_id) on delete cascade
);
create index on avisos_equipe (membro_id, criado_em desc);
create index on avisos_equipe (criado_em) where whatsapp in ('pendente', 'enviando');
alter table avisos_equipe enable row level security;
create policy aveq_ler on avisos_equipe for select to authenticated using (membro_id = (select auth.uid()) and salao_id = (select meu_salao()));
create policy aveq_marcar on avisos_equipe for update to authenticated using (membro_id = (select auth.uid()) and salao_id = (select meu_salao()));
revoke all on avisos_equipe from anon, authenticated;
grant select (id, salao_id, membro_id, agendamento_id, tipo, dados, criado_em, lido_em) on avisos_equipe to authenticated;
grant update (lido_em) on avisos_equipe to authenticated;

create function avisar_membro(p_membro uuid, a agendamentos, p_tipo text, p_antigo timestamptz) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  m membros;
  v_lote text := coalesce(a.serie_id, a.grupo_id)::text;   -- série que se repete ou visita com vários serviços: um WhatsApp só
begin
  if p_membro = auth.uid() then return; end if;   -- quem mexeu na própria agenda não precisa de aviso
  select * into m from membros where user_id = p_membro and salao_id = a.salao_id and ativo;
  if m.user_id is null then return; end if;
  insert into avisos_equipe (salao_id, membro_id, agendamento_id, tipo, dados, whatsapp)
  values (a.salao_id, p_membro, a.id, p_tipo,
    jsonb_build_object('cliente', (select nome from clientes where id = a.cliente_id),
                       'servico', (select nome from servicos where id = a.servico_id),
                       'inicio', a.inicio, 'inicio_antigo', p_antigo, 'lote', v_lote),
    case when m.avisos_whatsapp and m.telefone is not null
          and not (v_lote is not null and exists (select 1 from avisos_equipe e where e.membro_id = p_membro and e.tipo = p_tipo
                     and e.dados ->> 'lote' = v_lote and e.criado_em > now() - interval '2 minutes'))
         then 'pendente' else 'nao' end);
end
$$;
revoke execute on function avisar_membro(uuid, agendamentos, text, timestamptz) from public, anon, authenticated;

-- Horário online esperando o sinal só vira aviso quando o sinal é pago (se não pagar, nem chega a aparecer).
create function avisar_equipe() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_novo_ativo boolean := new.status in ('agendado', 'confirmado') and not (new.origem = 'online' and new.status = 'agendado');
  v_velho_ativo boolean;
begin
  if new.inicio < now() - interval '1 hour' then return null; end if;
  if tg_op = 'INSERT' then
    if v_novo_ativo then perform avisar_membro(new.profissional_id, new, 'novo', null); end if;
    return null;
  end if;
  v_velho_ativo := old.status in ('agendado', 'confirmado') and not (old.origem = 'online' and old.status = 'agendado');
  if v_velho_ativo and not v_novo_ativo then
    if new.status = 'cancelado' then perform avisar_membro(old.profissional_id, new, 'cancelou', null); end if;
  elsif v_novo_ativo and not v_velho_ativo then
    if old.status in ('agendado', 'confirmado') then perform avisar_membro(new.profissional_id, new, 'novo', null); end if;
  elsif v_novo_ativo then
    if new.profissional_id <> old.profissional_id then
      perform avisar_membro(old.profissional_id, old, 'cancelou', null);
      perform avisar_membro(new.profissional_id, new, 'novo', null);
    elsif new.inicio <> old.inicio then
      perform avisar_membro(new.profissional_id, new, 'mudou', old.inicio);
    end if;
  end if;
  return null;
end
$$;
revoke execute on function avisar_equipe() from public, anon, authenticated;
create trigger avisar_equipe after insert or update of inicio, profissional_id, status on agendamentos for each row execute function avisar_equipe();

create function reservar_avisos_equipe(p_limite int) returns table (
  id uuid, salao_id uuid, tipo text, dados jsonb, wa_id text, membro_nome text, fuso text
)
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update avisos_equipe a set tentativas = a.tentativas + 1, whatsapp = case when a.tentativas + 1 >= 3 then 'falhou' else 'pendente' end
  where a.whatsapp = 'enviando' and a.reservado_em < now() - interval '15 minutes';
  -- aviso velho não serve mais
  update avisos_equipe a set whatsapp = 'falhou', erro = 'passou da hora' where a.whatsapp = 'pendente' and a.criado_em < now() - interval '6 hours';
  return query
  with alvo as (
    select v.id from avisos_equipe v where v.whatsapp = 'pendente' and v.tentativas < 3 order by v.criado_em limit p_limite for update skip locked
  ), marcado as (
    update avisos_equipe v set whatsapp = 'enviando', reservado_em = now() from alvo where v.id = alvo.id returning v.*
  )
  select m.id, m.salao_id, m.tipo, m.dados, '55' || tel_nacional(mb.telefone), mb.nome, s.fuso
  from marcado m join membros mb on mb.user_id = m.membro_id and mb.salao_id = m.salao_id join saloes s on s.id = m.salao_id;
end
$$;
create function concluir_aviso_equipe(p_id uuid, p_ok boolean, p_wa_msg_id text, p_erro text) returns void
language sql security definer set search_path = public, pg_temp as
$$
  update avisos_equipe set whatsapp = case when p_ok then 'enviado' when tentativas + 1 >= 3 then 'falhou' else 'pendente' end,
    tentativas = tentativas + case when p_ok then 0 else 1 end, wa_msg_id = p_wa_msg_id, erro = left(p_erro, 500)
  where id = p_id
$$;
revoke all on function reservar_avisos_equipe(int), concluir_aviso_equipe(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function reservar_avisos_equipe(int), concluir_aviso_equipe(uuid, boolean, text, text) to service_role;

-- ───────────── nota fiscal de serviço (NFS-e) ─────────────
create table fiscal_salao (
  salao_id uuid primary key default meu_salao() references saloes (id) on delete cascade,
  cnpj text check (cnpj ~ '^[0-9]{14}$'),
  razao_social text check (length(razao_social) between 2 and 150),
  inscricao_municipal text check (inscricao_municipal ~ '^[0-9A-Za-z./-]{1,20}$'),
  codigo_municipio text check (codigo_municipio ~ '^[0-9]{7}$'),   -- código IBGE da cidade
  item_lista_servico text check (item_lista_servico ~ '^[0-9]{2}\.?[0-9]{2}$'),   -- 06.01 = cabeleireiros, manicures e afins
  codigo_tributario_municipio text check (length(codigo_tributario_municipio) <= 20),
  aliquota numeric(5, 2) check (aliquota between 0 and 5),
  simples_nacional boolean not null default true,
  ambiente text not null default 'homologacao' check (ambiente in ('homologacao', 'producao')),
  token_emissor text check (length(token_emissor) between 10 and 200),   -- segredo do emissor: só o servidor lê
  ativo boolean not null default false,
  atualizado_em timestamptz not null default now()
);
alter table fiscal_salao enable row level security;
create policy fiscal_ler on fiscal_salao for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy fiscal_criar on fiscal_salao for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy fiscal_editar on fiscal_salao for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on fiscal_salao from anon, authenticated;
grant select (salao_id, cnpj, razao_social, inscricao_municipal, codigo_municipio, item_lista_servico, codigo_tributario_municipio, aliquota, simples_nacional, ambiente, ativo, atualizado_em) on fiscal_salao to authenticated;
grant insert (cnpj, razao_social, inscricao_municipal, codigo_municipio, item_lista_servico, codigo_tributario_municipio, aliquota, simples_nacional, ambiente, token_emissor, ativo) on fiscal_salao to authenticated;
grant update (cnpj, razao_social, inscricao_municipal, codigo_municipio, item_lista_servico, codigo_tributario_municipio, aliquota, simples_nacional, ambiente, token_emissor, ativo, atualizado_em) on fiscal_salao to authenticated;

-- A tela só precisa saber se já existe token (o valor nunca volta para o navegador).
create function fiscal_tem_token() returns boolean
language sql stable security definer set search_path = public, pg_temp as
$$ select exists (select 1 from fiscal_salao where salao_id = meu_salao() and meu_papel() = 'admin' and token_emissor is not null) $$;
revoke all on function fiscal_tem_token() from public, anon;
grant execute on function fiscal_tem_token() to authenticated;

-- As notas são escritas só pelo servidor (que fala com o emissor); a equipe lê.
create table notas_fiscais (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  comanda_id uuid not null,
  ref text not null unique check (length(ref) between 8 and 60),
  status text not null default 'processando' check (status in ('processando', 'autorizada', 'erro', 'cancelada')),
  ambiente text not null check (ambiente in ('homologacao', 'producao', 'simulacao')),
  numero text,
  codigo_verificacao text,
  valor_centavos int not null check (valor_centavos > 0),
  tomador_nome text,
  tomador_documento text check (tomador_documento ~ '^([0-9]{11}|[0-9]{14})$'),
  url_pdf text check (url_pdf ~ '^https://'),
  url_xml text check (url_xml ~ '^https://'),
  mensagem text check (length(mensagem) <= 1000),
  emitida_por uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade
);
create unique index notas_uma_valida on notas_fiscais (comanda_id) where status in ('processando', 'autorizada');
create index on notas_fiscais (salao_id, criado_em desc);
alter table notas_fiscais enable row level security;
-- Comanda com nota emitida (ou em emissão) não reabre: primeiro cancela a nota.
create function comanda_com_nota() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if old.status = 'fechada' and new.status <> 'fechada'
     and exists (select 1 from notas_fiscais where comanda_id = new.id and status in ('processando', 'autorizada')) then
    raise exception 'comanda_com_nota' using errcode = '55000';
  end if;
  return new;
end
$$;
revoke execute on function comanda_com_nota() from public, anon, authenticated;
create trigger comanda_com_nota before update of status on comandas for each row execute function comanda_com_nota();
create policy notas_ler on notas_fiscais for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao'));
revoke all on notas_fiscais from anon, authenticated;
grant select on notas_fiscais to authenticated;

-- ───────────── termos com assinatura digital ─────────────
create table termos_modelos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  tipo text not null check (tipo in ('quimica', 'imagem', 'outro')),
  titulo text not null check (length(titulo) between 3 and 80),
  texto text not null check (length(texto) between 20 and 8000),
  atualizado_em timestamptz not null default now(),
  unique (salao_id, titulo)
);
alter table termos_modelos enable row level security;
create policy tmod_ler on termos_modelos for select to authenticated using (salao_id = (select meu_salao()));
create policy tmod_criar on termos_modelos for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy tmod_editar on termos_modelos for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy tmod_apagar on termos_modelos for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on termos_modelos from anon, authenticated;
grant select, delete on termos_modelos to authenticated;
grant insert (tipo, titulo, texto) on termos_modelos to authenticated;
grant update (titulo, texto, atualizado_em) on termos_modelos to authenticated;

-- Cada termo guarda o texto exatamente como estava na hora (com o hash), quem assinou, a assinatura, IP e aparelho.
create table termos_assinados (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  tipo text not null check (tipo in ('quimica', 'imagem', 'outro')),
  titulo text not null check (length(titulo) between 3 and 80),
  texto text not null check (length(texto) between 20 and 8000),
  texto_hash text not null,
  token_hash text not null unique,
  expira_em timestamptz not null default now() + interval '7 days',
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  assinado_em timestamptz,
  nome_assinado text check (length(nome_assinado) between 3 and 120),
  documento text check (documento ~ '^[0-9]{11}$'),
  respostas jsonb,
  assinatura text check (assinatura ~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' and length(assinatura) <= 400000),
  ip text check (length(ip) <= 64),
  aparelho text check (length(aparelho) <= 300),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on termos_assinados (cliente_id, criado_em desc);
alter table termos_assinados enable row level security;
create policy tass_ler on termos_assinados for select to authenticated using (salao_id = (select meu_salao()));
revoke all on termos_assinados from anon, authenticated;
grant select (id, salao_id, cliente_id, tipo, titulo, texto, texto_hash, expira_em, criado_por, criado_em, assinado_em, nome_assinado, documento, respostas, assinatura, ip, aparelho) on termos_assinados to authenticated;

-- Cria o link de assinatura (segredo aleatório; só o hash fica no banco).
create function criar_termo(p_cliente uuid, p_tipo text, p_titulo text, p_texto text) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not exists (select 1 from clientes where id = p_cliente and salao_id = v_salao) then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  insert into termos_assinados (salao_id, cliente_id, tipo, titulo, texto, texto_hash, token_hash)
  values (v_salao, p_cliente, p_tipo, p_titulo, p_texto, encode(sha256(convert_to(p_texto, 'UTF8')), 'hex'), encode(sha256(convert_to(v_token, 'UTF8')), 'hex'));
  return v_token;
end
$$;
revoke all on function criar_termo(uuid, text, text, text) from public, anon;
grant execute on function criar_termo(uuid, text, text, text) to authenticated;

create function termo_publico(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'cliente', c.nome, 'tipo', t.tipo, 'titulo', t.titulo, 'texto', t.texto,
    'assinado', t.assinado_em is not null, 'assinado_em', t.assinado_em, 'expirado', t.expira_em < now() and t.assinado_em is null)
  from termos_assinados t join clientes c on c.id = t.cliente_id join saloes s on s.id = t.salao_id
  where t.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;

create function assinar_termo(p_token text, p_nome text, p_documento text, p_respostas jsonb, p_assinatura text, p_ip text, p_aparelho text) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  t termos_assinados;
begin
  select * into t from termos_assinados where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if t.id is null then return 'nao_encontrado'; end if;
  if t.assinado_em is not null then return 'ja_assinado'; end if;
  if t.expira_em < now() then return 'expirado'; end if;
  if length(trim(coalesce(p_nome, ''))) < 3 or coalesce(p_assinatura, '') !~ '^data:image/png;base64,' then return 'invalido'; end if;
  update termos_assinados set assinado_em = now(), nome_assinado = left(trim(p_nome), 120), documento = nullif(p_documento, ''),
    respostas = p_respostas, assinatura = p_assinatura, ip = left(p_ip, 64), aparelho = left(p_aparelho, 300)
  where id = t.id;
  if t.tipo = 'imagem' then
    update clientes set consentimento_imagem_em = coalesce(consentimento_imagem_em, now()) where id = t.cliente_id;
  end if;
  return 'assinado';
end
$$;
revoke all on function termo_publico(text), assinar_termo(text, text, text, jsonb, text, text, text) from public, anon, authenticated;
grant execute on function termo_publico(text), assinar_termo(text, text, text, jsonb, text, text, text) to service_role;

-- ───────────── unir cadastros: leva também fila, termos, etiquetas e marcações ─────────────
create or replace function unir_clientes(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  a clientes; b clientes;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção unem cadastros' using errcode = '42501'; end if;
  if p_manter = p_remover then raise exception 'mesmo cadastro' using errcode = '22023'; end if;
  select * into a from clientes where id = p_manter and salao_id = v_salao for update;
  select * into b from clientes where id = p_remover and salao_id = v_salao for update;
  if a.id is null or b.id is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update agendamentos set cliente_id = a.id where cliente_id = b.id;
  -- comandas fechadas também mudam de dono (só o cliente; valores continuam travados)
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', '', true);
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update aceites_politica set cliente_id = a.id where cliente_id = b.id;
  update pacotes_cliente set cliente_id = a.id where cliente_id = b.id;
  update cashback_movimentos set cliente_id = a.id where cliente_id = b.id;
  update lista_espera set cliente_id = a.id where cliente_id = b.id;
  update avisos set cliente_id = a.id where cliente_id = b.id;
  update fichas_previas set cliente_id = a.id where cliente_id = b.id;
  update avaliacoes set cliente_id = a.id where cliente_id = b.id;
  update fila_atendimento set cliente_id = a.id where cliente_id = b.id;
  update termos_assinados set cliente_id = a.id where cliente_id = b.id;
  update vales_presente set comprado_por = a.id where comprado_por = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em),
    vip = a.vip or b.vip, bloqueada = a.bloqueada or b.bloqueada, sempre_sinal = a.sempre_sinal or b.sempre_sinal,
    etiquetas = (select coalesce(array_agg(x), '{}') from (select distinct unnest(a.etiquetas || b.etiquetas) x order by 1 limit 10) e)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;
-- Função das etiquetas com search_path fixo (aviso do Supabase).
alter function etiquetas_ok(text[]) set search_path = public, pg_temp;
-- Sugestão de complemento, fidelidade por níveis, pedido de compra, indique uma amiga, metas e permissões da equipe,
-- cobrança pelo celular (comanda, vale e pacote pelo link), área da cliente, taxa por falta, relatórios com previsão,
-- fichas de estética e a chave da IA no WhatsApp.

alter type tipo_item add value if not exists 'taxa';

-- ───────────── permissões sob medida ─────────────
alter table membros add column permissoes jsonb not null default '{}' check (jsonb_typeof(permissoes) = 'object' and length(permissoes::text) <= 1000);
grant update (permissoes) on membros to authenticated;

-- Administrador pode tudo. Para os outros, vale o que o administrador marcou; sem marcação, o padrão do papel.
create function pode(p_chave text) returns boolean
language sql stable security definer set search_path = public, pg_temp as
$$
  select coalesce((
    select case when m.papel = 'admin' then true
      else coalesce(case when m.permissoes ? p_chave then (m.permissoes ->> p_chave) = 'true' end,
        case p_chave
          when 'desconto' then true
          when 'agenda_outros' then true
          when 'comissoes' then m.papel = 'recepcao'
          when 'estoque' then m.papel = 'recepcao'
          else false
        end) end
    from membros m where m.user_id = auth.uid() and m.ativo), false)
$$;
revoke all on function pode(text) from public, anon;
grant execute on function pode(text) to authenticated;

-- Painel: quem tem a permissão "painel" (além do administrador) vê.
do $$
declare d text;
begin
  select pg_get_functiondef('painel(date,date)'::regprocedure) into d;
  if position('meu_papel() is distinct from ''admin''' in d) = 0 then raise exception 'painel() mudou: revise a troca da permissão'; end if;
  execute replace(d, 'meu_papel() is distinct from ''admin''', 'not pode(''painel'')');
end $$;

-- Divulgar (promoções e campanhas): administrador ou quem tem a permissão "divulgar".
drop policy promo_criar on promocoes; drop policy promo_editar on promocoes; drop policy promo_apagar on promocoes;
create policy promo_criar on promocoes for insert to authenticated with check (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy promo_editar on promocoes for update to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy promo_apagar on promocoes for delete to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')));
drop policy camp_ler on campanhas; drop policy camp_criar on campanhas; drop policy camp_apagar on campanhas;
create policy camp_ler on campanhas for select to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy camp_criar on campanhas for insert to authenticated with check (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy camp_apagar on campanhas for delete to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')) and disparada_em is null);
do $$
declare f text; d text;
begin
  foreach f in array array['contar_publico_campanha(text[],integer)', 'disparar_campanha(uuid)'] loop
    select pg_get_functiondef(f::regprocedure) into d;
    if position('meu_papel() is distinct from ''admin''' in d) = 0 then raise exception '% mudou', f; end if;
    execute replace(d, 'meu_papel() is distinct from ''admin''', 'not pode(''divulgar'')');
  end loop;
end $$;

-- Só vale para o que a pessoa faz direto pela tela: as funções do sistema (security definer) rodam com outro usuário e passam.
-- Por isso estes gatilhos são security invoker: current_user mostra quem está mexendo.
create function checar_agenda_outros() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if current_user <> 'authenticated' then return new; end if;
  if auth.uid() is null or meu_papel() is distinct from 'profissional' or pode('agenda_outros') then return new; end if;
  if tg_op = 'UPDATE' and new.inicio = old.inicio and new.profissional_id = old.profissional_id and new.servico_id = old.servico_id
     and (new.status = old.status or new.status <> 'cancelado') then return new; end if;
  if new.profissional_id <> auth.uid() or (tg_op = 'UPDATE' and old.profissional_id <> auth.uid()) then
    raise exception 'sem_permissao_agenda' using errcode = '42501';
  end if;
  return new;
end
$$;
revoke execute on function checar_agenda_outros() from public, anon, authenticated;
create trigger checar_agenda_outros before insert or update on agendamentos for each row execute function checar_agenda_outros();

-- Desconto na comanda: quem não pode só lança o desconto da promoção do horário.
create function checar_desconto() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
declare
  v_pct int;
  v_novo int := new.desconto_centavos;
begin
  if current_user <> 'authenticated' then return new; end if;
  if auth.uid() is null or pode('desconto') or v_novo = 0 then return new; end if;
  if tg_op = 'UPDATE' and v_novo <= old.desconto_centavos then return new; end if;
  if tg_table_name = 'comanda_itens' then
    if new.agendamento_id is not null then
      select promocao_percentual into v_pct from agendamentos where id = new.agendamento_id;
      if v_novo <= round(new.preco_centavos * new.quantidade * coalesce(v_pct, 0) / 100.0) then return new; end if;
    end if;
  end if;
  raise exception 'sem_permissao_desconto' using errcode = '42501';
end
$$;
revoke execute on function checar_desconto() from public, anon, authenticated;
create trigger checar_desconto before insert or update of desconto_centavos on comanda_itens for each row execute function checar_desconto();
create trigger checar_desconto before update of desconto_centavos on comandas for each row execute function checar_desconto();

-- ───────────── sugestão de complemento ─────────────
alter table servicos add column complementos uuid[] not null default '{}' check (cardinality(complementos) <= 5);
alter table servicos add column produtos_sugeridos uuid[] not null default '{}' check (cardinality(produtos_sugeridos) <= 5);
grant insert (complementos, produtos_sugeridos) on servicos to authenticated;
grant update (complementos, produtos_sugeridos) on servicos to authenticated;

-- ───────────── fidelidade por pontos e níveis ─────────────
create function niveis_ok(n jsonb) returns boolean
language sql immutable set search_path = public, pg_temp as
$$
  select jsonb_typeof(n) = 'array' and jsonb_array_length(n) <= 5 and coalesce((
    select bool_and(jsonb_typeof(x -> 'nome') = 'string' and length(x ->> 'nome') between 1 and 20
      and jsonb_typeof(x -> 'pontos') = 'number' and (x ->> 'pontos')::numeric between 1 and 1000000
      and jsonb_typeof(x -> 'bonus') = 'number' and (x ->> 'bonus')::numeric between 0 and 20)
    from jsonb_array_elements(n) x), true)
$$;
alter table saloes add column fidelidade_ativa boolean not null default false;
alter table saloes add column fidelidade_niveis jsonb not null default '[{"nome":"Prata","pontos":500,"bonus":1},{"nome":"Ouro","pontos":1500,"bonus":3},{"nome":"Diamante","pontos":3000,"bonus":5}]' check (niveis_ok(fidelidade_niveis));
grant update (fidelidade_ativa, fidelidade_niveis) on saloes to authenticated;

-- 1 ponto por real pago nos últimos 12 meses (pacote usado e cashback não contam: já foram pagos antes).
create function pontos_fidelidade(p_salao uuid, p_cliente uuid) returns int
language sql stable security definer set search_path = public, pg_temp as
$$
  select (coalesce(sum(p.valor_centavos), 0) / 100)::int
  from comanda_pagamentos p join comandas c on c.id = p.comanda_id
  where c.salao_id = p_salao and c.cliente_id = p_cliente and c.status = 'fechada' and c.fechada_em > now() - interval '365 days'
    and p.forma::text not in ('pacote', 'cashback')
$$;
revoke all on function pontos_fidelidade(uuid, uuid) from public, anon, authenticated;

create function fidelidade_interna(p_salao uuid, p_cliente uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_pts int;
  n jsonb; v_nivel jsonb; v_prox jsonb;
begin
  select * into s from saloes where id = p_salao;
  if s.id is null or not s.fidelidade_ativa then return null; end if;
  v_pts := pontos_fidelidade(p_salao, p_cliente);
  for n in select x from jsonb_array_elements(s.fidelidade_niveis) x order by (x ->> 'pontos')::numeric loop
    if v_pts >= (n ->> 'pontos')::numeric then v_nivel := n; elsif v_prox is null then v_prox := n; end if;
  end loop;
  return jsonb_build_object('pontos', v_pts, 'nivel', v_nivel ->> 'nome', 'bonus', coalesce((v_nivel ->> 'bonus')::numeric, 0),
    'proximo', v_prox ->> 'nome', 'faltam', case when v_prox is null then null else (v_prox ->> 'pontos')::numeric - v_pts end);
end
$$;
revoke all on function fidelidade_interna(uuid, uuid) from public, anon, authenticated;
grant execute on function fidelidade_interna(uuid, uuid) to service_role;

create function fidelidade(p_cliente uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$ select fidelidade_interna(c.salao_id, c.id) from clientes c where c.id = p_cliente and c.salao_id = meu_salao() $$;
revoke all on function fidelidade(uuid) from public, anon;
grant execute on function fidelidade(uuid) to authenticated;

-- Bônus do nível: cashback extra sobre o que foi pago na comanda (some se a comanda for reaberta, junto com o cashback).
create function bonus_fidelidade() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  f jsonb;
  v_base int; v_bonus int;
begin
  if not (new.status = 'fechada' and old.status = 'aberta' and new.cliente_id is not null) then return null; end if;
  select * into s from saloes where id = new.salao_id;
  if not s.fidelidade_ativa then return null; end if;
  f := fidelidade_interna(new.salao_id, new.cliente_id);
  if coalesce((f ->> 'bonus')::numeric, 0) <= 0 then return null; end if;
  select coalesce(sum(valor_centavos), 0) into v_base from comanda_pagamentos where comanda_id = new.id and forma::text not in ('pacote', 'cashback');
  v_base := v_base - coalesce((select sum(preco_centavos) from comanda_itens where comanda_id = new.id and tipo = 'gorjeta'), 0);
  v_bonus := floor(greatest(v_base, 0) * (f ->> 'bonus')::numeric / 100);
  if v_bonus > 0 then
    insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, expira_em)
    values (new.salao_id, new.cliente_id, 'credito', v_bonus, new.id, now() + make_interval(days => s.cashback_validade_dias));
  end if;
  return null;
end
$$;
revoke execute on function bonus_fidelidade() from public, anon, authenticated;
create trigger zz_bonus_fidelidade after update of status on comandas for each row execute function bonus_fidelidade();

-- ───────────── pedido de compra ao fornecedor ─────────────
create table fornecedores (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 120),
  telefone text check (telefone ~ '^[0-9]{10,13}$'),
  email text check (length(email) <= 200),
  observacao text check (length(observacao) <= 300),
  criado_em timestamptz not null default now(),
  unique (id, salao_id)
);
alter table fornecedores enable row level security;
create policy forn_ler on fornecedores for select to authenticated using (salao_id = (select meu_salao()));
create policy forn_escrever on fornecedores for all to authenticated using (salao_id = (select meu_salao()) and (select pode('estoque'))) with check (salao_id = (select meu_salao()) and (select pode('estoque')));
revoke all on fornecedores from anon, authenticated;
grant select, delete on fornecedores to authenticated;
grant insert (nome, telefone, email, observacao) on fornecedores to authenticated;
grant update (nome, telefone, email, observacao) on fornecedores to authenticated;

alter table produtos add column fornecedor_id uuid;
alter table produtos add constraint produto_fornecedor foreign key (fornecedor_id, salao_id) references fornecedores (id, salao_id) on delete set null (fornecedor_id);
alter table produtos add column estoque_ideal numeric(12,2) check (estoque_ideal >= 0);
grant update (fornecedor_id, estoque_ideal) on produtos to authenticated;

create table pedidos_compra (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  fornecedor_id uuid,
  status text not null default 'aberto' check (status in ('aberto', 'recebido', 'cancelado')),
  observacao text check (length(observacao) <= 300),
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  recebido_em timestamptz,
  unique (id, salao_id),
  foreign key (fornecedor_id, salao_id) references fornecedores (id, salao_id) on delete set null (fornecedor_id)
);
create table pedido_compra_itens (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  pedido_id uuid not null,
  produto_id uuid not null,
  embalagens numeric(10,2) not null check (embalagens > 0 and embalagens <= 10000),
  custo_centavos int check (custo_centavos between 0 and 10000000),   -- por embalagem
  unique (pedido_id, produto_id),
  foreign key (pedido_id, salao_id) references pedidos_compra (id, salao_id) on delete cascade,
  foreign key (produto_id, salao_id) references produtos (id, salao_id) on delete cascade
);
alter table pedidos_compra enable row level security;
alter table pedido_compra_itens enable row level security;
create policy ped_tudo on pedidos_compra for all to authenticated using (salao_id = (select meu_salao()) and (select pode('estoque'))) with check (salao_id = (select meu_salao()) and (select pode('estoque')));
create policy pedi_tudo on pedido_compra_itens for all to authenticated using (salao_id = (select meu_salao()) and (select pode('estoque'))) with check (salao_id = (select meu_salao()) and (select pode('estoque')));
revoke all on pedidos_compra, pedido_compra_itens from anon, authenticated;
grant select, delete on pedidos_compra, pedido_compra_itens to authenticated;
grant insert (fornecedor_id, observacao) on pedidos_compra to authenticated;
grant update (status) on pedidos_compra to authenticated;
grant insert (pedido_id, produto_id, embalagens, custo_centavos) on pedido_compra_itens to authenticated;

-- Chegou a mercadoria: entrada no estoque de cada item, de uma vez.
create function receber_pedido(p_pedido uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  p pedidos_compra;
  v_n int;
begin
  if not pode('estoque') then raise exception 'sem permissão' using errcode = '42501'; end if;
  select * into p from pedidos_compra where id = p_pedido and salao_id = meu_salao() for update;
  if p.id is null then raise exception 'pedido não encontrado' using errcode = 'P0002'; end if;
  if p.status <> 'aberto' then raise exception 'pedido_ja_recebido' using errcode = '55000'; end if;
  insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, custo_centavos, motivo, feito_por)
  select i.salao_id, i.produto_id, 'entrada', case when pr.unidade = 'un' then i.embalagens else i.embalagens * pr.conteudo end,
         case when i.custo_centavos is null then null else round(i.custo_centavos * i.embalagens)::int end, 'Pedido de compra', auth.uid()
  from pedido_compra_itens i join produtos pr on pr.id = i.produto_id where i.pedido_id = p.id;
  get diagnostics v_n = row_count;
  update pedidos_compra set status = 'recebido', recebido_em = now() where id = p.id;
  return v_n;
end
$$;
revoke all on function receber_pedido(uuid) from public, anon;
grant execute on function receber_pedido(uuid) to authenticated;

-- ───────────── indique uma amiga e origem do link ─────────────
alter table saloes add column indicacao_credito_centavos int not null default 0 check (indicacao_credito_centavos between 0 and 100000);
grant update (indicacao_credito_centavos) on saloes to authenticated;
alter table clientes add column codigo_indicacao text check (codigo_indicacao ~ '^[A-Z2-9]{6}$');
create unique index clientes_codigo_indicacao on clientes (salao_id, codigo_indicacao) where codigo_indicacao is not null;

create function codigo_indicacao_interno(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c clientes;
  v text;
  abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  select * into c from clientes where id = p_cliente for update;
  if c.id is null then return null; end if;
  if c.codigo_indicacao is not null then return c.codigo_indicacao; end if;
  loop
    v := (select string_agg(substr(abc, 1 + floor(random() * length(abc))::int, 1), '') from generate_series(1, 6));
    exit when not exists (select 1 from clientes where salao_id = c.salao_id and codigo_indicacao = v);
  end loop;
  update clientes set codigo_indicacao = v where id = c.id;
  return v;
end
$$;
revoke all on function codigo_indicacao_interno(uuid) from public, anon, authenticated;
grant execute on function codigo_indicacao_interno(uuid) to service_role;
create function codigo_indicacao(p_cliente uuid) returns text
language sql security definer set search_path = public, pg_temp as
$$ select codigo_indicacao_interno(id) from clientes where id = p_cliente and salao_id = meu_salao() $$;
revoke all on function codigo_indicacao(uuid) from public, anon;
grant execute on function codigo_indicacao(uuid) to authenticated;

create table indicacoes_premiadas (
  indicada_id uuid primary key,
  salao_id uuid not null references saloes (id) on delete cascade,
  indicadora_id uuid not null,
  comanda_id uuid not null,
  valor_centavos int not null,
  criado_em timestamptz not null default now(),
  foreign key (indicada_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (indicadora_id, salao_id) references clientes (id, salao_id) on delete cascade
);
alter table indicacoes_premiadas enable row level security;
create policy indp_ler on indicacoes_premiadas for select to authenticated using (salao_id = (select meu_salao()));
revoke all on indicacoes_premiadas from anon, authenticated;
grant select on indicacoes_premiadas to authenticated;

-- Cliente nova que marcou pelo link de uma amiga (ou veio do Google, Instagram, QR...): guarda quem indicou e de onde veio.
create function vincular_origem(p_agendamento uuid, p_codigo text, p_origem text) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c clientes;
  v_ind uuid;
begin
  select cl.* into c from agendamentos a join clientes cl on cl.id = a.cliente_id where a.id = p_agendamento;
  if c.id is null or c.criado_em < now() - interval '1 hour' then return; end if;   -- só cadastro que acabou de nascer
  if p_codigo ~ '^[A-Z2-9]{6}$' then
    select id into v_ind from clientes where salao_id = c.salao_id and codigo_indicacao = p_codigo and id <> c.id;
  end if;
  update clientes set indicado_por = coalesce(indicado_por, v_ind),
    origem = coalesce(origem, case when v_ind is not null then 'indicacao'
                                   when p_origem in ('instagram', 'google', 'facebook', 'tiktok', 'whatsapp') then p_origem end)
  where id = c.id;
end
$$;
revoke all on function vincular_origem(uuid, text, text) from public, anon, authenticated;
grant execute on function vincular_origem(uuid, text, text) to service_role;

-- Na primeira comanda fechada da indicada, quem indicou ganha o crédito (vira cashback). Reabrir desfaz.
create function premiar_indicacao() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_ind uuid;
begin
  if old.status = 'fechada' and new.status <> 'fechada' then
    delete from indicacoes_premiadas where comanda_id = new.id;
    return null;
  end if;
  if not (new.status = 'fechada' and old.status = 'aberta' and new.cliente_id is not null) then return null; end if;
  select * into s from saloes where id = new.salao_id;
  if s.indicacao_credito_centavos <= 0 then return null; end if;
  select indicado_por into v_ind from clientes where id = new.cliente_id;
  if v_ind is null
     or exists (select 1 from comandas where cliente_id = new.cliente_id and status = 'fechada' and id <> new.id)
     or exists (select 1 from indicacoes_premiadas where indicada_id = new.cliente_id) then return null; end if;
  insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, expira_em)
  values (new.salao_id, v_ind, 'credito', s.indicacao_credito_centavos, new.id, now() + make_interval(days => s.cashback_validade_dias));
  insert into indicacoes_premiadas (indicada_id, salao_id, indicadora_id, comanda_id, valor_centavos)
  values (new.cliente_id, new.salao_id, v_ind, new.id, s.indicacao_credito_centavos);
  return null;
end
$$;
revoke execute on function premiar_indicacao() from public, anon, authenticated;
create trigger zz_premiar_indicacao after update of status on comandas for each row execute function premiar_indicacao();

-- ───────────── metas da equipe ─────────────
create table metas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  membro_id uuid,                                  -- vazio = meta do salão
  mes date not null check (extract(day from mes) = 1),
  tipo text not null check (tipo in ('faturamento', 'produtos', 'atendimentos')),
  valor int not null check (valor between 1 and 1000000000),
  criado_em timestamptz not null default now(),
  foreign key (membro_id, salao_id) references membros (user_id, salao_id) on delete cascade
);
create unique index metas_unica on metas (salao_id, coalesce(membro_id, '00000000-0000-0000-0000-000000000000'::uuid), mes, tipo);
alter table metas enable row level security;
create policy metas_ler on metas for select to authenticated using (salao_id = (select meu_salao()) and ((select meu_papel()) = 'admin' or membro_id is null or membro_id = (select auth.uid())));
create policy metas_escrever on metas for all to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin') with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on metas from anon, authenticated;
grant select, delete on metas to authenticated;
grant insert (membro_id, mes, tipo, valor) on metas to authenticated;
grant update (valor) on metas to authenticated;

-- Quanto já foi feito de cada meta do mês (faturamento e produtos em centavos; atendimentos em quantidade).
create function progresso_metas(p_mes date) returns table (id uuid, membro_id uuid, tipo text, valor int, realizado bigint)
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
begin
  select * into s from saloes where saloes.id = v_salao;
  de := (date_trunc('month', p_mes)::timestamp) at time zone s.fuso;
  ate := ((date_trunc('month', p_mes) + interval '1 month')::timestamp) at time zone s.fuso;
  return query
  with itens as (
    select i.tipo::text as t, i.profissional_id as prof, (i.preco_centavos * i.quantidade - i.desconto_centavos)::bigint as v
    from comanda_itens i join comandas c on c.id = i.comanda_id
    where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo::text in ('servico', 'produto')
  )
  select m.id, m.membro_id, m.tipo, m.valor,
    (case m.tipo
      when 'faturamento' then (select coalesce(sum(v), 0) from itens where m.membro_id is null or prof = m.membro_id)
      when 'produtos' then (select coalesce(sum(v), 0) from itens where t = 'produto' and (m.membro_id is null or prof = m.membro_id))
      else (select count(*) from itens where t = 'servico' and (m.membro_id is null or prof = m.membro_id))
    end)::bigint
  from metas m
  where m.salao_id = v_salao and m.mes = date_trunc('month', p_mes)::date
    and (meu_papel() = 'admin' or m.membro_id is null or m.membro_id = auth.uid());
end
$$;
revoke all on function progresso_metas(date) from public, anon;
grant execute on function progresso_metas(date) to authenticated;

-- ───────────── cobrança pelo celular: comanda, vale-presente e pacote pelo link ─────────────
alter table saloes add column venda_online boolean not null default false;
grant update (venda_online) on saloes to authenticated;
alter table pacotes add column online boolean not null default false;
grant update (online) on pacotes to authenticated;

create table cobrancas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  tipo text not null check (tipo in ('comanda', 'vale', 'pacote')),
  comanda_id uuid,
  pacote_id uuid,
  cliente_id uuid,
  valor_centavos int not null check (valor_centavos between 100 and 10000000),
  nome text check (length(nome) <= 120),
  presente_para text check (length(presente_para) <= 80),
  presente_mensagem text check (length(presente_mensagem) <= 200),
  token_hash text not null unique,
  status text not null default 'pendente' check (status in ('pendente', 'paga', 'cancelada')),
  modo text not null default 'pix_manual' check (modo in ('pix_manual', 'mercadopago')),
  mp_payment_id text,
  copia_cola text check (length(copia_cola) <= 600),
  expira_em timestamptz not null default now() + interval '2 days',
  paga_em timestamptz,
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade,
  foreign key (pacote_id, salao_id) references pacotes (id, salao_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete set null (cliente_id),
  check (tipo <> 'comanda' or comanda_id is not null),
  check (tipo <> 'pacote' or pacote_id is not null),
  check (tipo <> 'vale' or presente_para is not null)
);
create unique index cobrancas_mp on cobrancas (mp_payment_id) where mp_payment_id is not null;
create index on cobrancas (salao_id, status, criado_em desc);
create index on cobrancas (comanda_id);
alter table cobrancas enable row level security;
create policy cob_ler on cobrancas for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao'));
revoke all on cobrancas from anon, authenticated;
grant select (id, salao_id, tipo, comanda_id, pacote_id, cliente_id, valor_centavos, nome, presente_para, presente_mensagem, status, modo, copia_cola, expira_em, paga_em, criado_em) on cobrancas to authenticated;

create function novo_token() returns text
language sql volatile set search_path = public, pg_temp as
$$ select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') $$;
revoke all on function novo_token() from public, anon, authenticated;
create function hash_token(p text) returns text
language sql immutable set search_path = public, pg_temp as
$$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;

-- Quanto falta pagar na comanda (itens - desconto - pagamentos).
create function restante_comanda(p_comanda uuid) returns int
language sql stable security definer set search_path = public, pg_temp as
$$
  select (coalesce((select sum(preco_centavos * quantidade - desconto_centavos) from comanda_itens where comanda_id = c.id), 0)
          - c.desconto_centavos
          - coalesce((select sum(valor_centavos) from comanda_pagamentos where comanda_id = c.id), 0))::int
  from comandas c where c.id = p_comanda
$$;
revoke all on function restante_comanda(uuid) from public, anon, authenticated;

-- A recepção gera o link para a cliente pagar o que falta da comanda pelo celular.
create function criar_cobranca_comanda(p_comanda uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  v_valor int;
  v_token text := novo_token();
  v_id uuid;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  if c.status <> 'aberta' then raise exception 'comanda_fechada' using errcode = '55000'; end if;
  v_valor := restante_comanda(c.id);
  if v_valor < 100 then raise exception 'nada_a_cobrar' using errcode = '22023'; end if;
  update cobrancas set status = 'cancelada' where comanda_id = c.id and status = 'pendente';
  insert into cobrancas (salao_id, tipo, comanda_id, cliente_id, valor_centavos, token_hash)
  values (c.salao_id, 'comanda', c.id, c.cliente_id, v_valor, hash_token(v_token)) returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'valor_centavos', v_valor);
end
$$;
revoke all on function criar_cobranca_comanda(uuid) from public, anon;
grant execute on function criar_cobranca_comanda(uuid) to authenticated;

-- Vale-presente ou pacote comprado pelo link: a cliente é achada (ou cadastrada) pelo celular.
create function criar_pedido_online(p_slug text, p_tipo text, p_pacote uuid, p_valor int, p_nome text, p_telefone text, p_para text, p_mensagem text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  pk pacotes;
  v_tel text := tel_nacional(p_telefone);
  v_nome text := left(regexp_replace(trim(coalesce(p_nome, '')), '\s+', ' ', 'g'), 120);
  v_cli uuid;
  v_valor int;
  v_token text := novo_token();
  v_id uuid;
begin
  select * into s from saloes where slug = p_slug;
  if s.id is null or not s.venda_online then raise exception 'venda_indisponivel' using errcode = '55000'; end if;
  if length(v_nome) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if p_tipo = 'pacote' then
    select * into pk from pacotes where id = p_pacote and salao_id = s.id and ativo and online;
    if pk.id is null then raise exception 'pacote_indisponivel' using errcode = 'P0002'; end if;
    v_valor := pk.preco_centavos;
  elsif p_tipo = 'vale' then
    if p_valor is null or p_valor not between 2000 and 200000 then raise exception 'valor_invalido' using errcode = '22023'; end if;
    if length(trim(coalesce(p_para, ''))) < 2 then raise exception 'presente_sem_nome' using errcode = '22023'; end if;
    v_valor := p_valor;
  else
    raise exception 'tipo inválido' using errcode = '22023';
  end if;
  select id into v_cli from clientes where salao_id = s.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli is null then
    insert into clientes (salao_id, nome, telefone) values (s.id, v_nome, v_tel) returning id into v_cli;
  end if;
  insert into cobrancas (salao_id, tipo, pacote_id, cliente_id, valor_centavos, nome, presente_para, presente_mensagem, token_hash)
  values (s.id, p_tipo, case when p_tipo = 'pacote' then pk.id end, v_cli, v_valor, v_nome,
          case when p_tipo = 'vale' then left(trim(p_para), 80) end, case when p_tipo = 'vale' then left(nullif(trim(p_mensagem), ''), 200) end,
          hash_token(v_token))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'valor_centavos', v_valor);
end
$$;

create function registrar_pix_cobranca(p_id uuid, p_copia_cola text, p_mp_payment_id text, p_modo text) returns void
language sql security definer set search_path = public, pg_temp as
$$ update cobrancas set copia_cola = left(p_copia_cola, 600), mp_payment_id = p_mp_payment_id, modo = p_modo where id = p_id and status = 'pendente' $$;

create function cobranca_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('id', b.id, 'salao', s.nome, 'slug', s.slug, 'tipo', b.tipo, 'valor_centavos', b.valor_centavos,
    'status', case when b.status = 'pendente' and b.expira_em < now() then 'expirada' else b.status end,
    'copia_cola', b.copia_cola, 'modo', b.modo, 'presente_para', b.presente_para, 'nome', coalesce(b.nome, cl.nome),
    'pacote', (select nome from pacotes where id = b.pacote_id),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('descricao', i.descricao, 'valor', i.preco_centavos * i.quantidade - i.desconto_centavos) order by i.criado_em), '[]')
              from comanda_itens i where b.tipo = 'comanda' and i.comanda_id = b.comanda_id))
  from cobrancas b join saloes s on s.id = b.salao_id left join clientes cl on cl.id = b.cliente_id
  where b.token_hash = hash_token(p_token)
$$;

-- Pagamento confirmado: na comanda entra o Pix; vale e pacote viram uma comanda aberta com o item e o Pix,
-- que a recepção fecha no caixa do dia (é ao fechar que o vale e o pacote passam a valer).
create function quitar_cobranca(p_id uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  b cobrancas;
  v_cmd uuid;
begin
  select * into b from cobrancas where id = p_id for update;
  if b.id is null then return 'nao_encontrada'; end if;
  if b.status = 'paga' then return 'ja_paga'; end if;
  if b.status = 'cancelada' then return 'cancelada'; end if;
  if b.tipo = 'comanda' then
    if not exists (select 1 from comandas where id = b.comanda_id and status = 'aberta') then return 'comanda_fechada'; end if;
    insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (b.salao_id, b.comanda_id, 'pix', b.valor_centavos);
  else
    insert into comandas (salao_id, cliente_id, observacao) values (b.salao_id, b.cliente_id, 'Venda pelo link') returning id into v_cmd;
    if b.tipo = 'vale' then
      insert into comanda_itens (salao_id, comanda_id, tipo, descricao, preco_centavos, presente_para, presente_mensagem)
      values (b.salao_id, v_cmd, 'vale_presente', left('Vale-presente para ' || b.presente_para, 160), b.valor_centavos, b.presente_para, b.presente_mensagem);
    else
      insert into comanda_itens (salao_id, comanda_id, tipo, pacote_id, descricao, preco_centavos)
      values (b.salao_id, v_cmd, 'pacote', b.pacote_id, (select left(nome, 160) from pacotes where id = b.pacote_id), b.valor_centavos);
    end if;
    insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (b.salao_id, v_cmd, 'pix', b.valor_centavos);
    update cobrancas set comanda_id = v_cmd where id = b.id;
  end if;
  update cobrancas set status = 'paga', paga_em = now() where id = b.id;
  return 'paga';
end
$$;
revoke all on function quitar_cobranca(uuid) from public, anon, authenticated;

-- A recepção confere o Pix no banco e confirma.
create function confirmar_cobranca(p_id uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  if not exists (select 1 from cobrancas where id = p_id and salao_id = meu_salao()) then raise exception 'cobrança não encontrada' using errcode = 'P0002'; end if;
  return quitar_cobranca(p_id);
end
$$;
revoke all on function confirmar_cobranca(uuid) from public, anon;
grant execute on function confirmar_cobranca(uuid) to authenticated;

create function cancelar_cobranca(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  update cobrancas set status = 'cancelada' where id = p_id and salao_id = meu_salao() and status = 'pendente';
end
$$;
revoke all on function cancelar_cobranca(uuid) from public, anon;
grant execute on function cancelar_cobranca(uuid) to authenticated;

-- Aviso do Mercado Pago (o servidor já consultou o pagamento na API): confere o valor e quita.
create function cobranca_paga_mp(p_payment_id text, p_valor_centavos int, p_salao uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_id uuid;
begin
  select id into v_id from cobrancas where mp_payment_id = p_payment_id and salao_id = p_salao and valor_centavos <= p_valor_centavos;
  if v_id is null then return 'nao_encontrada'; end if;
  return quitar_cobranca(v_id);
end
$$;
revoke all on function criar_pedido_online(text, text, uuid, int, text, text, text, text), registrar_pix_cobranca(uuid, text, text, text),
  cobranca_publica(text), cobranca_paga_mp(text, int, uuid) from public, anon, authenticated;
grant execute on function criar_pedido_online(text, text, uuid, int, text, text, text, text), registrar_pix_cobranca(uuid, text, text, text),
  cobranca_publica(text), cobranca_paga_mp(text, int, uuid) to service_role;

-- ───────────── taxa por falta ─────────────
alter table saloes add column taxa_falta_centavos int not null default 0 check (taxa_falta_centavos between 0 and 50000);
grant update (taxa_falta_centavos) on saloes to authenticated;

create table taxas_falta (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  agendamento_id uuid not null unique references agendamentos (id) on delete cascade,
  valor_centavos int not null check (valor_centavos > 0),
  falta_em timestamptz not null,
  perdoada_em timestamptz,
  perdoada_por uuid,
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on taxas_falta (cliente_id);
alter table taxas_falta enable row level security;
create policy taxa_ler on taxas_falta for select to authenticated using (salao_id = (select meu_salao()));
revoke all on taxas_falta from anon, authenticated;
grant select on taxas_falta to authenticated;

alter table comanda_itens add column taxa_falta_id uuid references taxas_falta (id) on delete set null;
alter table comanda_itens add constraint item_taxa_ok check (tipo::text <> 'taxa' or (taxa_falta_id is not null and quantidade = 1 and profissional_id is null));
grant insert (taxa_falta_id) on comanda_itens to authenticated;

-- Faltou sem avisar: nasce a taxa (VIP e quem pagou sinal não pagam; uma por visita). Desmarcar a falta apaga a que não foi cobrada.
create function gerar_taxa_falta() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_valor int;
begin
  if new.status = 'faltou' and old.status <> 'faltou' then
    select taxa_falta_centavos into v_valor from saloes where id = new.salao_id;
    if v_valor > 0
       and not exists (select 1 from clientes where id = new.cliente_id and vip)
       and not exists (select 1 from sinais where agendamento_id = new.id and status in ('pago', 'credito'))
       and not (new.grupo_id is not null and exists (select 1 from taxas_falta t join agendamentos a on a.id = t.agendamento_id where a.grupo_id = new.grupo_id)) then
      insert into taxas_falta (salao_id, cliente_id, agendamento_id, valor_centavos, falta_em) values (new.salao_id, new.cliente_id, new.id, v_valor, new.inicio)
      on conflict (agendamento_id) do nothing;
    end if;
  elsif old.status = 'faltou' and new.status <> 'faltou' then
    delete from taxas_falta t where t.agendamento_id = new.id and not exists (select 1 from comanda_itens i where i.taxa_falta_id = t.id);
  end if;
  return null;
end
$$;
revoke execute on function gerar_taxa_falta() from public, anon, authenticated;
create trigger gerar_taxa_falta after update of status on agendamentos for each row execute function gerar_taxa_falta();

-- Taxa só entra na comanda da própria cliente, uma vez (comanda cancelada libera para cobrar de novo).
create function checar_item_taxa() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  t taxas_falta;
begin
  if new.taxa_falta_id is null then return new; end if;
  select * into t from taxas_falta where id = new.taxa_falta_id;
  if t.id is null or t.salao_id <> new.salao_id or t.perdoada_em is not null
     or t.cliente_id is distinct from (select cliente_id from comandas where id = new.comanda_id)
     or exists (select 1 from comanda_itens i join comandas c on c.id = i.comanda_id
                where i.taxa_falta_id = t.id and i.id <> new.id and c.status <> 'cancelada') then
    raise exception 'taxa_invalida' using errcode = '22023';
  end if;
  new.preco_centavos := t.valor_centavos;
  return new;
end
$$;
revoke execute on function checar_item_taxa() from public, anon, authenticated;
create trigger checar_item_taxa before insert or update of taxa_falta_id on comanda_itens for each row execute function checar_item_taxa();

create function taxas_pendentes(p_cliente uuid) returns setof taxas_falta
language sql stable security definer set search_path = public, pg_temp as
$$
  select t.* from taxas_falta t
  where t.cliente_id = p_cliente and t.salao_id = meu_salao() and t.perdoada_em is null
    and not exists (select 1 from comanda_itens i join comandas c on c.id = i.comanda_id where i.taxa_falta_id = t.id and c.status <> 'cancelada')
  order by t.falta_em
$$;
revoke all on function taxas_pendentes(uuid) from public, anon;
grant execute on function taxas_pendentes(uuid) to authenticated;

create function perdoar_taxa(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  update taxas_falta set perdoada_em = now(), perdoada_por = auth.uid() where id = p_id and salao_id = meu_salao() and perdoada_em is null;
end
$$;
revoke all on function perdoar_taxa(uuid) from public, anon;
grant execute on function perdoar_taxa(uuid) to authenticated;

-- ───────────── área da cliente ─────────────
create table links_cliente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  token_hash text not null unique,
  expira_em timestamptz not null default now() + interval '180 days',
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on links_cliente (cliente_id);
alter table links_cliente enable row level security;
revoke all on links_cliente from anon, authenticated;

create function link_cliente_interno(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_token text := novo_token();
begin
  insert into links_cliente (salao_id, cliente_id, token_hash) select salao_id, id, hash_token(v_token) from clientes where id = p_cliente;
  if not found then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  return v_token;
end
$$;
revoke all on function link_cliente_interno(uuid) from public, anon, authenticated;
create function criar_link_cliente(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if not exists (select 1 from clientes where id = p_cliente and salao_id = meu_salao()) then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  return link_cliente_interno(p_cliente);
end
$$;
revoke all on function criar_link_cliente(uuid) from public, anon;
grant execute on function criar_link_cliente(uuid) to authenticated;
-- Logo depois de marcar pelo link, a cliente já recebe a área dela.
create function link_cliente_online(p_agendamento uuid) returns text
language sql security definer set search_path = public, pg_temp as
$$ select link_cliente_interno(cliente_id) from agendamentos where id = p_agendamento $$;

create function area_cliente(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  l links_cliente;
  c clientes;
  s saloes;
  v_cash int;
begin
  select * into l from links_cliente where token_hash = hash_token(p_token);
  if l.id is null or l.expira_em < now() then return null; end if;
  select * into c from clientes where id = l.cliente_id;
  select * into s from saloes where id = l.salao_id;
  -- mesma regra de saldo_cashback: créditos válidos menos o usado desde o crédito válido mais antigo
  select greatest(0, v + coalesce((select sum(valor_centavos) from cashback_movimentos where cliente_id = c.id and tipo = 'uso' and criado_em >= desde), 0))::int
  into v_cash
  from (select coalesce(sum(valor_centavos), 0) v, min(criado_em) desde from cashback_movimentos where cliente_id = c.id and tipo = 'credito' and expira_em > now()) x;
  return jsonb_build_object(
    'nome', c.nome, 'salao', s.nome, 'slug', s.slug, 'fuso', s.fuso, 'cashback', v_cash,
    'indicacao_credito', s.indicacao_credito_centavos, 'codigo', case when s.indicacao_credito_centavos > 0 then c.codigo_indicacao end,
    'fidelidade', fidelidade_interna(s.id, c.id),
    'proximos', (select coalesce(jsonb_agg(jsonb_build_object('token', a.token, 'inicio', a.inicio, 'servico', sv.nome, 'profissional', m.nome, 'status', a.status) order by a.inicio), '[]')
                 from agendamentos a join servicos sv on sv.id = a.servico_id join membros m on m.user_id = a.profissional_id
                 where a.cliente_id = c.id and a.inicio > now() and a.status in ('agendado', 'confirmado')),
    'historico', (select coalesce(jsonb_agg(h order by h ->> 'inicio' desc), '[]') from (
                   select jsonb_build_object('inicio', a.inicio, 'servico', sv.nome, 'profissional', m.nome) h
                   from agendamentos a join servicos sv on sv.id = a.servico_id join membros m on m.user_id = a.profissional_id
                   where a.cliente_id = c.id and a.status = 'concluido' order by a.inicio desc limit 10) x),
    'pacotes', (select coalesce(jsonb_agg(jsonb_build_object('nome', pc.nome, 'expira_em', pc.expira_em,
                  'saldos', (select jsonb_agg(jsonb_build_object('servico', sv.nome, 'resta', ps.total - ps.usado)) from pacote_saldos ps join servicos sv on sv.id = ps.servico_id where ps.pacote_cliente_id = pc.id))), '[]')
                from pacotes_cliente pc where pc.cliente_id = c.id and pc.estado = 'ativo' and pc.expira_em > now()),
    'taxas', (select coalesce(sum(t.valor_centavos), 0) from taxas_falta t where t.cliente_id = c.id and t.perdoada_em is null
              and not exists (select 1 from comanda_itens i join comandas cm on cm.id = i.comanda_id where i.taxa_falta_id = t.id and cm.status <> 'cancelada')));
end
$$;
-- O código de indicação nasce quando a área é aberta pela primeira vez (com indicação ligada).
create function area_cliente_preparar(p_token text) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  l links_cliente;
begin
  select * into l from links_cliente where token_hash = hash_token(p_token) and expira_em > now();
  if l.id is not null and exists (select 1 from saloes where id = l.salao_id and indicacao_credito_centavos > 0) then
    perform codigo_indicacao_interno(l.cliente_id);
  end if;
end
$$;
revoke all on function link_cliente_online(uuid), area_cliente(text), area_cliente_preparar(text) from public, anon, authenticated;
grant execute on function link_cliente_online(uuid), area_cliente(text), area_cliente_preparar(text) to service_role;

-- ───────────── fichas de estética ─────────────
alter table saloes add column ficha_areas text[] not null default '{cabelo}'
  check (cardinality(ficha_areas) between 1 and 5 and ficha_areas <@ array['cabelo', 'unhas', 'cilios_sobrancelha', 'pele', 'depilacao']);
grant update (ficha_areas) on saloes to authenticated;
create or replace function ficha_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'slug', s.slug, 'cliente', split_part(c.nome, ' ', 1), 'respondida', f.respondida_em is not null,
    'expirada', f.expira_em < now() and f.respondida_em is null, 'pedir_nascimento', c.nascimento is null, 'areas', s.ficha_areas)
  from fichas_previas f join clientes c on c.id = f.cliente_id join saloes s on s.id = f.salao_id
  where f.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;
-- Com as perguntas de estética a resposta fica maior.
do $$
declare d text;
begin
  select pg_get_functiondef('responder_ficha(text,jsonb)'::regprocedure) into d;
  if position('length(r::text) > 4000' in d) = 0 then raise exception 'responder_ficha() mudou'; end if;
  execute replace(d, 'length(r::text) > 4000', 'length(r::text) > 12000');
end $$;

-- ───────────── IA no WhatsApp ─────────────
alter table saloes add column ia_ativa boolean not null default false;
alter table saloes add column ia_instrucoes text check (length(ia_instrucoes) <= 1500);
grant update (ia_ativa, ia_instrucoes) on saloes to authenticated;

-- ───────────── relatórios com previsão ─────────────
create function relatorios(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
  hoje date; fim_mes timestamptz; ini_mes timestamptz;
begin
  if not pode('painel') then raise exception 'sem permissão para relatórios' using errcode = '42501'; end if;
  select * into s from saloes where id = v_salao;
  de := p_inicio::timestamp at time zone s.fuso;
  ate := (p_fim + 1)::timestamp at time zone s.fuso;
  hoje := (now() at time zone s.fuso)::date;
  ini_mes := date_trunc('month', hoje)::timestamp at time zone s.fuso;
  fim_mes := (date_trunc('month', hoje) + interval '1 month')::timestamp at time zone s.fuso;
  return jsonb_build_object(
    'formas', (select coalesce(jsonb_object_agg(forma, v), '{}') from (
      select p.forma::text forma, sum(p.valor_centavos) v from comanda_pagamentos p join comandas c on c.id = p.comanda_id
      where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate group by 1) x),
    'servicos', (select coalesce(jsonb_agg(x order by (x ->> 'valor')::bigint desc), '[]') from (
      select jsonb_build_object('nome', coalesce(sv.nome, min(i.descricao)), 'qtd', sum(i.quantidade), 'valor', sum(i.preco_centavos * i.quantidade - i.desconto_centavos)) x
      from comanda_itens i join comandas c on c.id = i.comanda_id left join servicos sv on sv.id = i.servico_id
      where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo = 'servico'
      group by i.servico_id, sv.nome) y),
    'produtos', (select coalesce(jsonb_agg(x order by (x ->> 'valor')::bigint desc), '[]') from (
      select jsonb_build_object('nome', coalesce(pr.nome, min(i.descricao)), 'qtd', sum(i.quantidade), 'valor', sum(i.preco_centavos * i.quantidade - i.desconto_centavos),
             'custo', sum(i.quantidade * coalesce(pr.custo_centavos, 0))) x
      from comanda_itens i join comandas c on c.id = i.comanda_id left join produtos pr on pr.id = i.produto_id
      where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo = 'produto'
      group by i.produto_id, pr.nome) y),
    'profissionais', (select coalesce(jsonb_agg(x), '[]') from (
      select jsonb_build_object('nome', m.nome,
        'atendimentos', (select count(*) from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo = 'servico' and i.profissional_id = m.user_id),
        'faturamento', (select coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos), 0) from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo in ('servico', 'produto') and i.profissional_id = m.user_id),
        'clientes', (select count(distinct c.cliente_id) from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.profissional_id = m.user_id),
        'faltas', (select count(*) from agendamentos a where a.salao_id = v_salao and a.profissional_id = m.user_id and a.status = 'faltou' and a.inicio >= de and a.inicio < ate),
        'cancelados', (select count(*) from agendamentos a where a.salao_id = v_salao and a.profissional_id = m.user_id and a.status = 'cancelado' and a.inicio >= de and a.inicio < ate)) x
      from membros m where m.salao_id = v_salao and m.ativo and m.papel in ('admin', 'profissional') order by m.nome) y),
    'por_hora', (select coalesce(jsonb_object_agg(h, n), '{}') from (
      select extract(hour from a.inicio at time zone s.fuso)::int h, count(*) n from agendamentos a
      where a.salao_id = v_salao and a.status in ('concluido', 'em_atendimento', 'confirmado', 'agendado') and a.inicio >= de and a.inicio < ate group by 1) x),
    'clientes', (select jsonb_build_object(
        'novas', count(*) filter (where primeira >= de),
        'voltaram', count(*) filter (where primeira < de))
      from (select c.cliente_id, (select min(c2.fechada_em) from comandas c2 where c2.cliente_id = c.cliente_id and c2.status = 'fechada') primeira
            from comandas c where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and c.cliente_id is not null group by c.cliente_id) x),
    'previsao', jsonb_build_object(
      'realizado_mes', (select coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos), 0) - coalesce((select sum(desconto_centavos) from comandas where salao_id = v_salao and status = 'fechada' and fechada_em >= ini_mes and fechada_em < fim_mes), 0)
                        from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= ini_mes and c.fechada_em < fim_mes and i.tipo <> 'gorjeta'),
      'agendado_mes', (select coalesce(sum(preco_de(a.servico_id, a.profissional_id, a.variacao_id) * (100 - a.promocao_percentual) / 100), 0) from agendamentos a
                       where a.salao_id = v_salao and a.status in ('agendado', 'confirmado') and a.inicio >= now() and a.inicio < fim_mes),
      'semanas', (select coalesce(jsonb_agg(jsonb_build_object('semana', w, 'valor', v, 'horarios', n) order by w), '[]') from (
        select date_trunc('week', a.inicio at time zone s.fuso)::date w, sum(preco_de(a.servico_id, a.profissional_id, a.variacao_id) * (100 - a.promocao_percentual) / 100) v, count(*) n
        from agendamentos a where a.salao_id = v_salao and a.status in ('agendado', 'confirmado') and a.inicio >= now() and a.inicio < now() + interval '35 days' group by 1) x))
  );
end
$$;
revoke all on function relatorios(date, date) from public, anon;
grant execute on function relatorios(date, date) to authenticated;

-- ───────────── unir cadastros: leva também taxas, links, cobranças, indicações e código ─────────────
create or replace function unir_clientes(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  a clientes; b clientes;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção unem cadastros' using errcode = '42501'; end if;
  if p_manter = p_remover then raise exception 'mesmo cadastro' using errcode = '22023'; end if;
  select * into a from clientes where id = p_manter and salao_id = v_salao for update;
  select * into b from clientes where id = p_remover and salao_id = v_salao for update;
  if a.id is null or b.id is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update agendamentos set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', '', true);
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update aceites_politica set cliente_id = a.id where cliente_id = b.id;
  update pacotes_cliente set cliente_id = a.id where cliente_id = b.id;
  update cashback_movimentos set cliente_id = a.id where cliente_id = b.id;
  update lista_espera set cliente_id = a.id where cliente_id = b.id;
  update avisos set cliente_id = a.id where cliente_id = b.id;
  update fichas_previas set cliente_id = a.id where cliente_id = b.id;
  update avaliacoes set cliente_id = a.id where cliente_id = b.id;
  update fila_atendimento set cliente_id = a.id where cliente_id = b.id;
  update termos_assinados set cliente_id = a.id where cliente_id = b.id;
  update taxas_falta set cliente_id = a.id where cliente_id = b.id;
  update links_cliente set cliente_id = a.id where cliente_id = b.id;
  update cobrancas set cliente_id = a.id where cliente_id = b.id;
  update indicacoes_premiadas set indicadora_id = a.id where indicadora_id = b.id;
  delete from indicacoes_premiadas where indicada_id = b.id and exists (select 1 from indicacoes_premiadas where indicada_id = a.id);
  update indicacoes_premiadas set indicada_id = a.id where indicada_id = b.id;
  update vales_presente set comprado_por = a.id where comprado_por = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em),
    vip = a.vip or b.vip, bloqueada = a.bloqueada or b.bloqueada, sempre_sinal = a.sempre_sinal or b.sempre_sinal,
    etiquetas = (select coalesce(array_agg(x), '{}') from (select distinct unnest(a.etiquetas || b.etiquetas) x order by 1 limit 10) e)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;
-- A política que a cliente aceita no link já mostra a taxa por falta; o registro do aceite passa a guardar o mesmo texto.
create function politica_com_taxa() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_taxa int;
begin
  select taxa_falta_centavos into v_taxa from saloes where id = new.salao_id;
  if v_taxa > 0 and position('Falta sem aviso' in new.texto) = 0 then
    new.texto := new.texto || ' Falta sem aviso: taxa de R$ ' || replace(to_char(v_taxa / 100.0, 'FM999990.00'), '.', ',') || ' cobrada na próxima visita.';
  end if;
  return new;
end
$$;
revoke execute on function politica_com_taxa() from public, anon, authenticated;
create trigger politica_com_taxa before insert on aceites_politica for each row execute function politica_com_taxa();
-- Endereço da cliente (opcional): atendimento em casa, nota fiscal e "de onde vêm as clientes".
alter table clientes
  add column cep text check (cep ~ '^[0-9]{8}$'),
  add column logradouro text check (char_length(logradouro) <= 200),
  add column numero text check (char_length(numero) <= 20),
  add column complemento text check (char_length(complemento) <= 100),
  add column bairro text check (char_length(bairro) <= 100),
  add column cidade text check (char_length(cidade) <= 100),
  add column uf text check (uf ~ '^[A-Z]{2}$');

grant insert (cep, logradouro, numero, complemento, bairro, cidade, uf) on clientes to authenticated;
grant update (cep, logradouro, numero, complemento, bairro, cidade, uf) on clientes to authenticated;

-- Unir cadastros: o endereço vem inteiro de um dos dois (nunca rua de um com número do outro).
do $$
declare d text;
begin
  d := pg_get_functiondef('unir_clientes(uuid, uuid)'::regprocedure);
  if position('vip = a.vip or b.vip,' in d) = 0 then raise exception 'unir_clientes mudou'; end if;
  d := replace(d, 'vip = a.vip or b.vip,', 'cep = case when a.logradouro is null and a.cep is null then b.cep else a.cep end,
    logradouro = case when a.logradouro is null and a.cep is null then b.logradouro else a.logradouro end,
    numero = case when a.logradouro is null and a.cep is null then b.numero else a.numero end,
    complemento = case when a.logradouro is null and a.cep is null then b.complemento else a.complemento end,
    bairro = case when a.logradouro is null and a.cep is null then b.bairro else a.bairro end,
    cidade = case when a.logradouro is null and a.cep is null then b.cidade else a.cidade end,
    uf = case when a.logradouro is null and a.cep is null then b.uf else a.uf end,
    vip = a.vip or b.vip,');
  execute d;
end
$$;

-- Relatórios: bairros com mais clientes (entre as que têm endereço).
create function bairros_clientes() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare v_salao uuid := meu_salao();
begin
  if not pode('painel') then raise exception 'sem permissão para relatórios' using errcode = '42501'; end if;
  return jsonb_build_object(
    'com_endereco', (select count(*) from clientes where salao_id = v_salao and bairro is not null),
    'total', (select count(*) from clientes where salao_id = v_salao),
    'bairros', (select coalesce(jsonb_agg(jsonb_build_object('bairro', b, 'cidade', c, 'clientes', n) order by n desc, b), '[]') from (
      select min(trim(bairro)) b, min(cidade) c, count(*) n from clientes
      where salao_id = v_salao and nullif(trim(bairro), '') is not null
      group by lower(trim(bairro)), lower(coalesce(cidade, '')) order by 3 desc, 1 limit 10) x)
  );
end
$$;
revoke all on function bairros_clientes() from public, anon;
grant execute on function bairros_clientes() to authenticated;
-- Primeiro acesso guiado: o salão novo passa por salão, serviços, equipe, clientes e link. Fica marcado quando termina.
alter table saloes add column guia_concluido_em timestamptz;
-- Quem já usa o sistema não precisa do passo a passo.
update saloes set guia_concluido_em = now();
grant update (guia_concluido_em) on saloes to authenticated;
-- Correções da banca de revisão (itens críticos):
-- 1) Receber pagamento e fechar comanda vira a permissão "caixa": admin e recepção por padrão; profissional só se o admin ligar.
-- 2) Desconto não pode passar dos serviços e "comer" a gorjeta (receita negativa pagando gorjeta inteira).
-- 3) Agenda: pela API só dá para mexer em horário, profissional e situação; promoção, cliente e token ficam travados.
--    Profissional sem "agenda_outros" não mexe em nada do horário de outra pessoa (nem marcar falta).

-- ───────── 1) permissão "caixa" ─────────
create or replace function pode(p_chave text) returns boolean
language sql stable security definer set search_path = public, pg_temp as
$$
  select coalesce((
    select case when m.papel = 'admin' then true
      else coalesce(case when m.permissoes ? p_chave then (m.permissoes ->> p_chave) = 'true' end,
        case p_chave
          when 'desconto' then true
          when 'agenda_outros' then true
          when 'comissoes' then m.papel = 'recepcao'
          when 'estoque' then m.papel = 'recepcao'
          when 'caixa' then m.papel = 'recepcao'
          else false
        end) end
    from membros m where m.user_id = auth.uid() and m.ativo), false)
$$;

drop policy if exists pags_escrever on comanda_pagamentos;
create policy pags_escrever on comanda_pagamentos for all to authenticated
  using (salao_id = (select meu_salao()) and (select pode('caixa')))
  with check (salao_id = (select meu_salao()) and (select pode('caixa')));

create or replace function fechar_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v_caixa uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  if c.status <> 'aberta' then raise exception 'comanda_fechada' using errcode = '55000'; end if;
  select id into v_caixa from caixas where salao_id = c.salao_id and fechado_em is null;
  if v_caixa is null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  select * into t from total_comanda(p_comanda);
  if not exists (select 1 from comanda_itens where comanda_id = p_comanda) then raise exception 'comanda_vazia' using errcode = '22023'; end if;
  -- A gorjeta é do profissional: o desconto não pode passar do resto e "pagar" a gorjeta com dinheiro do salão.
  if t.total < 0 or t.receita < 0 then raise exception 'desconto_maior_que_total' using errcode = '22023'; end if;
  if t.pago <> t.total then raise exception 'pagamento_diferente' using errcode = '22023'; end if;
  perform set_config('belezando.fechando', 'sim', true);
  update comandas set status = 'fechada', caixa_id = v_caixa, fechada_em = now(), fechada_por = auth.uid() where id = p_comanda;
  perform set_config('belezando.fechando', '', true);
  update agendamentos set status = 'concluido'
  where id in (select agendamento_id from comanda_itens where comanda_id = p_comanda and agendamento_id is not null)
    and status not in ('cancelado', 'faltou', 'concluido');
  perform gerar_comissoes(p_comanda);
end
$$;

create or replace function usar_cashback(p_comanda uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v int;
  v_pag uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null or c.cliente_id is null then return 0; end if;
  perform 1 from clientes where id = c.cliente_id for update;
  select * into t from total_comanda(p_comanda);
  v := least(saldo_cashback(c.cliente_id), t.total - t.pago);
  if v <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'cashback', v) returning id into v_pag;
  insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, comanda_pagamento_id) values (c.salao_id, c.cliente_id, 'uso', -v, c.id, v_pag);
  return v;
end
$$;

create or replace function usar_credito_sinal(p_comanda uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  x sinais;
  v_pag uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta';
  if c.id is null or c.cliente_id is null then return 0; end if;
  select s.* into x from sinais s join agendamentos a on a.id = s.agendamento_id
  where s.salao_id = c.salao_id and a.cliente_id = c.cliente_id and s.status in ('pago', 'credito')
  order by s.pago_em nulls last, s.criado_em limit 1 for update of s;
  if x.id is null then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'sinal', x.valor_centavos) returning id into v_pag;
  update sinais set status = 'usado', comanda_pagamento_id = v_pag where id = x.id;
  return x.valor_centavos;
end
$$;

create or replace function usar_pacote(p_comanda uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  i comanda_itens;
  sd pacote_saldos;
  v_pag uuid;
  n int := 0;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null or c.cliente_id is null then return 0; end if;
  for i in select * from comanda_itens it where it.comanda_id = c.id and it.tipo = 'servico' and it.quantidade = 1
             and not exists (select 1 from pacote_usos u where u.comanda_item_id = it.id) loop
    sd := null;
    select ps.* into sd from pacote_saldos ps join pacotes_cliente pc on pc.id = ps.pacote_cliente_id
    where pc.cliente_id = c.cliente_id and pc.estado = 'ativo' and pc.expira_em > now() and ps.servico_id = i.servico_id and ps.usado < ps.total
    order by pc.expira_em limit 1 for update of ps;
    continue when sd.id is null;
    update comanda_itens set preco_centavos = sd.valor_unitario_centavos, desconto_centavos = 0 where id = i.id;
    if sd.valor_unitario_centavos > 0 then
      insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'pacote', sd.valor_unitario_centavos) returning id into v_pag;
    else
      v_pag := gen_random_uuid();
    end if;
    update pacote_saldos set usado = usado + 1 where id = sd.id;
    insert into pacote_usos (salao_id, saldo_id, comanda_item_id, comanda_pagamento_id, preco_original_centavos, desconto_original_centavos)
    values (c.salao_id, sd.id, i.id, v_pag, i.preco_centavos, i.desconto_centavos);
    n := n + 1;
  end loop;
  return n;
end
$$;

create or replace function usar_vale_presente(p_comanda uuid, p_codigo text) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  v vales_presente;
  t record;
  x int;
  v_pag uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  select * into v from vales_presente where salao_id = c.salao_id and codigo = upper(trim(p_codigo)) for update;
  if v.id is null then raise exception 'vale_nao_encontrado' using errcode = 'P0002'; end if;
  if v.estado <> 'ativo' or v.expira_em < now() then raise exception 'vale_vencido' using errcode = '55000'; end if;
  if v.comanda_id = c.id then raise exception 'vale_da_propria_comanda' using errcode = '22023'; end if;
  select * into t from total_comanda(p_comanda);
  x := least(v.saldo_centavos, t.total - t.pago);
  if x <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'vale_presente', x) returning id into v_pag;
  update vales_presente set saldo_centavos = saldo_centavos - x where id = v.id;
  insert into vale_presente_usos (salao_id, vale_id, comanda_pagamento_id, valor_centavos) values (c.salao_id, v.id, v_pag, x);
  return x;
end
$$;

-- ───────── 3) agenda: colunas travadas ─────────
revoke insert, update on agendamentos from authenticated;
grant insert (salao_id, cliente_id, profissional_id, servico_id, variacao_id, inicio, fim, fases, status, origem, grupo_id, serie_id, intervalo_min) on agendamentos to authenticated;
grant update (inicio, fim, profissional_id, status) on agendamentos to authenticated;

create or replace function checar_agenda_outros() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  -- Gravações feitas pelas funções do sistema (agendamento online, fechar comanda...) já conferem o que importa.
  if current_user <> 'authenticated' then return new; end if;
  if auth.uid() is null or meu_papel() is distinct from 'profissional' or pode('agenda_outros') then return new; end if;
  -- Sem a permissão, o profissional só mexe nos próprios horários: nada de mudar situação (falta, concluído) do horário de outro.
  if new.profissional_id <> auth.uid() or (tg_op = 'UPDATE' and old.profissional_id <> auth.uid()) then
    raise exception 'sem_permissao_agenda' using errcode = '42501';
  end if;
  return new;
end
$$;
