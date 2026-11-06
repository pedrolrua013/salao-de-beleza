-- Belezando · correções da terceira revisão (atendimento com vários serviços, ficha de primeira visita, união de cadastros, vale-presente).

-- Quem marca pelo link com o telefone de alguém já cadastrado não recebe a ficha dela; cliente nova nasce sem origem (a ficha preenche).
create or replace function agendar_online_grupo(
  p_slug text, p_servicos uuid[], p_profissional uuid, p_inicio timestamptz,
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
  v_novo boolean := false;
  v_fases jsonb := '[]';
  v_grupo uuid;
  v_t timestamptz;
  v_lider agendamentos;
  v_sid uuid;
  k int;
begin
  select * into c from saloes where slug = lower(p_slug) and agendamento_online;
  if c.id is null then raise exception 'salao_indisponivel' using errcode = 'P0002'; end if;
  if coalesce(array_length(p_servicos, 1), 0) not between 1 and 4 then raise exception 'dados inválidos' using errcode = '22023'; end if;
  -- o atendimento inteiro precisa caber: as fases dos serviços em sequência
  v_sinal := 0;
  foreach v_sid in array p_servicos loop
    select * into v_srv from servicos where id = v_sid and salao_id = c.id and ativo and online;
    if v_srv.id is null then raise exception 'dados inválidos' using errcode = '22023'; end if;
    v_fases := v_fases || v_srv.fases;
    v_sinal := v_sinal + round(coalesce(v_srv.preco_centavos, 0) * v_srv.sinal_percentual / 100.0)::int;
  end loop;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = c.id and ativo and papel in ('admin', 'profissional')) then
    raise exception 'dados inválidos' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_nome, ''))) < 2 or v_tel !~ '^[0-9]{10,11}$' then raise exception 'nome_telefone' using errcode = '22023'; end if;
  if not coalesce(p_aceite_contato, false) then raise exception 'consentimento obrigatório' using errcode = '22023'; end if;
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(c.id, p_profissional, p_inicio, v_fases) then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end if;

  -- Telefone já cadastrado: o horário entra nesse cadastro, mas o aceite de contato não é herdado de quem digitou
  -- (sem verificar o número, qualquer um poderia ligar lembretes no WhatsApp de outra pessoa).
  select id into v_cli from clientes where salao_id = c.id and tel_nacional(telefone) = v_tel order by criado_em limit 1;
  if v_cli is null then
    insert into clientes (salao_id, nome, telefone, consentimento_em) values (c.id, left(trim(p_nome), 120), v_tel, now()) returning id into v_cli;
    v_novo := true;
  end if;

  v_mp := exists (select 1 from pagamentos_contas where salao_id = c.id and mp_access_token is not null);
  if c.pix_chave is null and not v_mp then v_sinal := 0; end if;
  v_grupo := case when array_length(p_servicos, 1) > 1 then gen_random_uuid() end;
  v_t := p_inicio;
  begin
    for k in 1 .. array_length(p_servicos, 1) loop
      select * into v_srv from servicos where id = p_servicos[k];
      insert into agendamentos (salao_id, cliente_id, profissional_id, servico_id, inicio, fases, origem, status, grupo_id)
      values (c.id, v_cli, p_profissional, v_srv.id, v_t, v_srv.fases, 'online', case when v_sinal > 0 then 'agendado' else 'confirmado' end::status_agendamento, v_grupo)
      returning * into v_ag;
      if k = 1 then v_lider := v_ag; end if;
      v_t := v_ag.fim;
    end loop;
  exception when exclusion_violation then
    raise exception 'horario_indisponivel' using errcode = '22023';
  end;
  v_ag := v_lider;

  v_texto := coalesce(nullif(trim(c.politica_cancelamento), ''),
    format('Cancelamentos e remarcações até %s horas antes do horário. Depois disso, ou em caso de falta, o sinal não é devolvido.', c.cancelamento_horas));
  insert into aceites_politica (salao_id, agendamento_id, cliente_id, texto, ip, agente, nome_informado)
  values (c.id, v_ag.id, v_cli, v_texto, left(p_ip, 64), left(p_agente, 300), left(trim(p_nome), 120));
  if v_sinal > 0 then
    insert into sinais (salao_id, agendamento_id, valor_centavos, modo) values (c.id, v_ag.id, v_sinal, case when v_mp then 'mercadopago' else 'pix_manual' end);
  end if;
  return jsonb_build_object('agendamento_id', v_ag.id, 'token', v_ag.token, 'sinal_centavos', v_sinal, 'cliente_novo', v_novo);
