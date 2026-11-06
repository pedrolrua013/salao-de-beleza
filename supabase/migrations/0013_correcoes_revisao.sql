-- Belezando · correções da revisão de 31/10/2026 (comanda, comissão, sinal, união de cadastros e link público).

-- ───────────── 1) Unir cadastros com comanda fechada e sem perder o aceite da política ─────────────
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
  -- comandas fechadas também mudam de dono (só o cliente; valores continuam travados)
  perform set_config('belezando.reabrindo', 'sim', true);
  update comandas set cliente_id = a.id where cliente_id = b.id;
  perform set_config('belezando.reabrindo', '', true);
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
  update aceites_politica set cliente_id = a.id where cliente_id = b.id;
  update clientes set indicado_por = a.id where indicado_por = b.id and id <> a.id;
  update clientes set
    telefone = coalesce(a.telefone, b.telefone), email = coalesce(a.email, b.email), nascimento = coalesce(a.nascimento, b.nascimento),
    observacoes = nullif(concat_ws(E'\n', a.observacoes, b.observacoes), ''),
    alergias = nullif(concat_ws('; ', a.alergias, b.alergias), ''),
    preferencias = coalesce(a.preferencias, b.preferencias), tipo_cabelo = coalesce(a.tipo_cabelo, b.tipo_cabelo),
    origem = coalesce(a.origem, b.origem), indicado_por = coalesce(a.indicado_por, nullif(b.indicado_por, a.id)),
    consentimento_em = coalesce(a.consentimento_em, b.consentimento_em),
    consentimento_imagem_em = coalesce(a.consentimento_imagem_em, b.consentimento_imagem_em),
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;

-- ───────────── 2) Sinal: crédito da cliente usado em qualquer comanda dela, e devolvido se o pagamento sair ─────────────
alter table sinais drop constraint sinais_status_check;
alter table sinais add constraint sinais_status_check check (status in ('pendente', 'pago', 'expirado', 'cancelado', 'credito', 'devolvido', 'usado'));
alter table sinais add column comanda_pagamento_id uuid;
create index on sinais (comanda_pagamento_id);

drop function usar_sinal(uuid);

