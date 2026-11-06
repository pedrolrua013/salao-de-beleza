-- Sugestão de complemento, fidelidade por níveis, pedido de compra, indique uma amiga, metas e permissões da equipe,
-- cobrança pelo celular (comanda, vale e pacote pelo link), área da cliente, taxa por falta, relatórios com previsão,
-- fichas de estética e a chave da IA no WhatsApp.

alter type tipo_item add value if not exists 'taxa';

-- ───────────── permissões sob medida ─────────────
alter table membros add column permissoes jsonb not null default '{}' check (jsonb_typeof(permissoes) = 'object' and length(permissoes::text) <= 1000);
grant update (permissoes) on membros to authenticated;

-- Administrador pode tudo. Para os outros, vale o que o administrador marcou; sem marcação, o padrão do papel.
create function pode(p_chave text) returns boolean
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
          else false
        end) end
    from membros m where m.user_id = auth.uid() and m.ativo), false)
$$;
revoke all on function pode(text) from public, anon;
grant execute on function pode(text) to authenticated;

-- Painel: quem tem a permissão "painel" (além do administrador) vê.
do $$
declare d text;
begin
  select pg_get_functiondef('painel(date,date)'::regprocedure) into d;
  if position('meu_papel() is distinct from ''admin''' in d) = 0 then raise exception 'painel() mudou: revise a troca da permissão'; end if;
  execute replace(d, 'meu_papel() is distinct from ''admin''', 'not pode(''painel'')');
end $$;