end
$$;

create or replace function criar_link_ficha_online(p_agendamento uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_cli uuid;
begin
  select a.cliente_id into v_cli from agendamentos a join clientes c on c.id = a.cliente_id
  where a.id = p_agendamento and c.criado_em > now() - interval '10 minutes'
    and not exists (select 1 from agendamentos o where o.cliente_id = a.cliente_id and o.id not in (select id from do_grupo(a.id)));
  if v_cli is null or exists (select 1 from fichas_previas where cliente_id = v_cli) then return null; end if;
  return criar_link_ficha_interno(v_cli);
end
$$;

create or replace function responder_ficha(p_token text, p_respostas jsonb) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  f fichas_previas;
  r jsonb := p_respostas;
  v_resumo text;
begin
  select * into f from fichas_previas where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if f.id is null then return 'nao_encontrado'; end if;
  if f.respondida_em is not null then return 'ja_respondida'; end if;
  if f.expira_em < now() then return 'expirada'; end if;
  if jsonb_typeof(r) <> 'object' or length(r::text) > 4000 then return 'invalida'; end if;
  update fichas_previas set respostas = r, respondida_em = now() where id = f.id;
  v_resumo := concat_ws(' · ',
    'Ficha de primeira visita (' || to_char(now(), 'DD/MM/YYYY') || ')',
    nullif('química recente: ' || coalesce(r ->> 'quimica', ''), 'química recente: '),
    nullif('quando: ' || coalesce(r ->> 'quimica_quando', ''), 'quando: '),
    case r ->> 'reacao_tintura' when 'sim' then 'já teve reação a tintura' end,
    case r ->> 'couro_sensivel' when 'sim' then 'couro cabeludo sensível' end,
    case r ->> 'gestante' when 'sim' then 'gestante ou amamentando' end,
    nullif('medicamento: ' || coalesce(r ->> 'medicamento', ''), 'medicamento: '),
    nullif('quer: ' || coalesce(r ->> 'objetivo', ''), 'quer: '));
  update clientes c set
    tipo_cabelo = coalesce(case when r ->> 'tipo_cabelo' in ('liso', 'ondulado', 'cacheado', 'crespo') then r ->> 'tipo_cabelo' end, c.tipo_cabelo),
    alergias = left(nullif(concat_ws('; ', c.alergias, nullif(trim(r ->> 'alergias'), '')), ''), 500),
    origem = coalesce(nullif(c.origem, 'outro'), case when r ->> 'origem' in ('indicacao', 'instagram', 'google', 'whatsapp', 'passante', 'facebook', 'tiktok', 'outro') then r ->> 'origem' end),
    nascimento = coalesce(c.nascimento, case when (r ->> 'nascimento') ~ '^\d{4}-\d{2}-\d{2}$' and (r ->> 'nascimento')::date between date '1900-01-01' and current_date then (r ->> 'nascimento')::date end),
    observacoes = left(concat_ws(E'\n', c.observacoes, v_resumo), 2000)
  where c.id = f.cliente_id;
  return 'respondida';
end
$$;

-- Qualquer mudança num serviço do atendimento refaz os lembretes do grupo (o "primeiro" pode ter mudado).
create or replace function trg_lembretes_agendamento() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare r record;
begin
  for r in select id from do_grupo(new.id) loop
    perform programar_lembretes(r.id);
  end loop;
  return new;
end
$$;

-- Cancelar pelo robô cancela todos os serviços do atendimento.
create or replace function cancelar_whatsapp(p_salao uuid, p_conversa uuid, p_agendamento uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare n int;
begin
  if not exists (select 1 from agendamentos_whatsapp(p_salao, p_conversa) x where x.id = p_agendamento) then return false; end if;
  update agendamentos set status = 'cancelado'
  where id in (select id from do_grupo(p_agendamento)) and salao_id = p_salao and status in ('agendado', 'confirmado') and inicio > now();
  get diagnostics n = row_count;
  return n > 0;
end
$$;

-- Atendimento com profissionais diferentes é remarcado pela recepção (pelo link, todos iriam para um só).
create or replace function remarcar_online(p_token uuid, p_inicio timestamptz, p_profissional uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a agendamentos;
  c saloes;
  v_fases jsonb := '[]';
  r record;
  v_t timestamptz;
begin
  select * into a from agendamentos where token = p_token for update;
  if a.id is null then return 'nao_encontrado'; end if;
  select * into c from saloes where id = a.salao_id;
  if a.status not in ('agendado', 'confirmado') then return 'ja_cancelado'; end if;
  if a.inicio - now() < make_interval(hours => c.cancelamento_horas) then return 'fora_do_prazo'; end if;
  if (select count(distinct profissional_id) from do_grupo(a.id) where status in ('agendado', 'confirmado')) > 1 then return 'varios_profissionais'; end if;
  if not exists (select 1 from membros where user_id = p_profissional and salao_id = a.salao_id and ativo and papel in ('admin', 'profissional')) then return 'dados_invalidos'; end if;
  select coalesce(jsonb_agg(f order by g.inicio, ord), '[]') into v_fases
  from do_grupo(a.id) g, jsonb_array_elements(g.fases) with ordinality as e(f, ord) where g.status in ('agendado', 'confirmado');
  if p_inicio < now() + interval '1 hour' or not cabe_na_jornada(a.salao_id, p_profissional, p_inicio, v_fases) then return 'horario_indisponivel'; end if;
  -- solta as ocupações do atendimento antes de mover (senão um serviço esbarra no outro no meio da troca)
  v_t := p_inicio;
  begin
    delete from ocupacoes where agendamento_id in (select id from do_grupo(a.id));
    for r in select * from do_grupo(a.id) where status in ('agendado', 'confirmado') order by inicio loop
      update agendamentos set inicio = v_t, profissional_id = p_profissional where id = r.id returning fim into v_t;
    end loop;
  exception when exclusion_violation then
    return 'horario_indisponivel';  -- a exceção desfaz tudo o que foi feito dentro do bloco
  end;
  return 'remarcado';
end
$$;

create or replace function horario_publico(p_token uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object(
    'id', a.id, 'inicio', a.inicio, 'fim', (select max(g.fim) from do_grupo(a.id) g where g.status <> 'cancelado'), 'status', a.status,
    'servico', (select string_agg(sv.nome, ' + ' order by g.inicio) from do_grupo(a.id) g join servicos sv on sv.id = g.servico_id where g.status <> 'cancelado' or a.status = 'cancelado'),
    'servico_ids', (select jsonb_agg(g.servico_id order by g.inicio) from do_grupo(a.id) g where g.status in ('agendado', 'confirmado')),
    'varios_profissionais', (select count(distinct g.profissional_id) > 1 from do_grupo(a.id) g where g.status in ('agendado', 'confirmado')),
    'profissional_id', a.profissional_id, 'profissional', m.nome,
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
  update pacotes_cliente set cliente_id = a.id where cliente_id = b.id;
  update cashback_movimentos set cliente_id = a.id where cliente_id = b.id;
  update lista_espera set cliente_id = a.id where cliente_id = b.id;
  update avisos set cliente_id = a.id where cliente_id = b.id;
  update fichas_previas set cliente_id = a.id where cliente_id = b.id;
  update avaliacoes set cliente_id = a.id where cliente_id = b.id;
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
    recusou_lembretes_em = coalesce(a.recusou_lembretes_em, b.recusou_lembretes_em)
  where id = a.id;
  delete from clientes where id = b.id;
end
$$;

-- O vale vale o que foi pago por ele (com a parte do desconto da comanda).
create or replace function vales_presente_comanda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  i comanda_itens;
  v_codigo text;
  v_itens int;
  v_valor int;
begin
  if new.status = 'fechada' and old.status = 'aberta' then
    select coalesce(sum(preco_centavos * quantidade - desconto_centavos), 0) into v_itens from comanda_itens where comanda_id = new.id and tipo <> 'gorjeta';
    for i in select * from comanda_itens where comanda_id = new.id and tipo::text = 'vale_presente' loop
      v_valor := i.preco_centavos - i.desconto_centavos;
      if v_itens > 0 then v_valor := v_valor - round(new.desconto_centavos::numeric * v_valor / v_itens)::int; end if;
      continue when v_valor <= 0;
      loop
        v_codigo := novo_codigo_vale();
        exit when not exists (select 1 from vales_presente where salao_id = new.salao_id and codigo = v_codigo);
      end loop;
      insert into vales_presente (salao_id, codigo, valor_centavos, saldo_centavos, para, mensagem, comprado_por, comanda_id, item_id)
      values (new.salao_id, v_codigo, v_valor, v_valor, i.presente_para, i.presente_mensagem, new.cliente_id, new.id, i.id);
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
