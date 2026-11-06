-- Belezando · correções da quarta revisão (cashback ao reabrir comanda, desconto na venda de pacote, uso simultâneo de crédito).

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
  v_itens int;
  v_cb int;
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    select * into s from saloes where id = new.salao_id;
    if exists (select 1 from comanda_itens where comanda_id = new.id and tipo::text = 'pacote') and new.cliente_id is null then
      raise exception 'pacote_sem_cliente' using errcode = '22023';
    end if;
    -- venda de pacote: nasce o saldo, com o valor de cada sessão proporcional ao preço de tabela (e com a parte do desconto da comanda)
    select coalesce(sum(preco_centavos * quantidade - desconto_centavos), 0) into v_itens from comanda_itens where comanda_id = new.id and tipo <> 'gorjeta';
    for i in select * from comanda_itens where comanda_id = new.id and tipo::text = 'pacote' loop
      select * into p from pacotes where id = i.pacote_id;
      insert into pacotes_cliente (salao_id, cliente_id, pacote_id, nome, tipo, comanda_id, expira_em)
      values (new.salao_id, new.cliente_id, p.id, p.nome, p.tipo, new.id, now() + make_interval(days => p.validade_dias)) returning id into v_pc;
      select sum(greatest(sv.preco_centavos, 1) * pi.quantidade) into v_soma from pacote_itens pi join servicos sv on sv.id = pi.servico_id where pi.pacote_id = p.id;
      insert into pacote_saldos (salao_id, pacote_cliente_id, servico_id, total, valor_unitario_centavos)
      select new.salao_id, v_pc, pi.servico_id, pi.quantidade,
             round((i.preco_centavos - i.desconto_centavos
                    - case when v_itens > 0 then new.desconto_centavos::numeric * (i.preco_centavos - i.desconto_centavos) / v_itens else 0 end)
                   * greatest(sv.preco_centavos, 1)::numeric / nullif(v_soma, 0))::int
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
    -- cashback desta comanda que já foi gasto: não dá para desfazer
    select coalesce(sum(valor_centavos), 0) into v_cb from cashback_movimentos where comanda_id = new.id and tipo = 'credito' and expira_em > now();
    if v_cb > 0 and saldo_cashback(old.cliente_id) < v_cb then
      raise exception 'cashback_ja_usado' using errcode = '55000';
    end if;
    delete from pacotes_cliente where comanda_id = new.id;
    delete from cashback_movimentos where comanda_id = new.id and tipo = 'credito';
  end if;
  return new;
end
$$;

-- Um uso de cashback de cada vez por cliente e por comanda.
create or replace function usar_cashback(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v int;
  v_pag uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null or c.cliente_id is null then return 0; end if;
  perform 1 from clientes where id = c.cliente_id for update;  -- um uso de cada vez por cliente
  select * into t from total_comanda(p_comanda);
  v := least(saldo_cashback(c.cliente_id), t.total - t.pago);
  if v <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'cashback', v) returning id into v_pag;
  insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, comanda_pagamento_id) values (c.salao_id, c.cliente_id, 'uso', -v, c.id, v_pag);
  return v;
end
$$;

create or replace function usar_vale_presente(p_comanda uuid, p_codigo text) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  v vales_presente;
  t record;
  x int;
  v_pag uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
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

create or replace function usar_pacote(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  i comanda_itens;
  sd pacote_saldos;
  v_pag uuid;
  n int := 0;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
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
