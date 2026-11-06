-- Belezando · comanda e caixa.
-- Valores em centavos (int). A comanda junta serviços, produtos e gorjetas de uma cliente; só fecha com o caixa aberto
-- e com os pagamentos somando exatamente o total. Gorjeta não é receita do salão nem entra em comissão.

alter table servicos add column preco_centavos int not null default 0 check (preco_centavos between 0 and 10000000);

create table produtos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 120),
  preco_centavos int not null default 0 check (preco_centavos between 0 and 10000000),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (id, salao_id)
);
create index on produtos (salao_id, nome);

create type status_comanda as enum ('aberta', 'fechada', 'cancelada');
create type tipo_item as enum ('servico', 'produto', 'gorjeta');
create type forma_pagamento as enum ('dinheiro', 'pix', 'debito', 'credito', 'pacote', 'outro');

create table caixas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  aberto_por uuid default auth.uid(),
  aberto_em timestamptz not null default now(),
  troco_inicial_centavos int not null default 0 check (troco_inicial_centavos between 0 and 10000000),
  fechado_por uuid,
  fechado_em timestamptz,
  contado jsonb,          -- {"dinheiro": 12345, "pix": ...} informado no fechamento
  esperado jsonb,         -- o que o sistema calculou no fechamento
  observacao text check (length(observacao) <= 500),
  unique (id, salao_id)
);
-- um caixa aberto por salão
create unique index caixa_aberto_unico on caixas (salao_id) where fechado_em is null;

create table caixa_movimentos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  caixa_id uuid not null,
  tipo text not null check (tipo in ('sangria', 'suprimento')),
  valor_centavos int not null check (valor_centavos between 1 and 10000000),
  motivo text check (length(motivo) <= 200),
  feito_por uuid default auth.uid(),
  em timestamptz not null default now(),
  foreign key (caixa_id, salao_id) references caixas (id, salao_id)
);
create index on caixa_movimentos (caixa_id);

create table comandas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  numero bigint generated always as identity,
  cliente_id uuid,
  status status_comanda not null default 'aberta',
  desconto_centavos int not null default 0 check (desconto_centavos between 0 and 10000000),
  caixa_id uuid,
  aberta_por uuid default auth.uid(),
  aberta_em timestamptz not null default now(),
  fechada_por uuid,
  fechada_em timestamptz,
  observacao text check (length(observacao) <= 500),
  unique (id, salao_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id),
  foreign key (caixa_id, salao_id) references caixas (id, salao_id),
  check ((status = 'fechada') = (fechada_em is not null and caixa_id is not null) or status = 'cancelada')
);
create index on comandas (salao_id, status, aberta_em desc);
create index on comandas (cliente_id);
create index on comandas (caixa_id);

create table comanda_itens (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  comanda_id uuid not null,
  tipo tipo_item not null,
  servico_id uuid,
  produto_id uuid,
  agendamento_id uuid,
  descricao text not null check (length(descricao) between 1 and 160),
  profissional_id uuid,            -- quem fez o serviço, recebe a gorjeta ou vendeu o produto
  assistente_id uuid,              -- quem ajudou (lavou, aplicou): divide a comissão
  quantidade int not null default 1 check (quantidade between 1 and 999),
  preco_centavos int not null check (preco_centavos between 0 and 10000000),   -- unitário
  desconto_centavos int not null default 0 check (desconto_centavos >= 0),
  criado_em timestamptz not null default now(),
  check (desconto_centavos <= preco_centavos * quantidade),
  check (tipo <> 'servico' or (servico_id is not null and profissional_id is not null)),
  check (tipo <> 'produto' or produto_id is not null),
  check (tipo <> 'gorjeta' or (profissional_id is not null and desconto_centavos = 0 and quantidade = 1)),
  check (assistente_id is null or (tipo = 'servico' and assistente_id <> profissional_id)),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade,
  foreign key (servico_id, salao_id) references servicos (id, salao_id),
  foreign key (produto_id, salao_id) references produtos (id, salao_id),
  foreign key (agendamento_id, salao_id) references agendamentos (id, salao_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id),
  foreign key (assistente_id, salao_id) references membros (user_id, salao_id)
);
create index on comanda_itens (comanda_id);
create index on comanda_itens (agendamento_id);
create index on comanda_itens (profissional_id, salao_id);

