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
