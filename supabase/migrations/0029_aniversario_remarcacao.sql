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