-- Lança na comanda o sinal pago (ou crédito) mais antigo da cliente dela. O sinal só vira "usado" junto com o pagamento.
create function usar_credito_sinal(p_comanda uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  x sinais;
  v_pag uuid;
begin
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
revoke all on function usar_credito_sinal(uuid) from public, anon;
grant execute on function usar_credito_sinal(uuid) to authenticated;

-- Pagamento de sinal removido da comanda, ou comanda cancelada: o sinal volta a ser crédito da cliente.
create function devolver_sinal_pagamento() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update sinais set status = 'credito', comanda_pagamento_id = null where comanda_pagamento_id = old.id;
  return old;
end
$$;
create trigger devolve_sinal after delete on comanda_pagamentos for each row when (old.forma = 'sinal') execute function devolver_sinal_pagamento();

create function devolver_sinal_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update sinais set status = 'credito', comanda_pagamento_id = null
  where comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  return new;
end
$$;
create trigger devolve_sinal_cancelada after update of status on comandas for each row
  when (new.status = 'cancelada' and old.status is distinct from 'cancelada') execute function devolver_sinal_comanda();
revoke execute on function devolver_sinal_pagamento(), devolver_sinal_comanda() from public, anon, authenticated;

-- ───────────── 3) Comissão do assistente independente do profissional principal ─────────────
create or replace function gerar_comissoes(p_comanda uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c comandas;
  s saloes;
  i comanda_itens;
  r regras_comissao;
  v_total int; v_itens int; v_taxa numeric;
  v_bruto int; v_dia date;
  v_vinc vinculo; v_vinc_assist vinculo;

  -- base de um comissionado: desconta taxa e custo só se o salão escolheu e o vínculo permite (CLT nunca)
  v_taxa_item int; v_custo int; v_base int;
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
    v_bruto := i.preco_centavos * i.quantidade - i.desconto_centavos;
    if v_itens > 0 then v_bruto := v_bruto - round(c.desconto_centavos::numeric * v_bruto / v_itens)::int; end if;
    r := percentual_comissao(c.salao_id, i.tipo::text, i.profissional_id, i.servico_id);
    if r.id is null then continue; end if;

    if i.profissional_id is not null then
      select vinculo into v_vinc from membros where user_id = i.profissional_id and salao_id = c.salao_id;
      if v_vinc <> 'socio' then
        v_taxa_item := case when s.comissao_desconta_taxa and v_vinc <> 'clt' and v_total > 0 then round(v_taxa * v_bruto / v_total)::int else 0 end;
        v_custo := case when s.comissao_desconta_custo and v_vinc <> 'clt' and i.tipo = 'servico'
                        then i.quantidade * coalesce((select custo_produto_centavos from servicos where id = i.servico_id), 0) else 0 end;
        v_base := greatest(v_bruto - v_taxa_item - v_custo, 0);
        insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
        values (c.salao_id, c.id, i.id, i.profissional_id, case when i.tipo = 'produto' then 'vendedor' else 'profissional' end, v_dia, i.descricao,
                v_bruto, v_taxa_item, v_custo, v_base, r.percentual, round(v_base * r.percentual / 100)::int);
      end if;
    end if;

    if i.assistente_id is not null and r.assistente_percentual > 0 then
      select vinculo into v_vinc_assist from membros where user_id = i.assistente_id and salao_id = c.salao_id;
      if v_vinc_assist <> 'socio' then
        v_taxa_item := case when s.comissao_desconta_taxa and v_vinc_assist <> 'clt' and v_total > 0 then round(v_taxa * v_bruto / v_total)::int else 0 end;
        v_custo := case when s.comissao_desconta_custo and v_vinc_assist <> 'clt'
                        then i.quantidade * coalesce((select custo_produto_centavos from servicos where id = i.servico_id), 0) else 0 end;
        v_base := greatest(v_bruto - v_taxa_item - v_custo, 0);
        insert into comissoes (salao_id, comanda_id, item_id, profissional_id, papel, competencia, descricao, bruto_centavos, taxa_centavos, custo_centavos, base_centavos, percentual, valor_centavos)
        values (c.salao_id, c.id, i.id, i.assistente_id, 'assistente', v_dia, i.descricao || ' (assistente)',
                v_bruto, v_taxa_item, v_custo, v_base, r.assistente_percentual, round(v_base * r.assistente_percentual / 100)::int);
      end if;
    end if;
  end loop;
end
$$;

-- ───────────── 4) Vale maior que o período fica em aberto (não some) ─────────────
create or replace function pagar_profissional(p_prof uuid, p_inicio date, p_fim date, p_forma text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_com int; v_gor int; v_val int := 0;
  v_id uuid;
  x vales;
  v_quitar uuid[] := '{}';
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador registra pagamento' using errcode = '42501'; end if;
  if p_fim < p_inicio then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  if not exists (select 1 from membros where user_id = p_prof and salao_id = v_salao) then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
  select coalesce(sum(valor_centavos) filter (where papel <> 'gorjeta'), 0), coalesce(sum(valor_centavos) filter (where papel = 'gorjeta'), 0)
    into v_com, v_gor from comissoes
  where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  if v_com + v_gor = 0 then raise exception 'nada_a_pagar' using errcode = '22023'; end if;
  -- desconta os vales do mais antigo ao mais novo enquanto couberem; o que não couber fica para o próximo pagamento
  for x in select * from vales where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and data <= p_fim order by data, criado_em loop
    exit when v_val + x.valor_centavos > v_com + v_gor;
    v_val := v_val + x.valor_centavos;
    v_quitar := v_quitar || x.id;
  end loop;
  insert into fechamentos_comissao (salao_id, profissional_id, periodo_inicio, periodo_fim, comissoes_centavos, gorjetas_centavos, vales_centavos, pago_centavos, forma)
  values (v_salao, p_prof, p_inicio, p_fim, v_com, v_gor, v_val, v_com + v_gor - v_val, left(p_forma, 40)) returning id into v_id;
  update comissoes set fechamento_id = v_id where salao_id = v_salao and profissional_id = p_prof and fechamento_id is null and competencia between p_inicio and p_fim;
  update vales set fechamento_id = v_id where id = any (v_quitar);
  return v_id;
end
$$;

-- ───────────── 6, 7 e 11) Link público: sinal só com meio de cobrança, nome digitado, aceite sem herdar cadastro alheio ─────────────
alter table aceites_politica add column nome_informado text check (length(nome_informado) <= 120);

