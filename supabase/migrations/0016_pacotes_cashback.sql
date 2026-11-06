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
