-- Correções da banca de revisão (itens críticos):
-- 1) Receber pagamento e fechar comanda vira a permissão "caixa": admin e recepção por padrão; profissional só se o admin ligar.
-- 2) Desconto não pode passar dos serviços e "comer" a gorjeta (receita negativa pagando gorjeta inteira).
-- 3) Agenda: pela API só dá para mexer em horário, profissional e situação; promoção, cliente e token ficam travados.
--    Profissional sem "agenda_outros" não mexe em nada do horário de outra pessoa (nem marcar falta).

-- ───────── 1) permissão "caixa" ─────────
create or replace function pode(p_chave text) returns boolean
language sql stable security definer set search_path = public, pg_temp as
$$
  select coalesce((
    select case when m.papel = 'admin' then true
      else coalesce(case when m.permissoes ? p_chave then (m.permissoes ->> p_chave) = 'true' end,
        case p_chave
          when 'desconto' then true
          when 'agenda_outros' then true
          when 'comissoes' then m.papel = 'recepcao'
          when 'estoque' then m.papel = 'recepcao'
          when 'caixa' then m.papel = 'recepcao'
          else false
        end) end
    from membros m where m.user_id = auth.uid() and m.ativo), false)
$$;

drop policy if exists pags_escrever on comanda_pagamentos;
create policy pags_escrever on comanda_pagamentos for all to authenticated
  using (salao_id = (select meu_salao()) and (select pode('caixa')))
  with check (salao_id = (select meu_salao()) and (select pode('caixa')));

create or replace function fechar_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v_caixa uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  if c.status <> 'aberta' then raise exception 'comanda_fechada' using errcode = '55000'; end if;
  select id into v_caixa from caixas where salao_id = c.salao_id and fechado_em is null;
  if v_caixa is null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  select * into t from total_comanda(p_comanda);
  if not exists (select 1 from comanda_itens where comanda_id = p_comanda) then raise exception 'comanda_vazia' using errcode = '22023'; end if;
  -- A gorjeta é do profissional: o desconto não pode passar do resto e "pagar" a gorjeta com dinheiro do salão.
  if t.total < 0 or t.receita < 0 then raise exception 'desconto_maior_que_total' using errcode = '22023'; end if;
  if t.pago <> t.total then raise exception 'pagamento_diferente' using errcode = '22023'; end if;
  perform set_config('belezando.fechando', 'sim', true);
  update comandas set status = 'fechada', caixa_id = v_caixa, fechada_em = now(), fechada_por = auth.uid() where id = p_comanda;
  perform set_config('belezando.fechando', '', true);
  update agendamentos set status = 'concluido'
  where id in (select agendamento_id from comanda_itens where comanda_id = p_comanda and agendamento_id is not null)
    and status not in ('cancelado', 'faltou', 'concluido');
  perform gerar_comissoes(p_comanda);
end
$$;

create or replace function usar_cashback(p_comanda uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v int;
  v_pag uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta' for update;
  if c.id is null or c.cliente_id is null then return 0; end if;
  perform 1 from clientes where id = c.cliente_id for update;
  select * into t from total_comanda(p_comanda);
  v := least(saldo_cashback(c.cliente_id), t.total - t.pago);
  if v <= 0 then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'cashback', v) returning id into v_pag;
  insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, comanda_pagamento_id) values (c.salao_id, c.cliente_id, 'uso', -v, c.id, v_pag);
  return v;
end
$$;

create or replace function usar_credito_sinal(p_comanda uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  x sinais;
  v_pag uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() and status = 'aberta';
  if c.id is null or c.cliente_id is null then return 0; end if;
  select s.* into x from sinais s join agendamentos a on a.id = s.agendamento_id
  where s.salao_id = c.salao_id and a.cliente_id = c.cliente_id and s.status in ('pago', 'credito')
  order by s.pago_em nulls last, s.criado_em limit 1 for update of s;
  if x.id is null then return 0; end if;
  insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (c.salao_id, c.id, 'sinal', x.valor_centavos) returning id into v_pag;
  update sinais set status = 'usado', comanda_pagamento_id = v_pag where id = x.id;
  return x.valor_centavos;
end
$$;

create or replace function usar_pacote(p_comanda uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  i comanda_itens;
  sd pacote_saldos;
  v_pag uuid;
  n int := 0;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
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

create or replace function usar_vale_presente(p_comanda uuid, p_codigo text) returns integer
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  v vales_presente;
  t record;
  x int;
  v_pag uuid;
begin
  if not pode('caixa') then raise exception 'sem_permissao_caixa' using errcode = '42501'; end if;
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

-- ───────── 3) agenda: colunas travadas ─────────
revoke insert, update on agendamentos from authenticated;
grant insert (salao_id, cliente_id, profissional_id, servico_id, variacao_id, inicio, fim, fases, status, origem, grupo_id, serie_id, intervalo_min) on agendamentos to authenticated;
grant update (inicio, fim, profissional_id, status) on agendamentos to authenticated;

create or replace function checar_agenda_outros() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  -- Gravações feitas pelas funções do sistema (agendamento online, fechar comanda...) já conferem o que importa.
  if current_user <> 'authenticated' then return new; end if;
  if auth.uid() is null or meu_papel() is distinct from 'profissional' or pode('agenda_outros') then return new; end if;
  -- Sem a permissão, o profissional só mexe nos próprios horários: nada de mudar situação (falta, concluído) do horário de outro.
  if new.profissional_id <> auth.uid() or (tg_op = 'UPDATE' and old.profissional_id <> auth.uid()) then
    raise exception 'sem_permissao_agenda' using errcode = '42501';
  end if;
  return new;
end
$$;
