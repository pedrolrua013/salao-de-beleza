-- Belezando · correções da segunda revisão (pacotes, cashback, união de cadastros, lista de espera, painel).

-- 1) Pagamento com pacote, cashback ou sinal só pelas funções que descontam o saldo (nunca digitado na comanda).
create function trava_pagamento_credito() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if new.forma::text in ('pacote', 'cashback', 'sinal') and current_user in ('authenticated', 'anon') then
    raise exception 'use o botão de pacote, cashback ou sinal' using errcode = '42501';
  end if;
  return new;
end
$$;
create trigger trava_pagamento_credito before insert on comanda_pagamentos for each row execute function trava_pagamento_credito();
revoke execute on function trava_pagamento_credito() from public, anon, authenticated;

-- 2) Unir cadastros não pode apagar pacote pago, cashback, lista de espera nem avisos.
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

-- 3 e 4) Cancelar a comanda devolve todas as sessões usadas nela (inclusive duas do mesmo saldo e as de valor zero).
create or replace function devolver_pacote_cashback_cancelada() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update pacote_saldos ps set usado = ps.usado - x.n
  from (select u.saldo_id, count(*) n from pacote_usos u join comanda_itens i on i.id = u.comanda_item_id where i.comanda_id = new.id group by u.saldo_id) x
  where ps.id = x.saldo_id;
  delete from pacote_usos where comanda_item_id in (select id from comanda_itens where comanda_id = new.id);
  delete from cashback_movimentos where comanda_pagamento_id in (select id from comanda_pagamentos where comanda_id = new.id);
  return new;
end
$$;

-- 5) Saldo de cashback: cada uso consome os créditos válidos mais antigos naquele momento; o que sobra e não venceu é o saldo.
create or replace function saldo_cashback(p_cliente uuid) returns int
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  m record;
  ids uuid[] := '{}';
  vence timestamptz[] := '{}';
  resto int[] := '{}';
  falta int;
  k int;
  total int := 0;
begin
  for m in select * from cashback_movimentos where cliente_id = p_cliente and salao_id = meu_salao() order by criado_em, tipo loop
    if m.tipo = 'credito' then
      ids := ids || m.id; vence := vence || m.expira_em; resto := resto || m.valor_centavos;
    else
      falta := -m.valor_centavos;
      for k in 1 .. coalesce(array_length(ids, 1), 0) loop
        exit when falta <= 0;
        if vence[k] > m.criado_em and resto[k] > 0 then
          if resto[k] >= falta then resto[k] := resto[k] - falta; falta := 0;
          else falta := falta - resto[k]; resto[k] := 0; end if;
        end if;
      end loop;
    end if;
  end loop;
  for k in 1 .. coalesce(array_length(ids, 1), 0) loop
    if vence[k] > now() then total := total + resto[k]; end if;
  end loop;
  return total;
end
$$;

-- 6) Sessão de pacote, cashback ou sinal de uma cliente não pode pagar a comanda de outra.
create or replace function trava_comanda() returns trigger
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
  if new.cliente_id is distinct from old.cliente_id and current_setting('belezando.reabrindo', true) is distinct from 'sim'
     and exists (select 1 from comanda_pagamentos where comanda_id = old.id and forma::text in ('pacote', 'cashback', 'sinal')) then
    raise exception 'comanda_com_credito_da_cliente' using errcode = '55000';
  end if;
  return new;
end
$$;

-- 7) Quem foi avisada de uma vaga e não conseguiu marcar continua recebendo as próximas.
create or replace function avisar_lista_espera() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  s saloes;
  v_local timestamp;
  v_periodo text;
  e record;
  n int := 0;
begin
  if new.status <> 'cancelado' or old.status = 'cancelado' or new.inicio < now() + interval '1 hour' then return new; end if;
  select * into s from saloes where id = new.salao_id;
  if not s.espera_ativa then return new; end if;
  v_local := new.inicio at time zone s.fuso;
  v_periodo := case when v_local::time < '12:00' then 'manha' when v_local::time < '18:00' then 'tarde' else 'noite' end;
  for e in
    select l.*, c.nome cliente_nome from lista_espera l join clientes c on c.id = l.cliente_id
    where l.salao_id = new.salao_id and l.estado in ('aguardando', 'avisado') and l.servico_id = new.servico_id
      and v_local::date between l.data_de and l.data_ate
      and (l.periodo = 'qualquer' or l.periodo = v_periodo)
      and (l.profissional_id is null or l.profissional_id = new.profissional_id)
      and l.cliente_id <> new.cliente_id and cliente_contatavel(c)
    order by l.criado_em limit 3
  loop
    insert into avisos (salao_id, cliente_id, tipo, chave, dados)
    values (new.salao_id, e.cliente_id, 'vaga', 'vaga:' || e.id || ':' || new.id,
            jsonb_build_object('servico_id', new.servico_id, 'profissional_id', new.profissional_id, 'inicio', new.inicio, 'espera_id', e.id))
    on conflict (salao_id, chave) do nothing;
    update lista_espera set estado = 'avisado', avisado_em = now() where id = e.id;
    n := n + 1;
  end loop;
  return new;
