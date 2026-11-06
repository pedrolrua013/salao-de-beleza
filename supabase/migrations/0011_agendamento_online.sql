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
