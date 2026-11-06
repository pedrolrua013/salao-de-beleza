-- Belezando · endurecimento de segurança (revisão de segurança de 24/10/2026).

-- 1) Permissões por coluna: o app nunca precisa mexer em consentimento, opt-out, identificador ou fuso.
--    Com o grant da tabela inteira, qualquer membro conseguia alterar esses campos direto pela API.
revoke insert, update on clientes from authenticated;
grant insert (nome, telefone, email, nascimento, observacoes) on clientes to authenticated;
grant update (nome, telefone, email, nascimento, observacoes) on clientes to authenticated;

revoke update on membros from authenticated;
grant update (nome, papel, ativo) on membros to authenticated;

revoke update on saloes from authenticated;
grant update (nome, telefone, endereco, mensagem, abre, fecha, dias_semana, lembretes_ativos, lembrete_hora) on saloes to authenticated;

-- 2) O aceite de contato por WhatsApp só entra por esta função (fica na auditoria, com quem registrou).
--    Não existe função para apagar o PARAR do cliente: quem pediu para parar só volta se o próprio cliente pedir.
create function registrar_aceite_contato(p_cliente uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare n int;
begin
  if auth.uid() is null or meu_salao() is null then return false; end if;
  update clientes set consentimento_em = coalesce(consentimento_em, now())
  where id = p_cliente and salao_id = meu_salao() and consentimento_em is null;
  get diagnostics n = row_count;
  return n > 0;
end
$$;
revoke all on function registrar_aceite_contato(uuid) from public, anon;
grant execute on function registrar_aceite_contato(uuid) to authenticated;

-- 3) Teto de horários futuros por cliente nas marcações feitas pelo robô (impede encher a agenda por WhatsApp).
create function limitar_agendamentos_whatsapp() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if new.origem = 'whatsapp' and new.status in ('agendado', 'confirmado') and
     (select count(*) from agendamentos a
      where a.cliente_id = new.cliente_id and a.status in ('agendado', 'confirmado') and a.inicio > now()) >= 3 then
    raise exception 'limite_agendamentos' using errcode = '22023';
  end if;
  return new;
end
$$;
create trigger lim_agendamentos_whatsapp before insert on agendamentos for each row execute function limitar_agendamentos_whatsapp();

-- 4) Mensagem recebida nunca se perde: só é dada como tratada depois de processada (a Meta reenvia se o servidor responder erro).
alter table mensagens add column processada_em timestamptz;
alter table mensagens add column tentativas smallint not null default 0;
update mensagens set processada_em = criado_em;

drop function receber_mensagem(uuid, text, text, text, text, text);
create function receber_mensagem(
  p_salao uuid, p_wa_id text, p_nome text, p_wa_msg_id text, p_tipo text, p_corpo text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_tel text := tel_nacional(p_wa_id);
  v_conv conversas;
  v_pac clientes;
  v_msg uuid;
  v_nova boolean;
  v_repetida boolean := false;
  v_recebidas int;
begin
  select * into v_conv from conversas where salao_id = p_salao and wa_id = p_wa_id;
  if not found then
    select * into v_pac from clientes where salao_id = p_salao and tel_nacional(telefone) = v_tel order by criado_em limit 1;
    insert into conversas (salao_id, wa_id, telefone, nome_contato, cliente_id)
    values (p_salao, p_wa_id, v_tel, left(nullif(trim(p_nome), ''), 120), v_pac.id)
    on conflict (salao_id, wa_id) do nothing
    returning * into v_conv;
    if v_conv.id is null then   -- duas primeiras mensagens ao mesmo tempo: a outra chegou antes
      select * into v_conv from conversas where salao_id = p_salao and wa_id = p_wa_id;
    end if;
  end if;

  insert into mensagens (salao_id, conversa_id, direcao, autor, tipo, corpo, wa_msg_id)
  values (p_salao, v_conv.id, 'entrada', 'cliente', p_tipo, left(p_corpo, 4096), p_wa_msg_id)
  on conflict (salao_id, wa_msg_id) do nothing
  returning id into v_msg;
  v_nova := v_msg is not null;

  if v_nova then
    update conversas set nao_lidas = nao_lidas + 1, ultima_msg_em = now(), ultima_entrada_em = now(),
      nome_contato = coalesce(nome_contato, left(nullif(trim(p_nome), ''), 120))
    where id = v_conv.id returning * into v_conv;
  else
    -- reenvio de uma mensagem que o servidor não conseguiu tratar: tenta de novo, no máximo 3 vezes
    update mensagens set tentativas = tentativas + 1
    where salao_id = p_salao and wa_msg_id = p_wa_msg_id and direcao = 'entrada' and processada_em is null and tentativas < 3;
    v_repetida := found;
  end if;

  select count(*) into v_recebidas from mensagens
  where conversa_id = v_conv.id and direcao = 'entrada' and criado_em > now() - interval '10 minutes';

  return jsonb_build_object(
    'conversa_id', v_conv.id, 'nova', v_nova or v_repetida, 'bot_ativo', v_conv.bot_ativo, 'estado', v_conv.estado,
    'telefone', v_conv.telefone, 'nome_contato', v_conv.nome_contato,
    'limitado', v_recebidas > 30,      -- mais de 30 mensagens em 10 minutos: não responde (evita custo e abuso)
    'cliente_nome', (select nome from clientes where id = v_conv.cliente_id),
    'consentiu', coalesce((select consentimento_em is not null from clientes where id = v_conv.cliente_id), false)
  );
end
$$;
revoke all on function receber_mensagem(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function receber_mensagem(uuid, text, text, text, text, text) to service_role;

-- 5) Funções: nada executável por anônimo, e search_path sem pg_temp nas funções SECURITY DEFINER.
revoke execute on all functions in schema public from anon;
alter default privileges in schema public revoke execute on functions from anon, public;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef loop
    execute format('alter function %s set search_path = public, pg_temp', f.assinatura);
  end loop;
end $$;