end
$$;

-- Aviso que travou três vezes no envio é dado como falha (não fica pendente para sempre).
create or replace function reservar_avisos(p_limite int) returns table (
  id uuid, salao_id uuid, tipo text, dados jsonb, wa_id text, cliente_nome text, salao_nome text, slug text, fuso text
)
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update avisos a set tentativas = a.tentativas + 1, estado = case when a.tentativas + 1 >= 3 then 'falhou' else 'pendente' end
  where a.estado = 'enviando' and a.reservado_em < now() - interval '15 minutes';
  -- vaga velha não serve mais; cliente que marcou ou pediu PARAR não recebe
  update avisos a set estado = 'cancelado', erro = 'passou da hora' where a.estado = 'pendente' and a.tipo = 'vaga' and a.criado_em < now() - interval '3 hours';
  update avisos a set estado = 'cancelado', erro = 'cliente não pode receber ou já marcou'
  where a.estado = 'pendente' and a.enviar_em <= now()
    and (not exists (select 1 from clientes c where c.id = a.cliente_id and cliente_contatavel(c))
         or (a.tipo = 'retorno' and exists (select 1 from agendamentos f where f.cliente_id = a.cliente_id and f.inicio > now() and f.status in ('agendado', 'confirmado'))));
  return query
  with alvo as (
    select v.id from avisos v where v.estado = 'pendente' and v.enviar_em <= now() and v.tentativas < 3
    order by v.enviar_em limit p_limite for update skip locked
  ), marcado as (
    update avisos v set estado = 'enviando', reservado_em = now() from alvo where v.id = alvo.id returning v.*
  )
  select m.id, m.salao_id, m.tipo, m.dados,
    coalesce((select cv.wa_id from conversas cv where cv.salao_id = m.salao_id and cv.cliente_id = c.id order by cv.ultima_msg_em desc limit 1), '55' || tel_nacional(c.telefone)),
    c.nome, s.nome, s.slug, s.fuso
  from marcado m join clientes c on c.id = m.cliente_id join saloes s on s.id = m.salao_id;
end
$$;