create or replace function agendar_online(
  p_slug text, p_servico uuid, p_profissional uuid, p_inicio timestamptz,
  p_nome text, p_telefone text, p_aceite_contato boolean, p_ip text, p_agente text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  c saloes;
  v_srv servicos;
  v_tel text := tel_nacional(p_telefone);
  v_cli uuid;
  v_ag agendamentos;
  v_sinal int;
  v_mp boolean;
  v_texto text;
begin
  select * into c from saloes where slug = lower(p_slug) and agendamento_online;
  if c.id is null then raise exception 'salao_indisponivel' using errcode = 'P0002'; end if;
  select * into v_srv from servicos where id = p_servico and salao_id = c.id and ativo and online;
  if v_srv.id is null or not exists (select 1 from membros where user_id = p_profissional and salao_id = c.id and ativo and papel in ('admin', 'profissional')) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_nome, ''))) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if not coalesce(p_aceite_contato, false) then raise exception 'consentimento obrigatório' using errcode = '22023'; end if;
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(c.id, p_profissional, p_inicio, v_srv.fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  -- Telefone já cadastrado: o horário entra nesse cadastro, mas o aceite de contato não é herdado de quem digitou
  -- (sem verificar o número, qualquer um poderia ligar lembretes no WhatsApp de outra pessoa).
  select id into v_cli from clientes where salao_id = c.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli is null then
    insert into clientes (salao_id, nome, telefone, consentimento_em, origem) values (c.id, left(trim(p_nome), 120), v_tel, now(), 'outro') returning id into v_cli;
  end if;

  v_mp := exists (select 1 from pagamentos_contas where salao_id = c.id and mp_access_token is not null);
  v_sinal := case when c.pix_chave is not null or v_mp then round(coalesce(v_srv.preco_centavos, 0) * v_srv.sinal_percentual / 100.0)::int else 0 end;
  begin
    insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fases, origem, status)
    values (c.id, v_cli, p_profissional, p_servico, p_inicio, v_srv.fases, 'online', case when v_sinal > 0 then 'agendado' else 'confirmado' end::status_agendamento)
    returning * into v_ag;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;

  v_texto := coalesce(nullif(trim(c.politica_cancelamento), ''),
    format('Cancelamentos e remarcações até %s horas antes do horário. Depois disso, ou em caso de falta, o sinal não é devolvido.', c.cancelamento_horas));
  insert into aceites_politica (salao_id, agendamento_id, cliente_id, texto, ip, agente, nome_informado)
  values (c.id, v_ag.id, v_cli, v_texto, left(p_ip, 64), left(p_agente, 300), left(trim(p_nome), 120));
  if v_sinal > 0 then
    insert into sinais (salao_id, agendamento_id, valor_centavos, modo) values (c.id, v_ag.id, v_sinal, case when v_mp then 'mercadopago' else 'pix_manual' end);
  end if;
  return jsonb_build_object('agendamento_id', v_ag.id, 'token', v_ag.token, 'sinal_centavos', v_sinal);
end
$$;

