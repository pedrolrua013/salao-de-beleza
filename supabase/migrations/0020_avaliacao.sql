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
