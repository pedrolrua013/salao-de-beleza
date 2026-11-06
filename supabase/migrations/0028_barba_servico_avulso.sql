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
