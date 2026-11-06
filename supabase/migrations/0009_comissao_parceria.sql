-- Belezando · comissão, vales, fechamento de pagamento e Salão Parceiro (Lei 13.352/2016).
-- A comissão de cada item nasce quando a comanda fecha e fica congelada (mudar a regra não mexe no passado).
-- Base = valor do item − parte do desconto da comanda − (se o salão escolher e o vínculo permitir) taxa do cartão e custo do produto.
-- Para profissional CLT a taxa do cartão e o custo de produto nunca são descontados (convenções coletivas proíbem).

create type vinculo as enum ('socio', 'clt', 'parceiro', 'autonomo');

alter table membros add column vinculo vinculo not null default 'parceiro';
alter table membros add column documento text check (length(documento) <= 20);      -- CPF ou CNPJ (parceiro precisa de CNPJ)
alter table membros add column contrato_inicio date;
alter table membros add column contrato_fim date;
alter table membros add column contrato_homologado_em date;
alter table membros add constraint contrato_ok check (contrato_fim is null or contrato_inicio is null or contrato_fim > contrato_inicio);
grant update (vinculo, documento, contrato_inicio, contrato_fim, contrato_homologado_em) on membros to authenticated;
update membros set vinculo = 'socio' where papel = 'admin';
update membros set vinculo = 'clt' where papel = 'recepcao';  -- a Lei do Salão Parceiro não cobre recepção

alter table saloes add column taxa_debito numeric(5,2) not null default 0 check (taxa_debito between 0 and 20);
alter table saloes add column taxa_credito numeric(5,2) not null default 0 check (taxa_credito between 0 and 20);
alter table saloes add column taxa_credito_parcelado numeric(5,2) not null default 0 check (taxa_credito_parcelado between 0 and 30);
alter table saloes add column taxa_pix numeric(5,2) not null default 0 check (taxa_pix between 0 and 20);
alter table saloes add column comissao_desconta_taxa boolean not null default false;
alter table saloes add column comissao_desconta_custo boolean not null default false;
grant update (taxa_debito, taxa_credito, taxa_credito_parcelado, taxa_pix, comissao_desconta_taxa, comissao_desconta_custo) on saloes to authenticated;

alter table servicos add column custo_produto_centavos int not null default 0 check (custo_produto_centavos between 0 and 10000000);

-- Regra mais específica vence: profissional + serviço > profissional > serviço > padrão do salão.
create table regras_comissao (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  tipo text not null check (tipo in ('servico', 'produto')),
  profissional_id uuid,
  servico_id uuid,
  percentual numeric(5,2) not null check (percentual between 0 and 100),
  assistente_percentual numeric(5,2) not null default 0 check (assistente_percentual between 0 and 100),
  check (tipo = 'servico' or (servico_id is null and assistente_percentual = 0)),
  check (percentual + assistente_percentual <= 100),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id) on delete cascade,
  foreign key (servico_id, salao_id) references servicos (id, salao_id) on delete cascade
);
create unique index regra_unica on regras_comissao (salao_id, tipo, coalesce(profissional_id, '00000000-0000-0000-0000-000000000000'), coalesce(servico_id, '00000000-0000-0000-0000-000000000000'));

create table fechamentos_comissao (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  profissional_id uuid not null,
  periodo_inicio date not null,
  periodo_fim date not null,
  comissoes_centavos int not null,
  gorjetas_centavos int not null,
  vales_centavos int not null,
  pago_centavos int not null,
  forma text check (length(forma) <= 40),
  pago_por uuid default auth.uid(),
  pago_em timestamptz not null default now(),
  unique (id, salao_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id)
);
create index on fechamentos_comissao (salao_id, pago_em desc);

create table comissoes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  comanda_id uuid not null,
  item_id uuid not null,
  profissional_id uuid not null,
  papel text not null check (papel in ('profissional', 'assistente', 'vendedor', 'gorjeta')),
  competencia date not null,                 -- dia em que a comanda fechou (no fuso do salão)
  descricao text not null,
  bruto_centavos int not null,               -- valor do item depois dos descontos
  taxa_centavos int not null default 0,      -- parte da taxa do cartão descontada da base
  custo_centavos int not null default 0,     -- custo de produto descontado da base
  base_centavos int not null,
  percentual numeric(5,2) not null,
  valor_centavos int not null,
  fechamento_id uuid,
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade,
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id),
  foreign key (fechamento_id, salao_id) references fechamentos_comissao (id, salao_id)
);
create index on comissoes (salao_id, profissional_id, competencia);
create index on comissoes (comanda_id);
create index on comissoes (fechamento_id);

