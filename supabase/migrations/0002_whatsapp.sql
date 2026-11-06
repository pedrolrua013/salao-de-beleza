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
