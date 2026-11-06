-- Belezando · estoque: produto de revenda (sai na venda) e de uso interno (sai sozinho pelo consumo de cada serviço).
-- O saldo fica na unidade do produto (unidade, grama ou mililitro). Entrada é por embalagem: 2 tubos de 60 g = +120 g.

alter table produtos add column tipo text not null default 'revenda' check (tipo in ('revenda', 'uso', 'ambos'));
alter table produtos add column unidade text not null default 'un' check (unidade in ('un', 'g', 'ml'));
alter table produtos add column conteudo numeric(10,2) not null default 1 check (conteudo > 0);       -- quanto tem numa embalagem
alter table produtos add column custo_centavos int not null default 0 check (custo_centavos between 0 and 10000000);   -- custo da embalagem
alter table produtos add column estoque numeric(12,2) not null default 0;
alter table produtos add column estoque_minimo numeric(12,2) not null default 0 check (estoque_minimo >= 0);
-- o saldo só muda por movimento
revoke update on produtos from authenticated;
grant update (nome, preco_centavos, ativo, tipo, unidade, conteudo, custo_centavos, estoque_minimo) on produtos to authenticated;

-- Quanto de cada produto um serviço consome (ex.: Coloração usa 60 g de tinta e 90 ml de oxidante).
create table servico_insumos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  servico_id uuid not null,
  produto_id uuid not null,
  quantidade numeric(10,2) not null check (quantidade > 0),
  unique (servico_id, produto_id),
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade,
  foreign key (produto_id, salao_id) references produtos (id, salao_id) on delete cascade
);

create table movimentos_estoque (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  produto_id uuid not null,
  tipo text not null check (tipo in ('entrada', 'venda', 'uso', 'ajuste', 'perda', 'estorno')),
  quantidade numeric(12,2) not null check (quantidade <> 0),     -- positivo entra, negativo sai
  custo_centavos int check (custo_centavos >= 0),
  comanda_id uuid,
  motivo text check (length(motivo) <= 200),
  feito_por uuid default auth.uid(),
  em timestamptz not null default now(),
  foreign key (produto_id, salao_id) references produtos (id, salao_id) on delete cascade,
  foreign key (comanda_id, salao_id) references comandas (id, salao_id)
);
create index on movimentos_estoque (produto_id, em desc);
create index on movimentos_estoque (comanda_id);

create function aplicar_movimento() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update produtos set estoque = estoque + new.quantidade where id = new.produto_id;
  return new;
end
$$;
create trigger aplica_movimento after insert on movimentos_estoque for each row execute function aplicar_movimento();

-- Comanda fechada: sai o que foi vendido e o que os serviços consumiram. Reaberta: tudo volta (estorno).
create function baixar_estoque_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, comanda_id, feito_por)
    select i.salao_id, i.produto_id, 'venda', -(i.quantidade * case p.unidade when 'un' then 1 else p.conteudo end), new.id, auth.uid()
    from comanda_itens i join produtos p on p.id = i.produto_id
    where i.comanda_id = new.id and i.tipo = 'produto';
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, comanda_id, feito_por)
    select i.salao_id, si.produto_id, 'uso', -sum(si.quantidade * i.quantidade), new.id, auth.uid()
    from comanda_itens i join servico_insumos si on si.servico_id = i.servico_id
    where i.comanda_id = new.id and i.tipo = 'servico'
    group by i.salao_id, si.produto_id;
  elsif new.status = 'aberta' and old.status = 'fechada' then
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, comanda_id, motivo, feito_por)
    select salao_id, produto_id, 'estorno', -sum(quantidade), new.id, 'comanda reaberta', auth.uid()
    from movimentos_estoque where comanda_id = new.id group by salao_id, produto_id having sum(quantidade) <> 0;
  end if;
  return new;
end
$$;
create trigger estoque_comanda after update of status on comandas for each row execute function baixar_estoque_comanda();
revoke execute on function aplicar_movimento(), baixar_estoque_comanda() from public, anon, authenticated;

-- Contagem física: o administrador ou a recepção informa quanto tem de verdade e o sistema lança a diferença.
create function ajustar_estoque(p_produto uuid, p_contado numeric, p_motivo text) returns numeric
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_atual numeric;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção ajustam estoque' using errcode = '42501'; end if;
  if p_contado < 0 then raise exception 'contagem negativa' using errcode = '22023'; end if;
  select estoque into v_atual from produtos where id = p_produto and salao_id = meu_salao() for update;
  if v_atual is null then raise exception 'produto não encontrado' using errcode = 'P0002'; end if;
  if p_contado <> v_atual then
    insert into movimentos_estoque (salao_id, produto_id, tipo, quantidade, motivo) values (meu_salao(), p_produto, 'ajuste', p_contado - v_atual, left(coalesce(p_motivo, 'contagem'), 200));
  end if;
  return p_contado - v_atual;
end
$$;
revoke all on function ajustar_estoque(uuid, numeric, text) from public, anon;
grant execute on function ajustar_estoque(uuid, numeric, text) to authenticated;

alter table servico_insumos enable row level security;
alter table movimentos_estoque enable row level security;
create policy insumos_ler on servico_insumos for select to authenticated using (salao_id = meu_salao());
create policy insumos_escrever on servico_insumos for all to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');
create policy mov_estoque_ler on movimentos_estoque for select to authenticated using (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
-- pela API só entra mercadoria e registra perda; venda, uso, estorno e ajuste vêm do sistema
create policy mov_estoque_criar on movimentos_estoque for insert to authenticated
  with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao')
              and ((tipo = 'entrada' and quantidade > 0) or (tipo = 'perda' and quantidade < 0)) and comanda_id is null);
revoke all on servico_insumos, movimentos_estoque from anon, authenticated;
grant select, insert, update, delete on servico_insumos to authenticated;
grant select on movimentos_estoque to authenticated;
grant insert (produto_id, tipo, quantidade, custo_centavos, motivo) on movimentos_estoque to authenticated;
create trigger aud_insumos after insert or update or delete on servico_insumos for each row execute function auditar();

-- Produto comprado para uso interno não precisa de preço de venda.
alter table produtos drop constraint if exists produtos_preco_centavos_check;
alter table produtos add constraint produtos_preco_centavos_check check (preco_centavos between 0 and 10000000);
