-- Belezando · segurança do agendamento online (limite de marcações por endereço e por salão).

create index if not exists aceites_ip_idx on aceites_politica (ip, aceito_em);
create index if not exists aceites_salao_idx on aceites_politica (salao_id, aceito_em);

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
  -- Contra robô que lota a agenda com clientes falsas (e manda WhatsApp para números de estranhos):
  -- até 5 marcações por hora do mesmo endereço e 40 por hora no salão.
  if p_ip is not null and (select count(distinct agendamento_id) from aceites_politica where ip = p_ip and aceito_em > now() - interval '1 hour') >= 5 then
    raise exception 'muitas_tentativas' using errcode = '54000';
  end if;
  if (select count(distinct agendamento_id) from aceites_politica where salao_id = c.id and aceito_em > now() - interval '1 hour') >= 40 then
    raise exception 'muitas_tentativas' using errcode = '54000';
  end if;
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
