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
