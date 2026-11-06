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