-- 8) O faturamento por dia bate com a receita do período.
create or replace function painel(p_inicio date, p_fim date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  s saloes;
  de timestamptz; ate timestamptz;
  r jsonb;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador vê o painel' using errcode = '42501'; end if;
  if p_fim < p_inicio or p_fim - p_inicio > 400 then raise exception 'periodo_invalido' using errcode = '22023'; end if;
  select * into s from saloes where id = v_salao;
  de := (p_inicio::timestamp) at time zone s.fuso;
  ate := ((p_fim + 1)::timestamp) at time zone s.fuso;

  with
  cmd as (
    select c.id, c.cliente_id, (c.fechada_em at time zone s.fuso)::date dia from comandas c
    where c.salao_id = v_salao and c.status = 'fechada' and c.fechada_em >= de and c.fechada_em < ate
  ),
  itens as (
    select i.*, cmd.dia from comanda_itens i join cmd on cmd.id = i.comanda_id
  ),
  vendas as (
    select
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'servico'), 0) servicos,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo = 'produto'), 0) produtos,
      coalesce(sum(i.preco_centavos) filter (where i.tipo = 'gorjeta'), 0) gorjetas,
      coalesce(sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo::text = 'pacote'), 0) pacotes
    from itens i
  ),
  descontos as (select coalesce(sum(c.desconto_centavos), 0) v from comandas c join cmd on cmd.id = c.id),
  -- serviço usado do pacote ou pago com cashback não é dinheiro novo
  creditos as (select coalesce(sum(p.valor_centavos), 0) v from comanda_pagamentos p join cmd on cmd.id = p.comanda_id where p.forma::text in ('pacote', 'cashback')),
  ags as (
    select a.* from agendamentos a where a.salao_id = v_salao and a.inicio >= de and a.inicio < ate
  ),
  atendidos as (select distinct cliente_id from ags where status = 'concluido'),
  -- cliente que já tinha vindo antes do período
  retornou as (
    select count(*) n from atendidos t
    where exists (select 1 from agendamentos x where x.cliente_id = t.cliente_id and x.status = 'concluido' and x.inicio < de)
  ),
  novos as (
    select c.id, c.origem from clientes c where c.salao_id = v_salao and c.criado_em >= de and c.criado_em < ate
  ),
  -- saiu com o próximo horário marcado: existe agendamento criado até o fim do dia do atendimento, para depois dele
  rebook as (
    select count(*) filter (where exists (
      select 1 from agendamentos x where x.cliente_id = a.cliente_id and x.inicio > a.fim and x.status <> 'cancelado'
        and x.criado_em < ((((a.inicio at time zone s.fuso)::date + 1)::timestamp) at time zone s.fuso)
    )) sim, count(*) total
    from (select distinct on (cliente_id) * from ags where status = 'concluido' order by cliente_id, inicio desc) a
  ),
  -- minutos disponíveis: jornada de cada profissional nos dias de trabalho, menos almoço e bloqueios
  dias as (select d::date dia from generate_series(p_inicio, p_fim, interval '1 day') d),
  jornada as (
    select m.user_id, m.nome, d.dia,
      greatest(extract(epoch from coalesce(m.saida, s.fecha) - coalesce(m.entrada, s.abre)) / 60
        - coalesce(extract(epoch from m.almoco_fim - m.almoco_inicio) / 60, 0), 0) minutos
    from membros m cross join dias d
    where m.salao_id = v_salao and m.ativo and m.papel in ('admin', 'profissional')
      and extract(isodow from d.dia)::int = any (coalesce(m.dias_semana, s.dias_semana))
  ),
  bloqueado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo * tstzrange(de, ate)) - lower(o.periodo * tstzrange(de, ate))) / 60) minutos
    from ocupacoes o where o.salao_id = v_salao and o.bloqueio_id is not null and o.periodo && tstzrange(de, ate) group by 1
  ),
  ocupado as (
    select o.profissional_id, sum(extract(epoch from upper(o.periodo) - lower(o.periodo)) / 60) minutos
    from ocupacoes o join agendamentos a on a.id = o.agendamento_id
    where o.salao_id = v_salao and a.inicio >= de and a.inicio < ate and a.status <> 'faltou' group by 1
  ),
  por_prof as (
    select j.user_id, j.nome, sum(j.minutos) - coalesce(max(b.minutos), 0) disponivel, coalesce(max(o.minutos), 0) ocupado
    from jornada j left join bloqueado b on b.profissional_id = j.user_id left join ocupado o on o.profissional_id = j.user_id
    group by j.user_id, j.nome
  ),
  receita_prof as (
    select i.profissional_id, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) receita, count(distinct i.comanda_id) atendimentos
    from itens i where i.tipo = 'servico' group by 1
  ),
  comissao_prof as (
    select profissional_id, sum(valor_centavos) v from comissoes
    where salao_id = v_salao and papel <> 'gorjeta' and competencia between p_inicio and p_fim group by 1
  ),
  por_dia as (
    select d.dia, sum(d.v) v from (
      select i.dia, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) filter (where i.tipo <> 'gorjeta') v from itens i group by 1
      union all
      select cmd.dia, -sum(c.desconto_centavos) from comandas c join cmd on cmd.id = c.id group by 1
      union all
      select cmd.dia, -sum(p.valor_centavos) from comanda_pagamentos p join cmd on cmd.id = p.comanda_id where p.forma::text in ('pacote', 'cashback') group by 1
    ) d group by 1
  ),
  top_servicos as (
    select i.descricao, count(*) n, sum(i.preco_centavos * i.quantidade - i.desconto_centavos) v from itens i where i.tipo = 'servico'
    group by 1 order by v desc limit 8
  )
  select jsonb_build_object(
    'receita', (select servicos + produtos + pacotes from vendas) - (select v from descontos) - (select v from creditos),
    'pacotes', (select pacotes from vendas),
    'servicos', (select servicos from vendas), 'produtos', (select produtos from vendas), 'gorjetas', (select gorjetas from vendas),
    'comandas', (select count(*) from cmd),
    'atendimentos', (select count(*) from ags where status = 'concluido'),
    'faltas', (select count(*) from ags where status = 'faltou'),
    'cancelados', (select count(*) from ags where status = 'cancelado'),
    'clientes_atendidos', (select count(*) from atendidos),
    'clientes_retorno', (select n from retornou),
    'clientes_novos', (select count(*) from novos),
    'origem_novos', coalesce((select jsonb_object_agg(coalesce(origem, 'nao_informado'), n) from (select origem, count(*) n from novos group by 1) o), '{}'::jsonb),
    'rebook', (select jsonb_build_object('sim', sim, 'total', total) from rebook),
    'ocupacao', (select jsonb_build_object('disponivel', coalesce(sum(disponivel), 0), 'ocupado', coalesce(sum(ocupado), 0)) from por_prof),
    'online', (select count(*) from ags where origem = 'online'), 'whatsapp', (select count(*) from ags where origem = 'whatsapp'),
    'profissionais', coalesce((select jsonb_agg(jsonb_build_object('id', p.user_id, 'nome', p.nome, 'disponivel', p.disponivel, 'ocupado', p.ocupado,
        'receita', coalesce(r.receita, 0), 'atendimentos', coalesce(r.atendimentos, 0), 'comissao', coalesce(c.v, 0)) order by coalesce(r.receita, 0) desc)
      from por_prof p left join receita_prof r on r.profissional_id = p.user_id left join comissao_prof c on c.profissional_id = p.user_id), '[]'::jsonb),
    'por_dia', coalesce((select jsonb_object_agg(dia, v) from por_dia), '{}'::jsonb),
    'top_servicos', coalesce((select jsonb_agg(jsonb_build_object('nome', descricao, 'n', n, 'v', v)) from top_servicos), '[]'::jsonb)
  ) into r;
  return r;
end
$$;