-- Divulgar (promoções e campanhas): administrador ou quem tem a permissão "divulgar".
drop policy promo_criar on promocoes; drop policy promo_editar on promocoes; drop policy promo_apagar on promocoes;
create policy promo_criar on promocoes for insert to authenticated with check (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy promo_editar on promocoes for update to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy promo_apagar on promocoes for delete to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')));
drop policy camp_ler on campanhas; drop policy camp_criar on campanhas; drop policy camp_apagar on campanhas;
create policy camp_ler on campanhas for select to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy camp_criar on campanhas for insert to authenticated with check (salao_id = (select meu_salao()) and (select pode('divulgar')));
create policy camp_apagar on campanhas for delete to authenticated using (salao_id = (select meu_salao()) and (select pode('divulgar')) and disparada_em is null);
do $$
declare f text; d text;
begin
  foreach f in array array['contar_publico_campanha(text[],integer)', 'disparar_campanha(uuid)'] loop
    select pg_get_functiondef(f::regprocedure) into d;
    if position('meu_papel() is distinct from ''admin''' in d) = 0 then raise exception '% mudou', f; end if;
    execute replace(d, 'meu_papel() is distinct from ''admin''', 'not pode(''divulgar'')');
  end loop;
end $$;

-- Só vale para o que a pessoa faz direto pela tela: as funções do sistema (security definer) rodam com outro usuário e passam.
-- Por isso estes gatilhos são security invoker: current_user mostra quem está mexendo.
create function checar_agenda_outros() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if current_user <> 'authenticated' then return new; end if;
  if auth.uid() is null or meu_papel() is distinct from 'profissional' or pode('agenda_outros') then return new; end if;
  if tg_op = 'UPDATE' and new.inicio = old.inicio and new.profissional_id = old.profissional_id and new.servico_id = old.servico_id
     and (new.status = old.status or new.status <> 'cancelado') then return new; end if;
  if new.profissional_id <> auth.uid() or (tg_op = 'UPDATE' and old.profissional_id <> auth.uid()) then
    raise exception 'sem_permissao_agenda' using errcode = '42501';
  end if;
  return new;
end
$$;
revoke execute on function checar_agenda_outros() from public, anon, authenticated;
create trigger checar_agenda_outros before insert or update on agendamentos for each row execute function checar_agenda_outros();

-- Desconto na comanda: quem não pode só lança o desconto da promoção do horário.
create function checar_desconto() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
declare
  v_pct int;
  v_novo int := new.desconto_centavos;
begin
  if current_user <> 'authenticated' then return new; end if;
  if auth.uid() is null or pode('desconto') or v_novo = 0 then return new; end if;
  if tg_op = 'UPDATE' and v_novo <= old.desconto_centavos then return new; end if;
  if tg_table_name = 'comanda_itens' then
    if new.agendamento_id is not null then
      select promocao_percentual into v_pct from agendamentos where id = new.agendamento_id;
      if v_novo <= round(new.preco_centavos * new.quantidade * coalesce(v_pct, 0) / 100.0) then return new; end if;
    end if;
  end if;
  raise exception 'sem_permissao_desconto' using errcode = '42501';
end
$$;
revoke execute on function checar_desconto() from public, anon, authenticated;
create trigger checar_desconto before insert or update of desconto_centavos on comanda_itens for each row execute function checar_desconto();
create trigger checar_desconto before update of desconto_centavos on comandas for each row execute function checar_desconto();

-- ───────────── sugestão de complemento ─────────────
alter table servicos add column complementos uuid[] not null default '{}' check (cardinality(complementos) <= 5);
alter table servicos add column produtos_sugeridos uuid[] not null default '{}' check (cardinality(produtos_sugeridos) <= 5);
grant insert (complementos, produtos_sugeridos) on servicos to authenticated;
grant update (complementos, produtos_sugeridos) on servicos to authenticated;

-- ───────────── fidelidade por pontos e níveis ─────────────
create function niveis_ok(n jsonb) returns boolean
language sql immutable set search_path = public, pg_temp as
$$
  select jsonb_typeof(n) = 'array' and jsonb_array_length(n) <= 5 and coalesce((
    select bool_and(jsonb_typeof(x -> 'nome') = 'string' and length(x ->> 'nome') between 1 and 20
      and jsonb_typeof(x -> 'pontos') = 'number' and (x ->> 'pontos')::numeric between 1 and 1000000
      and jsonb_typeof(x -> 'bonus') = 'number' and (x ->> 'bonus')::numeric between 0 and 20)
    from jsonb_array_elements(n) x), true)
$$;
alter table saloes add column fidelidade_ativa boolean not null default false;
alter table saloes add column fidelidade_niveis jsonb not null default '[{"nome":"Prata","pontos":500,"bonus":1},{"nome":"Ouro","pontos":1500,"bonus":3},{"nome":"Diamante","pontos":3000,"bonus":5}]' check (niveis_ok(fidelidade_niveis));
grant update (fidelidade_ativa, fidelidade_niveis) on saloes to authenticated;

-- 1 ponto por real pago nos últimos 12 meses (pacote usado e cashback não contam: já foram pagos antes).
create function pontos_fidelidade(p_salao uuid, p_cliente uuid) returns int
language sql stable security definer set search_path = public, pg_temp as
$$
  select (coalesce(sum(p.valor_centavos), 0) / 100)::int
  from comanda_pagamentos p join comandas c on c.id = p.comanda_id
  where c.salao_id = p_salao and c.cliente_id = p_cliente and c.status = 'fechada' and c.fechada_em > now() - interval '365 days'
    and p.forma::text not in ('pacote', 'cashback')
$$;
revoke all on function pontos_fidelidade(uuid, uuid) from public, anon, authenticated;

create function fidelidade_interna(p_salao uuid, p_cliente uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_pts int;
  n jsonb; v_nivel jsonb; v_prox jsonb;
begin
  select * into s from saloes where id = p_salao;
  if s.id is null or not s.fidelidade_ativa then return null; end if;
  v_pts := pontos_fidelidade(p_salao, p_cliente);
  for n in select x from jsonb_array_elements(s.fidelidade_niveis) x order by (x ->> 'pontos')::numeric loop
    if v_pts >= (n ->> 'pontos')::numeric then v_nivel := n; elsif v_prox is null then v_prox := n; end if;
  end loop;
  return jsonb_build_object('pontos', v_pts, 'nivel', v_nivel ->> 'nome', 'bonus', coalesce((v_nivel ->> 'bonus')::numeric, 0),
    'proximo', v_prox ->> 'nome', 'faltam', case when v_prox is null then null else (v_prox ->> 'pontos')::numeric - v_pts end);
end
$$;
revoke all on function fidelidade_interna(uuid, uuid) from public, anon, authenticated;
grant execute on function fidelidade_interna(uuid, uuid) to service_role;

create function fidelidade(p_cliente uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$ select fidelidade_interna(c.salao_id, c.id) from clientes c where c.id = p_cliente and c.salao_id = meu_salao() $$;
revoke all on function fidelidade(uuid) from public, anon;
grant execute on function fidelidade(uuid) to authenticated;

-- Bônus do nível: cashback extra sobre o que foi pago na comanda (some se a comanda for reaberta, junto com o cashback).
create function bonus_fidelidade() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  f jsonb;
  v_base int; v_bonus int;
begin
  if not (new.status = 'fechada' and old.status = 'aberta' and new.cliente_id is not null) then return null; end if;
  select * into s from saloes where id = new.salao_id;
  if not s.fidelidade_ativa then return null; end if;
  f := fidelidade_interna(new.salao_id, new.cliente_id);
  if coalesce((f ->> 'bonus')::numeric, 0) <= 0 then return null; end if;
  select coalesce(sum(valor_centavos), 0) into v_base from comanda_pagamentos where comanda_id = new.id and forma::text not in ('pacote', 'cashback');
  v_base := v_base - coalesce((select sum(preco_centavos) from comanda_itens where comanda_id = new.id and tipo = 'gorjeta'), 0);
  v_bonus := floor(greatest(v_base, 0) * (f ->> 'bonus')::numeric / 100);
  if v_bonus > 0 then
    insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, expira_em)
    values (new.salao_id, new.cliente_id, 'credito', v_bonus, new.id, now() + make_interval(days => s.cashback_validade_dias));
  end if;
  return null;
end
$$;
revoke execute on function bonus_fidelidade() from public, anon, authenticated;
create trigger zz_bonus_fidelidade after update of status on comandas for each row execute function bonus_fidelidade();

-- ───────────── pedido de compra ao fornecedor ─────────────
create table fornecedores (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 120),
  telefone text check (telefone ~ '^[0-9]{10,13}$'),
  email text check (length(email) <= 200),
  observacao text check (length(observacao) <= 300),
  criado_em timestamptz not null default now(),
  unique (id, salao_id)
);
alter table fornecedores enable row level security;
create policy forn_ler on fornecedores for select to authenticated using (salao_id = (select meu_salao()));
create policy forn_escrever on fornecedores for all to authenticated using (salao_id = (select meu_salao()) and (select pode('estoque'))) with check (salao_id = (select meu_salao()) and (select pode('estoque')));
revoke all on fornecedores from anon, authenticated;
grant select, delete on fornecedores to authenticated;
grant insert (nome, telefone, email, observacao) on fornecedores to authenticated;
grant update (nome, telefone, email, observacao) on fornecedores to authenticated;

alter table produtos add column fornecedor_id uuid;
alter table produtos add constraint produto_fornecedor foreign key (fornecedor_id, salao_id) references fornecedores (id, salao_id) on delete set null (fornecedor_id);
alter table produtos add column estoque_ideal numeric(12,2) check (estoque_ideal >= 0);
grant update (fornecedor_id, estoque_ideal) on produtos to authenticated;

create table pedidos_compra (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  fornecedor_id uuid,
  status text not null default 'aberto' check (status in ('aberto', 'recebido', 'cancelado')),
  observacao text check (length(observacao) <= 300),
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  recebido_em timestamptz,
  unique (id, salao_id),
  foreign key (fornecedor_id, salao_id) references fornecedores (id, salao_id) on delete set null (fornecedor_id)
);
create table pedido_compra_itens (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  pedido_id uuid not null,
  produto_id uuid not null,
  embalagens numeric(10,2) not null check (embalagens > 0 and embalagens <= 10000),
  custo_centavos int check (custo_centavos between 0 and 10000000),   -- por embalagem
  unique (pedido_id, produto_id),
  foreign key (pedido_id, salao_id) references pedidos_compra (id, salao_id) on delete cascade,
  foreign key (produto_id, salao_id) references produtos (id, salao_id) on delete cascade
);
alter table pedidos_compra enable row level security;
alter table pedido_compra_itens enable row level security;
create policy ped_tudo on pedidos_compra for all to authenticated using (salao_id = (select meu_salao()) and (select pode('estoque'))) with check (salao_id = (select meu_salao()) and (select pode('estoque')));
create policy pedi_tudo on pedido_compra_itens for all to authenticated using (salao_id = (select meu_salao()) and (select pode('estoque'))) with check (salao_id = (select meu_salao()) and (select pode('estoque')));
revoke all on pedidos_compra, pedido_compra_itens from anon, authenticated;
grant select, delete on pedidos_compra, pedido_compra_itens to authenticated;
grant insert (fornecedor_id, observacao) on pedidos_compra to authenticated;
grant update (status) on pedidos_compra to authenticated;
grant insert (pedido_id, produto_id, embalagens, custo_centavos) on pedido_compra_itens to authenticated;

-- Chegou a mercadoria: entrada no estoque de cada item, de uma vez.
create function receber_pedido(p_pedido uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  p pedidos_compra;
  v_n int;
begin
  if not pode('estoque') then raise exception 'sem permissão' using errcode = '42501'; end if;
  select * into p from pedidos_compra where id = p_pedido and salao_id = meu_salao() for update;
  if p.id is null then raise exception 'pedido não encontrado' using errcode = 'P0002'; end if;
  if p.status <> 'aberto' then raise exception 'pedido_ja_recebido' using errcode = '55000'; end if;
  insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, custo_centavos, motivo, feito_por)
  select i.salao_id, i.produto_id, 'entrada', case when pr.unidade = 'un' then i.embalagens else i.embalagens * pr.conteudo end,
         case when i.custo_centavos is null then null else round(i.custo_centavos * i.embalagens)::int end, 'Pedido de compra', auth.uid()
  from pedido_compra_itens i join produtos pr on pr.id = i.produto_id where i.pedido_id = p.id;
  get diagnostics v_n = row_count;
  update pedidos_compra set status = 'recebido', recebido_em = now() where id = p.id;
  return v_n;
end
$$;
revoke all on function receber_pedido(uuid) from public, anon;
grant execute on function receber_pedido(uuid) to authenticated;

-- ───────────── indique uma amiga e origem do link ─────────────
alter table saloes add column indicacao_credito_centavos int not null default 0 check (indicacao_credito_centavos between 0 and 100000);
grant update (indicacao_credito_centavos) on saloes to authenticated;
alter table clientes add column codigo_indicacao text check (codigo_indicacao ~ '^[A-Z2-9]{6}$');
create unique index clientes_codigo_indicacao on clientes (salao_id, codigo_indicacao) where codigo_indicacao is not null;

create function codigo_indicacao_interno(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c clientes;
  v text;
  abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  select * into c from clientes where id = p_cliente for update;
  if c.id is null then return null; end if;
  if c.codigo_indicacao is not null then return c.codigo_indicacao; end if;
  loop
    v := (select string_agg(substr(abc, 1 + floor(random() * length(abc))::int, 1), '') from generate_series(1, 6));
    exit when not exists (select 1 from clientes where salao_id = c.salao_id and codigo_indicacao = v);
  end loop;
  update clientes set codigo_indicacao = v where id = c.id;
  return v;
end
$$;
revoke all on function codigo_indicacao_interno(uuid) from public, anon, authenticated;
grant execute on function codigo_indicacao_interno(uuid) to service_role;
create function codigo_indicacao(p_cliente uuid) returns text
language sql security definer set search_path = public, pg_temp as
$$ select codigo_indicacao_interno(id) from clientes where id = p_cliente and salao_id = meu_salao() $$;
revoke all on function codigo_indicacao(uuid) from public, anon;
grant execute on function codigo_indicacao(uuid) to authenticated;

create table indicacoes_premiadas (
  indicada_id uuid primary key,
  salao_id uuid not null references saloes (id) on delete cascade,
  indicadora_id uuid not null,
  comanda_id uuid not null,
  valor_centavos int not null,
  criado_em timestamptz not null default now(),
  foreign key (indicada_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (indicadora_id, salao_id) references clientes (id, salao_id) on delete cascade
);
alter table indicacoes_premiadas enable row level security;
create policy indp_ler on indicacoes_premiadas for select to authenticated using (salao_id = (select meu_salao()));
revoke all on indicacoes_premiadas from anon, authenticated;
grant select on indicacoes_premiadas to authenticated;

-- Cliente nova que marcou pelo link de uma amiga (ou veio do Google, Instagram, QR...): guarda quem indicou e de onde veio.
create function vincular_origem(p_agendamento uuid, p_codigo text, p_origem text) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c clientes;
  v_ind uuid;
begin
  select cl.* into c from agendamentos a join clientes cl on cl.id = a.cliente_id where a.id = p_agendamento;
  if c.id is null or c.criado_em < now() - interval '1 hour' then return; end if;   -- só cadastro que acabou de nascer
  if p_codigo ~ '^[A-Z2-9]{6}$' then
    select id into v_ind from clientes where salao_id = c.salao_id and codigo_indicacao = p_codigo and id <> c.id;
  end if;
  update clientes set indicado_por = coalesce(indicado_por, v_ind),
    origem = coalesce(origem, case when v_ind is not null then 'indicacao'
                                   when p_origem in ('instagram', 'google', 'facebook', 'tiktok', 'whatsapp') then p_origem end)
  where id = c.id;
end
$$;
revoke all on function vincular_origem(uuid, text, text) from public, anon, authenticated;
grant execute on function vincular_origem(uuid, text, text) to service_role;

-- Na primeira comanda fechada da indicada, quem indicou ganha o crédito (vira cashback). Reabrir desfaz.
create function premiar_indicacao() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_ind uuid;
begin
  if old.status = 'fechada' and new.status <> 'fechada' then
    delete from indicacoes_premiadas where comanda_id = new.id;
    return null;
  end if;
  if not (new.status = 'fechada' and old.status = 'aberta' and new.cliente_id is not null) then return null; end if;
  select * into s from saloes where id = new.salao_id;
  if s.indicacao_credito_centavos <= 0 then return null; end if;
  select indicado_por into v_ind from clientes where id = new.cliente_id;
  if v_ind is null
     or exists (select 1 from comandas where cliente_id = new.cliente_id and status = 'fechada' and id <> new.id)
     or exists (select 1 from indicacoes_premiadas where indicada_id = new.cliente_id) then return null; end if;
  insert into cashback_movimentos (salao_id, cliente_id, tipo, valor_centavos, comanda_id, expira_em)
  values (new.salao_id, v_ind, 'credito', s.indicacao_credito_centavos, new.id, now() + make_interval(days => s.cashback_validade_dias));
  insert into indicacoes_premiadas (indicada_id, salao_id, indicadora_id, comanda_id, valor_centavos)
  values (new.cliente_id, new.salao_id, v_ind, new.id, s.indicacao_credito_centavos);
  return null;
end
$$;
revoke execute on function premiar_indicacao() from public, anon, authenticated;
create trigger zz_premiar_indicacao after update of status on comandas for each row execute function premiar_indicacao();

-- ───────────── metas da equipe ─────────────
create table metas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  membro_id uuid,                                  -- vazio = meta do salão
  mes date not null check (extract(day from mes) = 1),
  tipo text not null check (tipo in ('faturamento', 'produtos', 'atendimentos')),
  valor int not null check (valor between 1 and 1000000000),
  criado_em timestamptz not null default now(),
  foreign key (membro_id, salao_id) references membros (user_id, salao_id) on delete cascade
);
create unique index metas_unica on metas (salao_id, coalesce(membro_id, '00000000-0000-0000-0000-000000000000'::uuid), mes, tipo);
alter table metas enable row level security;
create policy metas_ler on metas for select to authenticated using (salao_id = (select meu_salao()) and ((select meu_papel()) = 'admin' or membro_id is null or membro_id = (select auth.uid())));
create policy metas_escrever on metas for all to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin') with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on metas from anon, authenticated;
grant select, delete on metas to authenticated;
grant insert (membro_id, mes, tipo, valor) on metas to authenticated;
grant update (valor) on metas to authenticated;

-- Quanto já foi feito de cada meta do mês (faturamento e produtos em centavos; atendimentos em quantidade).
create function progresso_metas(p_mes date) returns table (id uuid, membro_id uuid, tipo text, valor int, realizado bigint)
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
begin
  select * into s from saloes where saloes.id = v_salao;
  de := (date_trunc('month', p_mes)::timestamp) at time zone s.fuso;
  ate := ((date_trunc('month', p_mes) + interval '1 month')::timestamp) at time zone s.fuso;
  return query
  with itens as (
    select i.tipo::text as t, i.profissional_id as prof, (i.preco_centavos * i.quantidade - i.desconto_centavos)::bigint as v
    from comanda_itens i join comandas c on c.id = i.comanda_id
    where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo::text in ('servico', 'produto')
  )
  select m.id, m.membro_id, m.tipo, m.valor,
    (case m.tipo
      when 'faturamento' then (select coalesce(sum(v), 0) from itens where m.membro_id is null or prof = m.membro_id)
      when 'produtos' then (select coalesce(sum(v), 0) from itens where t = 'produto' and (m.membro_id is null or prof = m.membro_id))
      else (select count(*) from itens where t = 'servico' and (m.membro_id is null or prof = m.membro_id))
    end)::bigint
  from metas m
  where m.salao_id = v_salao and m.mes = date_trunc('month', p_mes)::date
    and (meu_papel() = 'admin' or m.membro_id is null or m.membro_id = auth.uid());
end
$$;
revoke all on function progresso_metas(date) from public, anon;
grant execute on function progresso_metas(date) to authenticated;

-- ───────────── cobrança pelo celular: comanda, vale-presente e pacote pelo link ─────────────
alter table saloes add column venda_online boolean not null default false;
grant update (venda_online) on saloes to authenticated;
alter table pacotes add column online boolean not null default false;
grant update (online) on pacotes to authenticated;

create table cobrancas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  tipo text not null check (tipo in ('comanda', 'vale', 'pacote')),
  comanda_id uuid,
  pacote_id uuid,
  cliente_id uuid,
  valor_centavos int not null check (valor_centavos between 100 and 10000000),
  nome text check (length(nome) <= 120),
  presente_para text check (length(presente_para) <= 80),
  presente_mensagem text check (length(presente_mensagem) <= 200),
  token_hash text not null unique,
  status text not null default 'pendente' check (status in ('pendente', 'paga', 'cancelada')),
  modo text not null default 'pix_manual' check (modo in ('pix_manual', 'mercadopago')),
  mp_payment_id text,
  copia_cola text check (length(copia_cola) <= 600),
  expira_em timestamptz not null default now() + interval '2 days',
  paga_em timestamptz,
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade,
  foreign key (pacote_id, salao_id) references pacotes (id, salao_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete set null (cliente_id),
  check (tipo <> 'comanda' or comanda_id is not null),
  check (tipo <> 'pacote' or pacote_id is not null),
  check (tipo <> 'vale' or presente_para is not null)
);
create unique index cobrancas_mp on cobrancas (mp_payment_id) where mp_payment_id is not null;
create index on cobrancas (salao_id, status, criado_em desc);
create index on cobrancas (comanda_id);
alter table cobrancas enable row level security;
create policy cob_ler on cobrancas for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao'));
revoke all on cobrancas from anon, authenticated;
grant select (id, salao_id, tipo, comanda_id, pacote_id, cliente_id, valor_centavos, nome, presente_para, presente_mensagem, status, modo, copia_cola, expira_em, paga_em, criado_em) on cobrancas to authenticated;

create function novo_token() returns text
language sql volatile set search_path = public, pg_temp as
$$ select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') $$;
revoke all on function novo_token() from public, anon, authenticated;
create function hash_token(p text) returns text
language sql immutable set search_path = public, pg_temp as
$$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;

-- Quanto falta pagar na comanda (itens - desconto - pagamentos).
create function restante_comanda(p_comanda uuid) returns int
language sql stable security definer set search_path = public, pg_temp as
$$
  select (coalesce((select sum(preco_centavos * quantidade - desconto_centavos) from comanda_itens where comanda_id = c.id), 0)
          - c.desconto_centavos
          - coalesce((select sum(valor_centavos) from comanda_pagamentos where comanda_id = c.id), 0))::int
  from comandas c where c.id = p_comanda
$$;
revoke all on function restante_comanda(uuid) from public, anon, authenticated;

-- A recepção gera o link para a cliente pagar o que falta da comanda pelo celular.
create function criar_cobranca_comanda(p_comanda uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  v_valor int;
  v_token text := novo_token();
  v_id uuid;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  if c.status <> 'aberta' then raise exception 'comanda_fechada' using errcode = '55000'; end if;
  v_valor := restante_comanda(c.id);
  if v_valor < 100 then raise exception 'nada_a_cobrar' using errcode = '22023'; end if;
  update cobrancas set status = 'cancelada' where comanda_id = c.id and status = 'pendente';
  insert into cobrancas (salao_id, tipo, comanda_id, cliente_id, valor_centavos, token_hash)
  values (c.salao_id, 'comanda', c.id, c.cliente_id, v_valor, hash_token(v_token)) returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'valor_centavos', v_valor);
end
$$;
revoke all on function criar_cobranca_comanda(uuid) from public, anon;
grant execute on function criar_cobranca_comanda(uuid) to authenticated;

-- Vale-presente ou pacote comprado pelo link: a cliente é achada (ou cadastrada) pelo celular.
create function criar_pedido_online(p_slug text, p_tipo text, p_pacote uuid, p_valor int, p_nome text, p_telefone text, p_para text, p_mensagem text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  pk pacotes;
  v_tel text := tel_nacional(p_telefone);
  v_nome text := left(regexp_replace(trim(coalesce(p_nome, '')), '\s+', ' ', 'g'), 120);
  v_cli uuid;
  v_valor int;
  v_token text := novo_token();
  v_id uuid;
begin
  select * into s from saloes where slug = p_slug;
  if s.id is null or not s.venda_online then raise exception 'venda_indisponivel' using errcode = '55000'; end if;
  if length(v_nome) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if p_tipo = 'pacote' then
    select * into pk from pacotes where id = p_pacote and salao_id = s.id and ativo and online;
    if pk.id is null then raise exception 'pacote_indisponivel' using errcode = 'P0002'; end if;
    v_valor := pk.preco_centavos;
  elsif p_tipo = 'vale' then
    if p_valor is null or p_valor not between 2000 and 200000 then raise exception 'valor_invalido' using errcode = '22023'; end if;
    if length(trim(coalesce(p_para, ''))) < 2 then raise exception 'presente_sem_nome' using errcode = '22023'; end if;
    v_valor := p_valor;
  else
    raise exception 'tipo inválido' using errcode = '22023';
  end if;
  select id into v_cli from clientes where salao_id = s.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli is null then
    insert into clientes (salao_id, nome, telefone) values (s.id, v_nome, v_tel) returning id into v_cli;
  end if;
  insert into cobrancas (salao_id, tipo, pacote_id, cliente_id, valor_centavos, nome, presente_para, presente_mensagem, token_hash)
  values (s.id, p_tipo, case when p_tipo = 'pacote' then pk.id end, v_cli, v_valor, v_nome,
          case when p_tipo = 'vale' then left(trim(p_para), 80) end, case when p_tipo = 'vale' then left(nullif(trim(p_mensagem), ''), 200) end,
          hash_token(v_token))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'valor_centavos', v_valor);
end
$$;

create function registrar_pix_cobranca(p_id uuid, p_copia_cola text, p_mp_payment_id text, p_modo text) returns void
language sql security definer set search_path = public, pg_temp as
$$ update cobrancas set copia_cola = left(p_copia_cola, 600), mp_payment_id = p_mp_payment_id, modo = p_modo where id = p_id and status = 'pendente' $$;

create function cobranca_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('id', b.id, 'salao', s.nome, 'slug', s.slug, 'tipo', b.tipo, 'valor_centavos', b.valor_centavos,
    'status', case when b.status = 'pendente' and b.expira_em < now() then 'expirada' else b.status end,
    'copia_cola', b.copia_cola, 'modo', b.modo, 'presente_para', b.presente_para, 'nome', coalesce(b.nome, cl.nome),
    'pacote', (select nome from pacotes where id = b.pacote_id),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('descricao', i.descricao, 'valor', i.preco_centavos * i.quantidade - i.desconto_centavos) order by i.criado_em), '[]')
              from comanda_itens i where b.tipo = 'comanda' and i.comanda_id = b.comanda_id))
  from cobrancas b join saloes s on s.id = b.salao_id left join clientes cl on cl.id = b.cliente_id
  where b.token_hash = hash_token(p_token)