create table comanda_pagamentos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  comanda_id uuid not null,
  forma forma_pagamento not null,
  valor_centavos int not null check (valor_centavos between 1 and 10000000),
  parcelas int not null default 1 check (parcelas between 1 and 24),
  criado_em timestamptz not null default now(),
  check (parcelas = 1 or forma = 'credito'),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade
);
create index on comanda_pagamentos (comanda_id);

-- ───────────── totais ─────────────

-- Total que a cliente paga (serviços + produtos + gorjetas − descontos) e a receita do salão (sem gorjeta).
create function total_comanda(p_comanda uuid) returns table (total int, receita int, gorjetas int, pago int)
language sql stable set search_path = public, pg_temp as
$$
  select
    (coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos), 0) - c.desconto_centavos)::int,
    (coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo <> 'gorjeta'), 0) - c.desconto_centavos)::int,
    coalesce(sum(i.preco_centavos) filter (where i.tipo = 'gorjeta'), 0)::int,
    (select coalesce(sum(valor_centavos), 0)::int from comanda_pagamentos p where p.comanda_id = c.id)
  from comandas c left join comanda_itens i on i.comanda_id = c.id
  where c.id = p_comanda
  group by c.id, c.desconto_centavos
$$;

-- ───────────── travas ─────────────

-- Itens e pagamentos só mudam com a comanda aberta.
create function trava_comanda_aberta() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
declare
  v_id uuid := coalesce(new.comanda_id, old.comanda_id);
begin
  if (select status from comandas where id = v_id) <> 'aberta' then
    raise exception 'comanda_fechada' using errcode = '55000';
  end if;
  return coalesce(new, old);
end
$$;
create trigger trava_itens before insert or update or delete on comanda_itens for each row execute function trava_comanda_aberta();
create trigger trava_pagamentos before insert or update or delete on comanda_pagamentos for each row execute function trava_comanda_aberta();

-- Comanda fechada ou cancelada não volta pela API (só pela função reabrir_comanda, do administrador).
create function trava_comanda() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if old.status <> 'aberta' and current_setting('belezando.reabrindo', true) is distinct from 'sim' then
    raise exception 'comanda_fechada' using errcode = '55000';
  end if;
  if new.status = 'fechada' and old.status = 'aberta' and current_setting('belezando.fechando', true) is distinct from 'sim' then
    raise exception 'use fechar_comanda' using errcode = '42501';
  end if;
  if new.status = 'cancelada' and old.status = 'aberta' and auth.uid() is not null and meu_papel() <> 'admin'
     and exists (select 1 from comanda_pagamentos where comanda_id = old.id) then
    raise exception 'só o administrador cancela comanda com pagamento' using errcode = '42501';
  end if;
  return new;
end
$$;
create trigger trava_comanda before update on comandas for each row execute function trava_comanda();

create function trava_caixa() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if old.fechado_em is not null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  return new;
end
$$;
create trigger trava_caixa before update on caixas for each row execute function trava_caixa();

create function trava_movimento() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if (select fechado_em from caixas where id = new.caixa_id) is not null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  return new;
end
$$;
create trigger trava_movimento before insert on caixa_movimentos for each row execute function trava_movimento();

-- ───────────── ações ─────────────

-- Fecha a comanda no caixa aberto. Pagamentos precisam somar o total. Os horários ligados viram "concluído".
create function fechar_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  t record;
  v_caixa uuid;