create table vales (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  profissional_id uuid not null,
  valor_centavos int not null check (valor_centavos between 1 and 10000000),
  data date not null default current_date,
  motivo text check (length(motivo) <= 200),
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  fechamento_id uuid,
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id),
  foreign key (fechamento_id, salao_id) references fechamentos_comissao (id, salao_id)
);
create index on vales (salao_id, profissional_id, data);

-- ───────────── cálculo ─────────────

create function percentual_comissao(p_salao uuid, p_tipo text, p_prof uuid, p_servico uuid) returns regras_comissao
language sql stable set search_path = public, pg_temp as
$$
  select r.* from regras_comissao r
  where r.salao_id = p_salao and r.tipo = p_tipo
    and (r.profissional_id is null or r.profissional_id = p_prof)
    and (r.servico_id is null or r.servico_id = p_servico)
  order by (r.profissional_id is not null and r.servico_id is not null) desc, (r.profissional_id is not null) desc, (r.servico_id is not null) desc
  limit 1
$$;

create function gerar_comissoes(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  s saloes;
  i comanda_itens;
  r regras_comissao;
  v_total int;           -- o que a cliente pagou (com gorjeta)
  v_itens int;           -- soma dos itens sem gorjeta, antes do desconto da comanda
  v_taxa numeric;        -- taxa total do cartão/pix nesta comanda
  v_bruto int; v_taxa_item int; v_custo int; v_base int;
  v_prof_vinc vinculo;
  v_dia date;
begin
  select * into c from comandas where id = p_comanda;
  select * into s from saloes where id = c.salao_id;
  delete from comissoes where comanda_id = p_comanda and fechamento_id is null;
  v_dia := (coalesce(c.fechada_em, now()) at time zone s.fuso)::date;
  select total into v_total from total_comanda(p_comanda);
  select coalesce(sum(preco_centavos * quantidade - desconto_centavos), 0) into v_itens from comanda_itens where comanda_id = p_comanda and tipo <> 'gorjeta';
  select coalesce(sum(valor_centavos * case forma
           when 'debito' then s.taxa_debito when 'pix' then s.taxa_pix
           when 'credito' then case when parcelas > 1 then s.taxa_credito_parcelado else s.taxa_credito end
           else 0 end / 100.0), 0)
    into v_taxa from comanda_pagamentos where comanda_id = p_comanda;

  for i in select * from comanda_itens where comanda_id = p_comanda order by criado_em loop
    if i.tipo = 'gorjeta' then
      insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, base_centavos, percentual, valor_centavos)
      values (c.salao_id, c.id, i.id, i.profissional_id, 'gorjeta', v_dia, i.descricao, i.preco_centavos, i.preco_centavos, 100, i.preco_centavos);
      continue;
    end if;
    if i.profissional_id is null then continue; end if;
    select vinculo into v_prof_vinc from membros where user_id = i.profissional_id and salao_id = c.salao_id;
    if v_prof_vinc = 'socio' then continue; end if;
    -- parte do desconto da comanda proporcional ao item
    v_bruto := i.preco_centavos * i.quantidade - i.desconto_centavos;
    if v_itens > 0 then v_bruto := v_bruto - round(c.desconto_centavos::numeric * v_bruto / v_itens)::int; end if;
    v_taxa_item := case when s.comissao_desconta_taxa and v_prof_vinc <> 'clt' and v_total > 0 then round(v_taxa * v_bruto / v_total)::int else 0 end;
    v_custo := case when s.comissao_desconta_custo and v_prof_vinc <> 'clt' and i.tipo = 'servico'
                    then i.quantidade * coalesce((select custo_produto_centavos from servicos where id = i.servico_id), 0) else 0 end;
    v_base := greatest(v_bruto - v_taxa_item - v_custo, 0);
    r := percentual_comissao(c.salao_id, i.tipo::text, i.profissional_id, i.servico_id);
    if r.id is null then continue; end if;
    insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
    values (c.salao_id, c.id, i.id, i.profissional_id, case when i.tipo = 'produto' then 'vendedor' else 'profissional' end, v_dia, i.descricao,
            v_bruto, v_taxa_item, v_custo, v_base, r.percentual, round(v_base * r.percentual / 100)::int);
    if i.assistente_id is not null and r.assistente_percentual > 0 then
      insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
      values (c.salao_id, c.id, i.id, i.assistente_id, 'assistente', v_dia, i.descricao || ' (assistente)',
              v_bruto, v_taxa_item, v_custo, v_base, r.assistente_percentual, round(v_base * r.assistente_percentual / 100)::int);
    end if;
  end loop;