$$;

-- Pagamento confirmado: na comanda entra o Pix; vale e pacote viram uma comanda aberta com o item e o Pix,
-- que a recepção fecha no caixa do dia (é ao fechar que o vale e o pacote passam a valer).
create function quitar_cobranca(p_id uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  b cobrancas;
  v_cmd uuid;
begin
  select * into b from cobrancas where id = p_id for update;
  if b.id is null then return 'nao_encontrada'; end if;
  if b.status = 'paga' then return 'ja_paga'; end if;
  if b.status = 'cancelada' then return 'cancelada'; end if;
  if b.tipo = 'comanda' then
    if not exists (select 1 from comandas where id = b.comanda_id and status = 'aberta') then return 'comanda_fechada'; end if;
    insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (b.salao_id, b.comanda_id, 'pix', b.valor_centavos);
  else
    insert into comandas (salao_id, cliente_id, observacao) values (b.salao_id, b.cliente_id, 'Venda pelo link') returning id into v_cmd;
    if b.tipo = 'vale' then
      insert into comanda_itens (salao_id, comanda_id, tipo, descricao, preco_centavos, presente_para, presente_mensagem)
      values (b.salao_id, v_cmd, 'vale_presente', left('Vale-presente para ' || b.presente_para, 160), b.valor_centavos, b.presente_para, b.presente_mensagem);
    else
      insert into comanda_itens (salao_id, comanda_id, tipo, pacote_id, descricao, preco_centavos)
      values (b.salao_id, v_cmd, 'pacote', b.pacote_id, (select left(nome, 160) from pacotes where id = b.pacote_id), b.valor_centavos);
    end if;
    insert into comanda_pagamentos (salao_id, comanda_id, forma, valor_centavos) values (b.salao_id, v_cmd, 'pix', b.valor_centavos);
    update cobrancas set comanda_id = v_cmd where id = b.id;
  end if;
  update cobrancas set status = 'paga', paga_em = now() where id = b.id;
  return 'paga';
end
$$;
revoke all on function quitar_cobranca(uuid) from public, anon, authenticated;

-- A recepção confere o Pix no banco e confirma.
create function confirmar_cobranca(p_id uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  if not exists (select 1 from cobrancas where id = p_id and salao_id = meu_salao()) then raise exception 'cobrança não encontrada' using errcode = 'P0002'; end if;
  return quitar_cobranca(p_id);
end
$$;
revoke all on function confirmar_cobranca(uuid) from public, anon;
grant execute on function confirmar_cobranca(uuid) to authenticated;

create function cancelar_cobranca(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  update cobrancas set status = 'cancelada' where id = p_id and salao_id = meu_salao() and status = 'pendente';
end
$$;
revoke all on function cancelar_cobranca(uuid) from public, anon;
grant execute on function cancelar_cobranca(uuid) to authenticated;

-- Aviso do Mercado Pago (o servidor já consultou o pagamento na API): confere o valor e quita.
create function cobranca_paga_mp(p_payment_id text, p_valor_centavos int, p_salao uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_id uuid;
begin
  select id into v_id from cobrancas where mp_payment_id = p_payment_id and salao_id = p_salao and valor_centavos <= p_valor_centavos;
  if v_id is null then return 'nao_encontrada'; end if;
  return quitar_cobranca(v_id);
end
$$;
revoke all on function criar_pedido_online(text, text, uuid, int, text, text, text, text), registrar_pix_cobranca(uuid, text, text, text),
  cobranca_publica(text), cobranca_paga_mp(text, int, uuid) from public, anon, authenticated;
grant execute on function criar_pedido_online(text, text, uuid, int, text, text, text, text), registrar_pix_cobranca(uuid, text, text, text),
  cobranca_publica(text), cobranca_paga_mp(text, int, uuid) to service_role;

-- ───────────── taxa por falta ─────────────
alter table saloes add column taxa_falta_centavos int not null default 0 check (taxa_falta_centavos between 0 and 50000);
grant update (taxa_falta_centavos) on saloes to authenticated;

create table taxas_falta (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  agendamento_id uuid not null unique references agendamentos (id) on delete cascade,
  valor_centavos int not null check (valor_centavos > 0),
  falta_em timestamptz not null,
  perdoada_em timestamptz,
  perdoada_por uuid,
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on taxas_falta (cliente_id);
alter table taxas_falta enable row level security;
create policy taxa_ler on taxas_falta for select to authenticated using (salao_id = (select meu_salao()));
revoke all on taxas_falta from anon, authenticated;
grant select on taxas_falta to authenticated;

alter table comanda_itens add column taxa_falta_id uuid references taxas_falta (id) on delete set null;
alter table comanda_itens add constraint item_taxa_ok check (tipo::text <> 'taxa' or (taxa_falta_id is not null and quantidade = 1 and profissional_id is null));
grant insert (taxa_falta_id) on comanda_itens to authenticated;

-- Faltou sem avisar: nasce a taxa (VIP e quem pagou sinal não pagam; uma por visita). Desmarcar a falta apaga a que não foi cobrada.
create function gerar_taxa_falta() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_valor int;
begin
  if new.status = 'faltou' and old.status <> 'faltou' then
    select taxa_falta_centavos into v_valor from saloes where id = new.salao_id;
    if v_valor > 0
       and not exists (select 1 from clientes where id = new.cliente_id and vip)
       and not exists (select 1 from sinais where agendamento_id = new.id and status in ('pago', 'credito'))
       and not (new.grupo_id is not null and exists (select 1 from taxas_falta t join agendamentos a on a.id = t.agendamento_id where a.grupo_id = new.grupo_id)) then
      insert into taxas_falta (salao_id, cliente_id, agendamento_id, valor_centavos, falta_em) values (new.salao_id, new.cliente_id, new.id, v_valor, new.inicio)
      on conflict (agendamento_id) do nothing;
    end if;
  elsif old.status = 'faltou' and new.status <> 'faltou' then
    delete from taxas_falta t where t.agendamento_id = new.id and not exists (select 1 from comanda_itens i where i.taxa_falta_id = t.id);
  end if;
  return null;
end
$$;
revoke execute on function gerar_taxa_falta() from public, anon, authenticated;
create trigger gerar_taxa_falta after update of status on agendamentos for each row execute function gerar_taxa_falta();

-- Taxa só entra na comanda da própria cliente, uma vez (comanda cancelada libera para cobrar de novo).
create function checar_item_taxa() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  t taxas_falta;
begin
  if new.taxa_falta_id is null then return new; end if;
  select * into t from taxas_falta where id = new.taxa_falta_id;
  if t.id is null or t.salao_id <> new.salao_id or t.perdoada_em is not null
     or t.cliente_id is distinct from (select cliente_id from comandas where id = new.comanda_id)
     or exists (select 1 from comanda_itens i join comandas c on c.id = i.comanda_id
                where i.taxa_falta_id = t.id and i.id <> new.id and c.status <> 'cancelada') then
    raise exception 'taxa_invalida' using errcode = '22023';
  end if;
  new.preco_centavos := t.valor_centavos;
  return new;
end
$$;
revoke execute on function checar_item_taxa() from public, anon, authenticated;
create trigger checar_item_taxa before insert or update of taxa_falta_id on comanda_itens for each row execute function checar_item_taxa();

create function taxas_pendentes(p_cliente uuid) returns setof taxas_falta
language sql stable security definer set search_path = public, pg_temp as
$$
  select t.* from taxas_falta t
  where t.cliente_id = p_cliente and t.salao_id = meu_salao() and t.perdoada_em is null
    and not exists (select 1 from comanda_itens i join comandas c on c.id = i.comanda_id where i.taxa_falta_id = t.id and c.status <> 'cancelada')
  order by t.falta_em
$$;
revoke all on function taxas_pendentes(uuid) from public, anon;
grant execute on function taxas_pendentes(uuid) to authenticated;

create function perdoar_taxa(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  update taxas_falta set perdoada_em = now(), perdoada_por = auth.uid() where id = p_id and salao_id = meu_salao() and perdoada_em is null;
end
$$;
revoke all on function perdoar_taxa(uuid) from public, anon;
grant execute on function perdoar_taxa(uuid) to authenticated;

-- ───────────── área da cliente ─────────────
create table links_cliente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  token_hash text not null unique,
  expira_em timestamptz not null default now() + interval '180 days',
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on links_cliente (cliente_id);
alter table links_cliente enable row level security;
revoke all on links_cliente from anon, authenticated;

create function link_cliente_interno(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_token text := novo_token();
begin
  insert into links_cliente (salao_id, cliente_id, token_hash) select salao_id, id, hash_token(v_token) from clientes where id = p_cliente;
  if not found then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  return v_token;
end
$$;
revoke all on function link_cliente_interno(uuid) from public, anon, authenticated;
create function criar_link_cliente(p_cliente uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if not exists (select 1 from clientes where id = p_cliente and salao_id = meu_salao()) then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  return link_cliente_interno(p_cliente);
end
$$;
revoke all on function criar_link_cliente(uuid) from public, anon;
grant execute on function criar_link_cliente(uuid) to authenticated;
-- Logo depois de marcar pelo link, a cliente já recebe a área dela.
create function link_cliente_online(p_agendamento uuid) returns text
language sql security definer set search_path = public, pg_temp as
$$ select link_cliente_interno(cliente_id) from agendamentos where id = p_agendamento $$;

create function area_cliente(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  l links_cliente;
  c clientes;
  s saloes;
  v_cash int;
begin
  select * into l from links_cliente where token_hash = hash_token(p_token);
  if l.id is null or l.expira_em < now() then return null; end if;
  select * into c from clientes where id = l.cliente_id;
  select * into s from saloes where id = l.salao_id;
  -- mesma regra de saldo_cashback: créditos válidos menos o usado desde o crédito válido mais antigo
  select greatest(0, v + coalesce((select sum(valor_centavos) from cashback_movimentos where cliente_id = c.id and tipo = 'uso' and criado_em >= desde), 0))::int
  into v_cash
  from (select coalesce(sum(valor_centavos), 0) v, min(criado_em) desde from cashback_movimentos where cliente_id = c.id and tipo = 'credito' and expira_em > now()) x;
  return jsonb_build_object(
    'nome', c.nome, 'salao', s.nome, 'slug', s.slug, 'fuso', s.fuso, 'cashback', v_cash,
    'indicacao_credito', s.indicacao_credito_centavos, 'codigo', case when s.indicacao_credito_centavos > 0 then c.codigo_indicacao end,
    'fidelidade', fidelidade_interna(s.id, c.id),
    'proximos', (select coalesce(jsonb_agg(jsonb_build_object('token', a.token, 'inicio', a.inicio, 'servico', sv.nome, 'profissional', m.nome, 'status', a.status) order by a.inicio), '[]')
                 from agendamentos a join servicos sv on sv.id = a.servico_id join membros m on m.user_id = a.profissional_id
                 where a.cliente_id = c.id and a.inicio > now() and a.status in ('agendado', 'confirmado')),
    'historico', (select coalesce(jsonb_agg(h order by h ->> 'inicio' desc), '[]') from (
                   select jsonb_build_object('inicio', a.inicio, 'servico', sv.nome, 'profissional', m.nome) h
                   from agendamentos a join servicos sv on sv.id = a.servico_id join membros m on m.user_id = a.profissional_id
                   where a.cliente_id = c.id and a.status = 'concluido' order by a.inicio desc limit 10) x),
    'pacotes', (select coalesce(jsonb_agg(jsonb_build_object('nome', pc.nome, 'expira_em', pc.expira_em,
                  'saldos', (select jsonb_agg(jsonb_build_object('servico', sv.nome, 'resta', ps.total - ps.usado)) from pacote_saldos ps join servicos sv on sv.id = ps.servico_id where ps.pacote_cliente_id = pc.id))), '[]')
                from pacotes_cliente pc where pc.cliente_id = c.id and pc.estado = 'ativo' and pc.expira_em > now()),
    'taxas', (select coalesce(sum(t.valor_centavos), 0) from taxas_falta t where t.cliente_id = c.id and t.perdoada_em is null
              and not exists (select 1 from comanda_itens i join comandas cm on cm.id = i.comanda_id where i.taxa_falta_id = t.id and cm.status <> 'cancelada')));
end
$$;
-- O código de indicação nasce quando a área é aberta pela primeira vez (com indicação ligada).
create function area_cliente_preparar(p_token text) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  l links_cliente;
begin
  select * into l from links_cliente where token_hash = hash_token(p_token) and expira_em > now();
  if l.id is not null and exists (select 1 from saloes where id = l.salao_id and indicacao_credito_centavos > 0) then
    perform codigo_indicacao_interno(l.cliente_id);
  end if;
end
$$;
revoke all on function link_cliente_online(uuid), area_cliente(text), area_cliente_preparar(text) from public, anon, authenticated;
grant execute on function link_cliente_online(uuid), area_cliente(text), area_cliente_preparar(text) to service_role;

-- ───────────── fichas de estética ─────────────
alter table saloes add column ficha_areas text[] not null default '{cabelo}'
  check (cardinality(ficha_areas) between 1 and 5 and ficha_areas <@ array['cabelo', 'unhas', 'cilios_sobrancelha', 'pele', 'depilacao']);
grant update (ficha_areas) on saloes to authenticated;
create or replace function ficha_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'slug', s.slug, 'cliente', split_part(c.nome, ' ', 1), 'respondida', f.respondida_em is not null,
    'expirada', f.expira_em < now() and f.respondida_em is null, 'pedir_nascimento', c.nascimento is null, 'areas', s.ficha_areas)
  from fichas_previas f join clientes c on c.id = f.cliente_id join saloes s on s.id = f.salao_id
  where f.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;
-- Com as perguntas de estética a resposta fica maior.
do $$
declare d text;
begin
  select pg_get_functiondef('responder_ficha(text,jsonb)'::regprocedure) into d;
  if position('length(r::text) > 4000' in d) = 0 then raise exception 'responder_ficha() mudou'; end if;
  execute replace(d, 'length(r::text) > 4000', 'length(r::text) > 12000');
end $$;

-- ───────────── IA no WhatsApp ─────────────
alter table saloes add column ia_ativa boolean not null default false;
alter table saloes add column ia_instrucoes text check (length(ia_instrucoes) <= 1500);
grant update (ia_ativa, ia_instrucoes) on saloes to authenticated;

-- ───────────── relatórios com previsão ─────────────
create function relatorios(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
  hoje date; fim_mes timestamptz; ini_mes timestamptz;
begin
  if not pode('painel') then raise exception 'sem permissão para relatórios' using errcode = '42501'; end if;
  select * into s from saloes where id = v_salao;
  de := p_inicio::timestamp at time zone s.fuso;
  ate := (p_fim + 1)::timestamp at time zone s.fuso;
  hoje := (now() at time zone s.fuso)::date;
  ini_mes := date_trunc('month', hoje)::timestamp at time zone s.fuso;
  fim_mes := (date_trunc('month', hoje) + interval '1 month')::timestamp at time zone s.fuso;
  return jsonb_build_object(
    'formas', (select coalesce(jsonb_object_agg(forma, v), '{}') from (
      select p.forma::text forma, sum(p.valor_centavos) v from comanda_pagamentos p join comandas c on c.id = p.comanda_id
      where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate group by 1) x),
    'servicos', (select coalesce(jsonb_agg(x order by (x ->> 'valor')::bigint desc), '[]') from (
      select jsonb_build_object('nome', coalesce(sv.nome, min(i.descricao)), 'qtd', sum(i.quantidade), 'valor', sum(i.preco_centavos * i.quantidade - i.desconto_centavos)) x
      from comanda_itens i join comandas c on c.id = i.comanda_id left join servicos sv on sv.id = i.servico_id
      where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo = 'servico'
      group by i.servico_id, sv.nome) y),
    'produtos', (select coalesce(jsonb_agg(x order by (x ->> 'valor')::bigint desc), '[]') from (
      select jsonb_build_object('nome', coalesce(pr.nome, min(i.descricao)), 'qtd', sum(i.quantidade), 'valor', sum(i.preco_centavos * i.quantidade - i.desconto_centavos),
             'custo', sum(i.quantidade * coalesce(pr.custo_centavos, 0))) x
      from comanda_itens i join comandas c on c.id = i.comanda_id left join produtos pr on pr.id = i.produto_id
      where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo = 'produto'
      group by i.produto_id, pr.nome) y),
    'profissionais', (select coalesce(jsonb_agg(x), '[]') from (
      select jsonb_build_object('nome', m.nome,
        'atendimentos', (select count(*) from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo = 'servico' and i.profissional_id = m.user_id),
        'faturamento', (select coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos), 0) from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.tipo in ('servico', 'produto') and i.profissional_id = m.user_id),
        'clientes', (select count(distinct c.cliente_id) from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and i.profissional_id = m.user_id),
        'faltas', (select count(*) from agendamentos a where a.salao_id = v_salao and a.profissional_id = m.user_id and a.status = 'faltou' and a.inicio >= de and a.inicio < ate),
        'cancelados', (select count(*) from agendamentos a where a.salao_id = v_salao and a.profissional_id = m.user_id and a.status = 'cancelado' and a.inicio >= de and a.inicio < ate)) x
      from membros m where m.salao_id = v_salao and m.ativo and m.papel in ('admin', 'profissional') order by m.nome) y),
    'por_hora', (select coalesce(jsonb_object_agg(h, n), '{}') from (
      select extract(hour from a.inicio at time zone s.fuso)::int h, count(*) n from agendamentos a
      where a.salao_id = v_salao and a.status in ('concluido', 'em_atendimento', 'confirmado', 'agendado') and a.inicio >= de and a.inicio < ate group by 1) x),
    'clientes', (select jsonb_build_object(
        'novas', count(*) filter (where primeira >= de),
        'voltaram', count(*) filter (where primeira < de))
      from (select c.cliente_id, (select min(c2.fechada_em) from comandas c2 where c2.cliente_id = c.cliente_id and c2.status = 'fechada') primeira
            from comandas c where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate and c.cliente_id is not null group by c.cliente_id) x),
    'previsao', jsonb_build_object(
      'realizado_mes', (select coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos), 0) - coalesce((select sum(desconto_centavos) from comandas where salao_id = v_salao and status = 'fechada' and fechada_em >= ini_mes and fechada_em < fim_mes), 0)
                        from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= ini_mes and c.fechada_em < fim_mes and i.tipo <> 'gorjeta'),
      'agendado_mes', (select coalesce(sum(preco_de(a.servico_id, a.profissional_id, a.variacao_id) * (100 - a.promocao_percentual) / 100), 0) from agendamentos a
                       where a.salao_id = v_salao and a.status in ('agendado', 'confirmado') and a.inicio >= now() and a.inicio < fim_mes),
      'semanas', (select coalesce(jsonb_agg(jsonb_build_object('semana', w, 'valor', v, 'horarios', n) order by w), '[]') from (
        select date_trunc('week', a.inicio at time zone s.fuso)::date w, sum(preco_de(a.servico_id, a.profissional_id, a.variacao_id) * (100 - a.promocao_percentual) / 100) v, count(*) n
        from agendamentos a where a.salao_id = v_salao and a.status in ('agendado', 'confirmado') and a.inicio >= now() and a.inicio < now() + interval '35 days' group by 1) x))
  );
end
$$;
revoke all on function relatorios(date, date) from public, anon;
grant execute on function relatorios(date, date) to authenticated;

-- ───────────── unir cadastros: leva também taxas, links, cobranças, indicações e código ─────────────
create or replace function unir_clientes(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  a clientes; b clientes;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção unem cadastros' using errcode = '42501'; end if;
  if p_manter = p_remover then raise exception 'mesmo cadastro' using errcode = '22023'; end if;
  select * into a from clientes where id = p_manter and salao_id = v_salao for update;
  select * into b from clientes where id = p_remover and salao_id = v_salao for update;
  if a.id is null or b.id is null then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  update agendamentos set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', '', true);
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update aceites_politica set cliente_id = a.id where cliente_id = b.id;
  update pacotes_cliente set cliente_id = a.id where cliente_id = b.id;
  update cashback_movimentos set cliente_id = a.id where cliente_id = b.id;
  update lista_espera set cliente_id = a.id where cliente_id = b.id;
  update avisos set cliente_id = a.id where cliente_id = b.id;
  update fichas_previas set cliente_id = a.id where cliente_id = b.id;
  update avaliacoes set cliente_id = a.id where cliente_id = b.id;
  update fila_atendimento set cliente_id = a.id where cliente_id = b.id;
  update termos_assinados set cliente_id = a.id where cliente_id = b.id;
  update taxas_falta set cliente_id = a.id where cliente_id = b.id;
  update links_cliente set cliente_id = a.id where cliente_id = b.id;
  update cobrancas set cliente_id = a.id where cliente_id = b.id;
  update indicacoes_premiadas set indicadora_id = a.id where indicadora_id = b.id;
  delete from indicacoes_premiadas where indicada_id = b.id and exists (select 1 from indicacoes_premiadas where indicada_id = a.id);
  update indicacoes_premiadas set indicada_id = a.id where indicada_id = b.id;
  update vales_presente set comprado_por = a.id where comprado_por = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em),
    vip = a.vip or b.vip, bloqueada = a.bloqueada or b.bloqueada, sempre_sinal = a.sempre_sinal or b.sempre_sinal,
    etiquetas = (select coalesce(array_agg(x), '{}') from (select distinct unnest(a.etiquetas || b.etiquetas) x order by 1 limit 10) e)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;