begin
  select * into c from comandas where id = p_comanda and salao_id = meu_salao() for update;
  if c.id is null then raise exception 'comanda não encontrada' using errcode = 'P0002'; end if;
  if c.status <> 'aberta' then raise exception 'comanda_fechada' using errcode = '55000'; end if;
  select id into v_caixa from caixas where salao_id = c.salao_id and fechado_em is null;
  if v_caixa is null then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  select * into t from total_comanda(p_comanda);
  if not exists (select 1 from comanda_itens where comanda_id = p_comanda) then raise exception 'comanda_vazia' using errcode = '22023'; end if;
  if t.total < 0 then raise exception 'desconto_maior_que_total' using errcode = '22023'; end if;
  if t.pago <> t.total then raise exception 'pagamento_diferente' using errcode = '22023'; end if;
  perform set_config('belezando.fechando', 'sim', true);
  update comandas set status = 'fechada', caixa_id = v_caixa, fechada_em = now(), fechada_por = auth.uid() where id = p_comanda;
  perform set_config('belezando.fechando', '', true);
  update agendamentos set status = 'concluido'
  where id in (select agendamento_id from comanda_itens where comanda_id = p_comanda and agendamento_id is not null)
    and status not in ('cancelado', 'faltou', 'concluido');
end
$$;

-- O administrador reabre uma comanda fechada por engano (fica na auditoria). Só enquanto o caixa dela está aberto.
create function reabrir_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador reabre comanda' using errcode = '42501'; end if;
  if not exists (select 1 from comandas c join caixas x on x.id = c.caixa_id
                 where c.id = p_comanda and c.salao_id = meu_salao() and c.status = 'fechada' and x.fechado_em is null) then
    raise exception 'comanda_nao_reabre' using errcode = '55000';
  end if;
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set status = 'aberta', caixa_id = null, fechada_em = null, fechada_por = null where id = p_comanda;
  perform set_config('belezando.reabrindo', '', true);
end
$$;

-- Resumo do caixa: entradas por forma de pagamento, gorjetas, sangrias, suprimentos e o dinheiro esperado na gaveta.
create function resumo_caixa(p_caixa uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  with cx as (select * from caixas where id = p_caixa and salao_id = meu_salao()),
  pags as (
    select p.forma, sum(p.valor_centavos)::int v from comanda_pagamentos p join comandas c on c.id = p.comanda_id
    where c.caixa_id = p_caixa and c.status = 'fechada' group by p.forma
  ),
  mov as (select tipo, sum(valor_centavos)::int v from caixa_movimentos where caixa_id = p_caixa group by tipo),
  com as (select count(*)::int n, coalesce(sum((select receita from total_comanda(c.id))), 0)::int receita,
                 coalesce(sum((select gorjetas from total_comanda(c.id))), 0)::int gorjetas
          from comandas c where c.caixa_id = p_caixa and c.status = 'fechada')
  select jsonb_build_object(
    'formas', coalesce((select jsonb_object_agg(forma, v) from pags), '{}'::jsonb),
    'comandas', com.n, 'receita', com.receita, 'gorjetas', com.gorjetas,
    'troco_inicial', cx.troco_inicial_centavos,
    'sangrias', coalesce((select v from mov where tipo = 'sangria'), 0),
    'suprimentos', coalesce((select v from mov where tipo = 'suprimento'), 0),
    'dinheiro_esperado', cx.troco_inicial_centavos + coalesce((select v from pags where forma = 'dinheiro'), 0)
       + coalesce((select v from mov where tipo = 'suprimento'), 0) - coalesce((select v from mov where tipo = 'sangria'), 0)
  ) from cx, com
$$;

-- Fecha o caixa guardando o que foi contado e o que era esperado. Comandas abertas continuam abertas para o próximo caixa.
create function fechar_caixa(p_caixa uuid, p_contado jsonb, p_obs text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v jsonb;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção fecham o caixa' using errcode = '42501'; end if;
  if not exists (select 1 from caixas where id = p_caixa and salao_id = meu_salao() and fechado_em is null) then
    raise exception 'caixa_fechado' using errcode = '55000';
  end if;
  v := resumo_caixa(p_caixa);
  update caixas set fechado_em = now(), fechado_por = auth.uid(), contado = p_contado, esperado = v, observacao = left(p_obs, 500)
  where id = p_caixa;
  return v;
end
$$;

revoke all on function total_comanda(uuid), fechar_comanda(uuid), reabrir_comanda(uuid), resumo_caixa(uuid), fechar_caixa(uuid, jsonb, text) from public, anon;
grant execute on function total_comanda(uuid), fechar_comanda(uuid), reabrir_comanda(uuid), resumo_caixa(uuid), fechar_caixa(uuid, jsonb, text) to authenticated;
revoke execute on function trava_comanda_aberta(), trava_comanda(), trava_caixa(), trava_movimento() from public, anon, authenticated;

-- ───────────── RLS e permissões ─────────────

alter table produtos enable row level security;
alter table caixas enable row level security;
alter table caixa_movimentos enable row level security;
alter table comandas enable row level security;
alter table comanda_itens enable row level security;
alter table comanda_pagamentos enable row level security;

create policy produtos_ler on produtos for select to authenticated using (salao_id = meu_salao());
create policy produtos_escrever on produtos for all to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');

create policy caixas_ler on caixas for select to authenticated using (salao_id = meu_salao());
create policy caixas_abrir on caixas for insert to authenticated with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
create policy mov_ler on caixa_movimentos for select to authenticated using (salao_id = meu_salao());
create policy mov_criar on caixa_movimentos for insert to authenticated with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));

