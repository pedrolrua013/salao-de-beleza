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
