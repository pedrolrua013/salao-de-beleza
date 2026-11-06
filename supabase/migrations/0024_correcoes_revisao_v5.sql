-- Belezando · correções da quinta revisão (robô com atendimento de vários serviços, pagamento de comissão em dobro).

-- Um item por atendimento: serviços juntos ("Coloração + Corte"), com o id do primeiro.
create or replace function agendamentos_whatsapp(p_salao uuid, p_conversa uuid)
returns table (id uuid, inicio timestamptz, servico text, profissional text)
language sql stable security definer set search_path = public, pg_temp as
$$
  select (array_agg(a.id order by a.inicio))[1], min(a.inicio),
         string_agg(s.nome, ' + ' order by a.inicio), string_agg(distinct m.nome, ', ')
  from conversas v
  join clientes p on p.salao_id = v.salao_id
    and (p.id = v.cliente_id or tel_nacional(p.telefone) = v.telefone)
  join agendamentos a on a.cliente_id = p.id and a.salao_id = v.salao_id
  join servicos s on s.id = a.servico_id
  join membros m on m.user_id = a.profissional_id
  where v.id = p_conversa and v.salao_id = p_salao
    and a.status in ('agendado', 'confirmado') and a.inicio > now()
  group by coalesce(a.grupo_id, a.id)
  order by min(a.inicio)
  limit 10
$$;

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
  perform 1 from membros where user_id = p_prof and salao_id = v_salao for update;  -- um pagamento de cada vez por profissional
  if not found then raise exception 'profissional não encontrado' using errcode = 'P0002'; end if;
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