create policy comandas_ler on comandas for select to authenticated using (salao_id = meu_salao());
create policy comandas_criar on comandas for insert to authenticated with check (salao_id = meu_salao());
create policy comandas_editar on comandas for update to authenticated using (salao_id = meu_salao()) with check (salao_id = meu_salao());
create policy itens_ler on comanda_itens for select to authenticated using (salao_id = meu_salao());
create policy itens_escrever on comanda_itens for all to authenticated using (salao_id = meu_salao()) with check (salao_id = meu_salao());
create policy pags_ler on comanda_pagamentos for select to authenticated using (salao_id = meu_salao());
create policy pags_escrever on comanda_pagamentos for all to authenticated using (salao_id = meu_salao()) with check (salao_id = meu_salao());

revoke all on produtos, caixas, caixa_movimentos, comandas, comanda_itens, comanda_pagamentos from anon, authenticated;
grant select, insert, update, delete on produtos to authenticated;
grant select on caixas to authenticated;
grant insert (troco_inicial_centavos) on caixas to authenticated;
grant select on caixa_movimentos to authenticated;
grant insert (caixa_id, tipo, valor_centavos, motivo) on caixa_movimentos to authenticated;
grant select on comandas to authenticated;
grant insert (cliente_id, observacao) on comandas to authenticated;
grant update (cliente_id, desconto_centavos, observacao, status) on comandas to authenticated;
grant select, delete on comanda_itens, comanda_pagamentos to authenticated;
grant insert (comanda_id, tipo, servico_id, produto_id, agendamento_id, descricao, profissional_id, assistente_id, quantidade, preco_centavos, desconto_centavos) on comanda_itens to authenticated;
grant update (profissional_id, assistente_id, quantidade, preco_centavos, desconto_centavos) on comanda_itens to authenticated;
grant insert (comanda_id, forma, valor_centavos, parcelas) on comanda_pagamentos to authenticated;
grant update (preco_centavos) on servicos to authenticated;

create trigger aud_comandas after insert or update or delete on comandas for each row execute function auditar();
create trigger aud_comanda_itens after insert or update or delete on comanda_itens for each row execute function auditar();
create trigger aud_comanda_pagamentos after insert or update or delete on comanda_pagamentos for each row execute function auditar();
create trigger aud_caixas after insert or update on caixas for each row execute function auditar();
create trigger aud_caixa_movimentos after insert on caixa_movimentos for each row execute function auditar();
create trigger aud_produtos after insert or update or delete on produtos for each row execute function auditar();