-- A página do horário mostra o nome digitado, nunca o do cadastro que tinha aquele telefone.
create or replace function horario_publico(p_token uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object(
    'id', a.id, 'inicio', a.inicio, 'fim', a.fim, 'status', a.status, 'servico', s.nome, 'profissional', m.nome,
    'cliente', split_part(coalesce((select p.nome_informado from aceites_politica p where p.agendamento_id = a.id order by aceito_em desc limit 1), 'Olá'), ' ', 1),
    'salao', c.nome, 'slug', c.slug, 'fuso', c.fuso, 'endereco', c.endereco, 'telefone', c.telefone,
    'cancelamento_horas', c.cancelamento_horas,
    'pode_cancelar', a.status in ('agendado', 'confirmado') and a.inicio - now() >= make_interval(hours => c.cancelamento_horas),
    'sinal', (select jsonb_build_object('valor', x.valor_centavos, 'status', x.status, 'modo', x.modo, 'copia_cola', x.copia_cola, 'expira_em', x.expira_em)
              from sinais x where x.agendamento_id = a.id),
    'politica', (select texto from aceites_politica p where p.agendamento_id = a.id order by aceito_em desc limit 1)
  )
  from agendamentos a join saloes c on c.id = a.salao_id join servicos s on s.id = a.servico_id
  join membros m on m.user_id = a.profissional_id and m.salao_id = a.salao_id
  where a.token = p_token
$$;

-- Cancelado pela cliente: sinal pendente vira "cancelado" (diferente de expirado), pago vira crédito.
create or replace function cancelar_online(p_token uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a agendamentos;
  c saloes;
begin
  select * into a from agendamentos where token = p_token for update;
  if a.id is null then return 'nao_encontrado'; end if;
  select * into c from saloes where id = a.salao_id;
  if a.status not in ('agendado', 'confirmado') then return 'ja_cancelado'; end if;
  if a.inicio - now() < make_interval(hours => c.cancelamento_horas) then return 'fora_do_prazo'; end if;
  update agendamentos set status = 'cancelado' where id = a.id;
  update sinais set status = case status when 'pago' then 'credito' when 'pendente' then 'cancelado' else status end where agendamento_id = a.id;
  return 'cancelado';
end
$$;

-- O modo passa a ser o que de fato foi gerado (se o Mercado Pago falhar e cair no Pix da chave, a página não promete confirmação automática).
drop function registrar_cobranca_sinal(uuid, text, text, text);
create function registrar_cobranca_sinal(p_agendamento uuid, p_txid text, p_copia_cola text, p_mp_payment_id text, p_modo text) returns void
language sql security definer set search_path = public, pg_temp as
$$
  update sinais set txid = left(p_txid, 35), copia_cola = left(p_copia_cola, 600), mp_payment_id = coalesce(p_mp_payment_id, mp_payment_id),
    modo = case when p_modo in ('pix_manual', 'mercadopago') then p_modo else modo end
  where agendamento_id = p_agendamento and status = 'pendente'
$$;

-- Webhook preso ao salão; pagamento atrasado de quem cancelou vira crédito em vez de ressuscitar o horário.
drop function sinal_pago_mp(text, int);
create function sinal_pago_mp(p_payment_id text, p_valor_centavos int, p_salao uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  x sinais;
begin
  select * into x from sinais where mp_payment_id = p_payment_id and salao_id = p_salao for update;
  if x.id is null or x.status not in ('pendente', 'expirado', 'cancelado') or p_valor_centavos < x.valor_centavos then return false; end if;
  if x.status = 'cancelado' then
    update sinais set status = 'credito', pago_em = now() where id = x.id;
    return true;
  end if;
  update sinais set status = 'pago', pago_em = now() where id = x.id;
  begin
    update agendamentos set status = 'confirmado' where id = x.agendamento_id and status in ('agendado', 'cancelado');
  exception when exclusion_violation then
    update sinais set status = 'credito' where id = x.id;
  end;
  return true;
end
$$;

revoke all on function registrar_cobranca_sinal(uuid, text, text, text, text), sinal_pago_mp(text, int, uuid) from public, anon, authenticated;
grant execute on function registrar_cobranca_sinal(uuid, text, text, text, text), sinal_pago_mp(text, int, uuid) to service_role;

-- ───────────── 12) Vale tirado do caixa: vale e retirada juntos ou nenhum ─────────────
create function vale_do_caixa(p_caixa uuid, p_prof uuid, p_valor int, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_nome text;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção mexem no caixa' using errcode = '42501'; end if;
  if not exists (select 1 from caixas where id = p_caixa and salao_id = meu_salao() and fechado_em is null) then raise exception 'caixa_fechado' using errcode = '55000'; end if;
  select nome into v_nome from membros where user_id = p_prof and salao_id = meu_salao();
  if v_nome is null then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
  insert into vales (salao_id, profissional_id, valor_centavos, motivo) values (meu_salao(), p_prof, p_valor, coalesce(nullif(trim(p_motivo), ''), 'Retirado do caixa'));
  insert into caixa_movimentos (salao_id, caixa_id, tipo, valor_centavos, motivo)
  values (meu_salao(), p_caixa, 'sangria', p_valor, left('Vale para ' || v_nome || coalesce(': ' || nullif(trim(p_motivo), ''), ''), 200));
end
$$;
revoke all on function vale_do_caixa(uuid, uuid, int, text) from public, anon;
grant execute on function vale_do_caixa(uuid, uuid, int, text) to authenticated;