end
$$;
revoke all on function gerar_comissoes(uuid) from public, anon, authenticated;
revoke all on function percentual_comissao(uuid, text, uuid, uuid) from public, anon;
grant execute on function percentual_comissao(uuid, text, uuid, uuid) to authenticated;

-- Fechar a comanda passa a gerar as comissões; reabrir apaga as que ainda não foram pagas.
create or replace function fechar_comanda(p_comanda uuid) returns void
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
  perform gerar_comissoes(p_comanda);
end
$$;

create or replace function reabrir_comanda(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador reabre comanda' using errcode = '42501'; end if;
  if not exists (select 1 from comandas c join caixas x on x.id = c.caixa_id
                 where c.id = p_comanda and c.salao_id = meu_salao() and c.status = 'fechada' and x.fechado_em is null) then
    raise exception 'comanda_nao_reabre' using errcode = '55000';
  end if;
  if exists (select 1 from comissoes where comanda_id = p_comanda and fechamento_id is not null) then
    raise exception 'comissao_ja_paga' using errcode = '55000';
  end if;
  delete from comissoes where comanda_id = p_comanda;
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set status = 'aberta', caixa_id = null, fechada_em = null, fechada_por = null where id = p_comanda;
  perform set_config('belezando.reabrindo', '', true);
end
$$;

-- Comanda cancelada depois de fechada não existe (só aberta vira cancelada), mas por garantia: cancelar limpa comissões não pagas.

-- ───────────── pagamento ao profissional ─────────────

-- Junta comissões e gorjetas do período ainda não pagas, desconta os vales e registra o pagamento.
create function pagar_profissional(p_prof uuid, p_inicio date, p_fim date, p_forma text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_com int; v_gor int; v_val int;
  v_id uuid;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador registra pagamento' using errcode = '42501'; end if;
  if p_fim < p_inicio then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from membros where user_id = p_prof and salao_id = v_salao) then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
  select coalesce(sum(valor_centavos) filter (where papel <> 'gorjeta'), 0), coalesce(sum(valor_centavos) filter (where papel = 'gorjeta'), 0)
    into v_com, v_gor from comissoes
  where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  select coalesce(sum(valor_centavos), 0) into v_val from vales
  where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and data <= p_fim;
  if v_com + v_gor = 0 and v_val = 0 then raise exception 'nada_a_pagar' using errcode = '22023'; end if;
  insert into fechamentos_comissao (salao_id, profissional_id, periodo_inicio, periodo_fim, comissoes_centavos, gorjetas_centavos, vales_centavos, pago_centavos, forma)
  values (v_salao, p_prof, p_inicio, p_fim, v_com, v_gor, v_val, v_com + v_gor - v_val, left(p_forma, 40)) returning id into v_id;
  update comissoes set fechamento_id = v_id where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  update vales set fechamento_id = v_id where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and data <= p_fim;
  return v_id;
end
$$;

-- Comprovação da parceria (Lei 13.352): por parceiro, quanto entrou de serviço, quanto ficou com o salão (cota-parte) e quanto foi repassado.
create function relatorio_parceria(p_inicio date, p_fim date) returns table (
  profissional_id uuid, nome text, documento text, contrato_inicio date, contrato_fim date, contrato_homologado_em date,
  servicos_centavos bigint, cota_profissional_centavos bigint, cota_salao_centavos bigint, gorjetas_centavos bigint, repassado_centavos bigint
)
language sql stable security definer set search_path = public, pg_temp as
$$
  select m.user_id, m.nome, m.documento, m.contrato_inicio, m.contrato_fim, m.contrato_homologado_em,
    coalesce(sum(x.bruto_centavos) filter (where x.papel = 'profissional'), 0),
    coalesce(sum(x.valor_centavos) filter (where x.papel in ('profissional', 'assistente', 'vendedor')), 0),
    coalesce(sum(x.bruto_centavos - x.valor_centavos) filter (where x.papel = 'profissional'), 0),
    coalesce(sum(x.valor_centavos) filter (where x.papel = 'gorjeta'), 0),
    (select coalesce(sum(f.pago_centavos), 0) from fechamentos_comissao f
      where f.profissional_id = m.user_id and f.salao_id = m.salao_id and (f.pago_em at time zone s.fuso)::date between p_inicio and p_fim)
  from membros m join saloes s on s.id = m.salao_id
  left join comissoes x on x.profissional_id = m.user_id and x.salao_id = m.salao_id and x.competencia between p_inicio and p_fim
  where m.salao_id = meu_salao() and meu_papel() = 'admin' and m.vinculo = 'parceiro' and m.papel <> 'recepcao'
  group by m.user_id, m.nome, m.documento, m.contrato_inicio, m.contrato_fim, m.contrato_homologado_em, m.salao_id, s.fuso
  order by m.nome
$$;

revoke all on function pagar_profissional(uuid, date, date, text), relatorio_parceria(date, date) from public, anon;
grant execute on function pagar_profissional(uuid, date, date, text), relatorio_parceria(date, date) to authenticated;

-- ───────────── RLS ─────────────

alter table regras_comissao enable row level security;
alter table comissoes enable row level security;
alter table vales enable row level security;
alter table fechamentos_comissao enable row level security;

-- Regras são transparentes para a equipe; só o administrador muda.
create policy regras_ler on regras_comissao for select to authenticated using (salao_id = meu_salao());
create policy regras_escrever on regras_comissao for all to authenticated
  using (salao_id = meu_salao() and meu_papel() = 'admin') with check (salao_id = meu_salao() and meu_papel() = 'admin');
-- Cada profissional vê só o próprio dinheiro; o administrador vê tudo.
create policy comissoes_ler on comissoes for select to authenticated
  using (salao_id = meu_salao() and (meu_papel() = 'admin' or profissional_id = auth.uid()));
create policy fech_ler on fechamentos_comissao for select to authenticated
  using (salao_id = meu_salao() and (meu_papel() = 'admin' or profissional_id = auth.uid()));
create policy vales_ler on vales for select to authenticated
  using (salao_id = meu_salao() and (meu_papel() in ('admin', 'recepcao') or profissional_id = auth.uid()));
create policy vales_criar on vales for insert to authenticated with check (salao_id = meu_salao() and meu_papel() in ('admin', 'recepcao'));
create policy vales_apagar on vales for delete to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin' and fechamento_id is null);

revoke all on regras_comissao, comissoes, vales, fechamentos_comissao from anon, authenticated;
grant select, insert, update, delete on regras_comissao to authenticated;
grant select on comissoes, fechamentos_comissao to authenticated;
grant select, delete on vales to authenticated;
grant insert (profissional_id, valor_centavos, data, motivo) on vales to authenticated;
grant update (custo_produto_centavos) on servicos to authenticated;

create trigger aud_regras after insert or update or delete on regras_comissao for each row execute function auditar();
create trigger aud_vales after insert or delete on vales for each row execute function auditar();
create trigger aud_fechamentos after insert on fechamentos_comissao for each row execute function auditar();

-- Salão novo nasce com 40% em serviço e 10% em produto (o administrador ajusta em Comissões).
insert into regras_comissao (salao_id, tipo, percentual) select id, 'servico', 40 from saloes;
insert into regras_comissao (salao_id, tipo, percentual) select id, 'produto', 10 from saloes;
create function regras_iniciais() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  insert into regras_comissao (salao_id, tipo, percentual) values (new.id, 'servico', 40), (new.id, 'produto', 10);
  return new;
end
$$;
revoke all on function regras_iniciais() from public, anon, authenticated;
create trigger regras_salao after insert on saloes for each row execute function regras_iniciais();

-- Quem cria o salão é sócio (não comissionado). Recepção não pode ser parceira: entra como CLT.
create function socio_fundador() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.papel = 'admin' and not exists (select 1 from membros where salao_id = new.salao_id) then new.vinculo := 'socio'; end if;
  if new.papel = 'recepcao' and new.vinculo = 'parceiro' then new.vinculo := 'clt'; end if;
  return new;
end
$$;
revoke all on function socio_fundador() from public, anon, authenticated;
create trigger socio_fundador before insert on membros for each row execute function socio_fundador();
