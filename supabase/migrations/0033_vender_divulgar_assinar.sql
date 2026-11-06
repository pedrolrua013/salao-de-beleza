-- Promoções e horários vazios, etiquetas e campanhas no WhatsApp, vitrine pública do salão, avisos para a equipe,
-- nota fiscal de serviço e termos com assinatura digital.

-- ───────────── promoções (dia/horário fixo ou última hora) ─────────────
create table promocoes (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 60),
  tipo text not null check (tipo in ('horario', 'ultima_hora')),
  percentual int not null check (percentual between 5 and 70),
  dias_semana int[] not null default '{1,2,3,4,5,6,7}' check (dias_semana <@ '{1,2,3,4,5,6,7}' and cardinality(dias_semana) between 1 and 7),
  hora_inicio time,
  hora_fim time,
  horas_antes int check (horas_antes between 1 and 72),   -- última hora: vale para horários que começam em até X horas
  servico_ids uuid[] check (servico_ids is null or cardinality(servico_ids) between 1 and 50),   -- nulo = todos os serviços
  valida_ate date,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  check (hora_inicio is null or hora_fim is null or hora_fim > hora_inicio),
  check (tipo <> 'ultima_hora' or horas_antes is not null)
);
create index on promocoes (salao_id) where ativa;
alter table promocoes enable row level security;
create policy promo_ler on promocoes for select to authenticated using (salao_id = (select meu_salao()));
create policy promo_criar on promocoes for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy promo_editar on promocoes for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy promo_apagar on promocoes for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on promocoes from anon, authenticated;
grant select, delete on promocoes to authenticated;
grant insert (nome, tipo, percentual, dias_semana, hora_inicio, hora_fim, horas_antes, servico_ids, valida_ate, ativa) on promocoes to authenticated;
grant update (ativa) on promocoes to authenticated;

-- A maior promoção que vale para aquele serviço naquele horário (no fuso do salão). Promoções são públicas (aparecem no link).
create function promocao_em(p_salao uuid, p_servico uuid, p_inicio timestamptz, p_agora timestamptz default now()) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('id', p.id, 'nome', p.nome, 'percentual', p.percentual)
  from promocoes p join saloes s on s.id = p.salao_id
  cross join lateral (select p_inicio at time zone s.fuso as l) t
  where p.salao_id = p_salao and p.ativa
    and (p.valida_ate is null or t.l::date <= p.valida_ate)
    and (p.servico_ids is null or p_servico = any (p.servico_ids))
    and extract(isodow from t.l)::int = any (p.dias_semana)
    and (p.hora_inicio is null or t.l::time >= p.hora_inicio)
    and (p.hora_fim is null or t.l::time < p.hora_fim)
    and (p.tipo = 'horario' or (p_inicio > p_agora and p_inicio <= p_agora + make_interval(hours => p.horas_antes)))
  order by p.percentual desc, p.criado_em
  limit 1
$$;
revoke all on function promocao_em(uuid, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function promocao_em(uuid, uuid, timestamptz, timestamptz) to authenticated, service_role;

-- O desconto fica gravado no horário quando ele é marcado (ou remarcado): a comanda usa esse valor.
alter table agendamentos add column promocao_percentual int not null default 0 check (promocao_percentual between 0 and 70);
alter table agendamentos add column promocao_nome text check (length(promocao_nome) <= 60);
create function aplicar_promocao() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v jsonb;
begin
  if tg_op = 'UPDATE' and new.inicio = old.inicio and new.servico_id = old.servico_id then return new; end if;
  v := promocao_em(new.salao_id, new.servico_id, new.inicio);
  new.promocao_percentual := coalesce((v ->> 'percentual')::int, 0);
  new.promocao_nome := v ->> 'nome';
  return new;
end
$$;
revoke execute on function aplicar_promocao() from public, anon, authenticated;
create trigger aplicar_promocao before insert or update of inicio, servico_id on agendamentos for each row execute function aplicar_promocao();

-- ───────────── etiquetas e campanhas pelo WhatsApp ─────────────
create function etiquetas_ok(e text[]) returns boolean
language sql immutable as
$$ select cardinality(e) <= 10 and coalesce((select bool_and(length(x) between 1 and 30 and x = lower(trim(x))) from unnest(e) x), true) $$;
alter table clientes add column etiquetas text[] not null default '{}' check (etiquetas_ok(etiquetas));
create index on clientes using gin (etiquetas);
grant insert (etiquetas) on clientes to authenticated;
grant update (etiquetas) on clientes to authenticated;

create table campanhas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  nome text not null check (length(nome) between 2 and 60),
  mensagem text not null check (length(mensagem) between 10 and 500),
  etiquetas text[] not null default '{}' check (etiquetas_ok(etiquetas)),   -- vazio = todas as clientes
  sumidas_dias int check (sumidas_dias between 30 and 730),                -- só quem não vem há tantos dias
  total int not null default 0,
  criada_por uuid default auth.uid(),
  criada_em timestamptz not null default now(),
  disparada_em timestamptz
);
create index on campanhas (salao_id, criada_em desc);
alter table campanhas enable row level security;
create policy camp_ler on campanhas for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy camp_criar on campanhas for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy camp_apagar on campanhas for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin' and disparada_em is null);
revoke all on campanhas from anon, authenticated;
grant select, delete on campanhas to authenticated;
grant insert (nome, mensagem, etiquetas, sumidas_dias) on campanhas to authenticated;

-- Quem recebe: aceitou mensagens, não pediu PARAR, não está bloqueada; com etiqueta (se houver) e sumida (se pedido).
create function publico_campanha(p_salao uuid, p_etiquetas text[], p_sumidas_dias int) returns setof uuid
language sql stable security definer set search_path = public, pg_temp as
$$
  select c.id from clientes c
  where c.salao_id = p_salao and cliente_contatavel(c) and not c.bloqueada
    and (cardinality(coalesce(p_etiquetas, '{}')) = 0 or c.etiquetas && p_etiquetas)
    and (p_sumidas_dias is null or not exists (
      select 1 from agendamentos a where a.cliente_id = c.id and a.status not in ('cancelado', 'faltou')
        and a.inicio > now() - make_interval(days => p_sumidas_dias)))
$$;
revoke all on function publico_campanha(uuid, text[], int) from public, anon, authenticated;

create function contar_publico_campanha(p_etiquetas text[], p_sumidas_dias int) returns int
language plpgsql stable security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador faz campanhas' using errcode = '42501'; end if;
  return (select count(*) from publico_campanha(meu_salao(), p_etiquetas, p_sumidas_dias));
end
$$;
revoke all on function contar_publico_campanha(text[], int) from public, anon;
grant execute on function contar_publico_campanha(text[], int) to authenticated;

alter table avisos drop constraint avisos_tipo_check;
alter table avisos add constraint avisos_tipo_check check (tipo in ('retorno', 'vaga', 'avaliacao', 'aniversario', 'campanha'));

-- Dispara: uma campanha por dia no máximo (protege o número do salão de bloqueio por excesso), até 2.000 clientes.
create function disparar_campanha(p_id uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v campanhas;
  v_n int;
begin
  if meu_papel() is distinct from 'admin' then raise exception 'só o administrador faz campanhas' using errcode = '42501'; end if;
  select * into v from campanhas where id = p_id and salao_id = meu_salao() for update;
  if v.id is null then raise exception 'campanha não encontrada' using errcode = 'P0002'; end if;
  if v.disparada_em is not null then raise exception 'campanha_ja_disparada' using errcode = '23505'; end if;
  if exists (select 1 from campanhas where salao_id = v.salao_id and disparada_em > now() - interval '24 hours') then
    raise exception 'uma_campanha_por_dia' using errcode = '54000';
  end if;
  insert into avisos (salao_id, cliente_id, tipo, chave, dados, enviar_em)
  select v.salao_id, x.id, 'campanha', 'camp:' || v.id || ':' || x.id, jsonb_build_object('campanha_id', v.id, 'texto', v.mensagem),
         now() + make_interval(secs => (row_number() over () / 30) * 60)
  from (select p.id from publico_campanha(v.salao_id, v.etiquetas, v.sumidas_dias) as p(id) limit 2000) x
  on conflict (salao_id, chave) do nothing;
  get diagnostics v_n = row_count;
  update campanhas set disparada_em = now(), total = v_n where id = v.id;
  return v_n;
end
$$;
revoke all on function disparar_campanha(uuid) from public, anon;
grant execute on function disparar_campanha(uuid) to authenticated;

-- ───────────── vitrine pública: fotos, descrição e avaliações ─────────────
alter table saloes add column descricao text check (length(descricao) <= 600);
alter table saloes add column instagram text check (instagram ~ '^[A-Za-z0-9._]{1,30}$');
alter table saloes add column vitrine_ativa boolean not null default true;
grant update (descricao, instagram, vitrine_ativa) on saloes to authenticated;

create table vitrine_fotos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  caminho text not null check (length(caminho) between 5 and 300),
  legenda text check (length(legenda) <= 80),
  foto_cliente_id uuid references fotos_cliente (id) on delete cascade,   -- veio da ficha de uma cliente (que autorizou)
  criado_em timestamptz not null default now()
);
create index on vitrine_fotos (salao_id, criado_em desc);
create trigger foto_na_pasta before insert or update on vitrine_fotos for each row execute function foto_na_pasta();
alter table vitrine_fotos enable row level security;
create policy vit_ler on vitrine_fotos for select to authenticated using (salao_id = (select meu_salao()));
create policy vit_criar on vitrine_fotos for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao') and foto_cliente_id is null);
create policy vit_apagar on vitrine_fotos for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao'));
revoke all on vitrine_fotos from anon, authenticated;
grant select, delete on vitrine_fotos to authenticated;
grant insert (caminho, legenda) on vitrine_fotos to authenticated;

-- No máximo 40 fotos na vitrine.
create function limite_vitrine() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if (select count(*) from vitrine_fotos where salao_id = new.salao_id) >= 40 then raise exception 'vitrine_cheia' using errcode = '54000'; end if;
  return new;
end
$$;
revoke execute on function limite_vitrine() from public, anon, authenticated;
create trigger limite_vitrine before insert on vitrine_fotos for each row execute function limite_vitrine();

-- Foto da ficha vai para a vitrine só com a autorização de uso de imagem da cliente.
create function publicar_foto_cliente(p_foto uuid, p_legenda text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  f fotos_cliente;
  v_id uuid;
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'sem permissão' using errcode = '42501'; end if;
  select * into f from fotos_cliente where id = p_foto and salao_id = meu_salao();
  if f.id is null then raise exception 'foto não encontrada' using errcode = 'P0002'; end if;
  if not exists (select 1 from clientes where id = f.cliente_id and consentimento_imagem_em is not null) then
    raise exception 'sem_autorizacao_imagem' using errcode = '42501';
  end if;
  select id into v_id from vitrine_fotos where foto_cliente_id = f.id;
  if v_id is not null then return v_id; end if;
  insert into vitrine_fotos (salao_id, caminho, legenda, foto_cliente_id) values (f.salao_id, f.caminho, left(nullif(trim(p_legenda), ''), 80), f.id) returning id into v_id;
  return v_id;
end
$$;
revoke all on function publicar_foto_cliente(uuid, text) from public, anon;
grant execute on function publicar_foto_cliente(uuid, text) to authenticated;

-- Retirar a autorização de imagem tira as fotos dela da vitrine.
create function vitrine_sem_autorizacao() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if old.consentimento_imagem_em is not null and new.consentimento_imagem_em is null then
    delete from vitrine_fotos v using fotos_cliente f where v.foto_cliente_id = f.id and f.cliente_id = new.id;
  end if;
  return null;
end
$$;
revoke execute on function vitrine_sem_autorizacao() from public, anon, authenticated;
create trigger vitrine_sem_autorizacao after update of consentimento_imagem_em on clientes for each row execute function vitrine_sem_autorizacao();

-- O comentário só aparece na página do salão se a cliente deixar.
alter table avaliacoes add column publica boolean not null default false;
grant select (publica) on avaliacoes to authenticated;
drop function responder_avaliacao(text, int, text);
create function responder_avaliacao(p_token text, p_nota int, p_comentario text, p_publica boolean default false) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  a avaliacoes;
begin
  select * into a from avaliacoes where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if a.id is null then return 'nao_encontrada'; end if;
  if a.respondida_em is not null then return 'ja_respondida'; end if;
  if a.criado_em < now() - interval '15 days' then return 'expirada'; end if;
  if p_nota is null or p_nota not between 0 and 10 then return 'invalida'; end if;
  update avaliacoes set nota = p_nota, comentario = left(nullif(trim(p_comentario), ''), 1000), respondida_em = now(),
    publica = coalesce(p_publica, false) and nullif(trim(p_comentario), '') is not null
  where id = a.id;
  return 'respondida';
end
$$;
revoke all on function responder_avaliacao(text, int, text, boolean) from public, anon, authenticated;
grant execute on function responder_avaliacao(text, int, text, boolean) to service_role;

-- ───────────── avisos para a equipe (no sistema e no WhatsApp do profissional) ─────────────
alter table membros add column telefone text check (telefone ~ '^[0-9]{10,13}$');
alter table membros add column avisos_whatsapp boolean not null default false;
grant update (telefone, avisos_whatsapp) on membros to authenticated;

create table avisos_equipe (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  membro_id uuid not null,
  agendamento_id uuid,
  tipo text not null check (tipo in ('novo', 'mudou', 'cancelou')),
  dados jsonb not null default '{}',
  criado_em timestamptz not null default now(),
  lido_em timestamptz,
  whatsapp text not null default 'nao' check (whatsapp in ('nao', 'pendente', 'enviando', 'enviado', 'falhou')),
  tentativas int not null default 0,
  reservado_em timestamptz,
  wa_msg_id text,
  erro text check (length(erro) <= 500),
  foreign key (membro_id, salao_id) references membros (user_id, salao_id) on delete cascade
);
create index on avisos_equipe (membro_id, criado_em desc);
create index on avisos_equipe (criado_em) where whatsapp in ('pendente', 'enviando');
alter table avisos_equipe enable row level security;
create policy aveq_ler on avisos_equipe for select to authenticated using (membro_id = (select auth.uid()) and salao_id = (select meu_salao()));
create policy aveq_marcar on avisos_equipe for update to authenticated using (membro_id = (select auth.uid()) and salao_id = (select meu_salao()));
revoke all on avisos_equipe from anon, authenticated;
grant select (id, salao_id, membro_id, agendamento_id, tipo, dados, criado_em, lido_em) on avisos_equipe to authenticated;
grant update (lido_em) on avisos_equipe to authenticated;

create function avisar_membro(p_membro uuid, a agendamentos, p_tipo text, p_antigo timestamptz) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  m membros;
  v_lote text := coalesce(a.serie_id, a.grupo_id)::text;   -- série que se repete ou visita com vários serviços: um WhatsApp só
begin
  if p_membro = auth.uid() then return; end if;   -- quem mexeu na própria agenda não precisa de aviso
  select * into m from membros where user_id = p_membro and salao_id = a.salao_id and ativo;
  if m.user_id is null then return; end if;
  insert into avisos_equipe (salao_id, membro_id, agendamento_id, tipo, dados, whatsapp)
  values (a.salao_id, p_membro, a.id, p_tipo,
    jsonb_build_object('cliente', (select nome from clientes where id = a.cliente_id),
                       'servico', (select nome from servicos where id = a.servico_id),
                       'inicio', a.inicio, 'inicio_antigo', p_antigo, 'lote', v_lote),
    case when m.avisos_whatsapp and m.telefone is not null
          and not (v_lote is not null and exists (select 1 from avisos_equipe e where e.membro_id = p_membro and e.tipo = p_tipo
                     and e.dados ->> 'lote' = v_lote and e.criado_em > now() - interval '2 minutes'))
         then 'pendente' else 'nao' end);
end
$$;
revoke execute on function avisar_membro(uuid, agendamentos, text, timestamptz) from public, anon, authenticated;

-- Horário online esperando o sinal só vira aviso quando o sinal é pago (se não pagar, nem chega a aparecer).
create function avisar_equipe() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_novo_ativo boolean := new.status in ('agendado', 'confirmado') and not (new.origem = 'online' and new.status = 'agendado');
  v_velho_ativo boolean;
begin
  if new.inicio < now() - interval '1 hour' then return null; end if;
  if tg_op = 'INSERT' then
    if v_novo_ativo then perform avisar_membro(new.profissional_id, new, 'novo', null); end if;
    return null;
  end if;
  v_velho_ativo := old.status in ('agendado', 'confirmado') and not (old.origem = 'online' and old.status = 'agendado');
  if v_velho_ativo and not v_novo_ativo then
    if new.status = 'cancelado' then perform avisar_membro(old.profissional_id, new, 'cancelou', null); end if;
  elsif v_novo_ativo and not v_velho_ativo then
    if old.status in ('agendado', 'confirmado') then perform avisar_membro(new.profissional_id, new, 'novo', null); end if;
  elsif v_novo_ativo then
    if new.profissional_id <> old.profissional_id then
      perform avisar_membro(old.profissional_id, old, 'cancelou', null);
      perform avisar_membro(new.profissional_id, new, 'novo', null);
    elsif new.inicio <> old.inicio then
      perform avisar_membro(new.profissional_id, new, 'mudou', old.inicio);
    end if;
  end if;
  return null;
end
$$;
revoke execute on function avisar_equipe() from public, anon, authenticated;
create trigger avisar_equipe after insert or update of inicio, profissional_id, status on agendamentos for each row execute function avisar_equipe();

create function reservar_avisos_equipe(p_limite int) returns table (
  id uuid, salao_id uuid, tipo text, dados jsonb, wa_id text, membro_nome text, fuso text
)
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update avisos_equipe a set tentativas = a.tentativas + 1, whatsapp = case when a.tentativas + 1 >= 3 then 'falhou' else 'pendente' end
  where a.whatsapp = 'enviando' and a.reservado_em < now() - interval '15 minutes';
  -- aviso velho não serve mais
  update avisos_equipe a set whatsapp = 'falhou', erro = 'passou da hora' where a.whatsapp = 'pendente' and a.criado_em < now() - interval '6 hours';
  return query
  with alvo as (
    select v.id from avisos_equipe v where v.whatsapp = 'pendente' and v.tentativas < 3 order by v.criado_em limit p_limite for update skip locked
  ), marcado as (
    update avisos_equipe v set whatsapp = 'enviando', reservado_em = now() from alvo where v.id = alvo.id returning v.*
  )
  select m.id, m.salao_id, m.tipo, m.dados, '55' || tel_nacional(mb.telefone), mb.nome, s.fuso
  from marcado m join membros mb on mb.user_id = m.membro_id and mb.salao_id = m.salao_id join saloes s on s.id = m.salao_id;
end
$$;
create function concluir_aviso_equipe(p_id uuid, p_ok boolean, p_wa_msg_id text, p_erro text) returns void
language sql security definer set search_path = public, pg_temp as
$$
  update avisos_equipe set whatsapp = case when p_ok then 'enviado' when tentativas + 1 >= 3 then 'falhou' else 'pendente' end,
    tentativas = tentativas + case when p_ok then 0 else 1 end, wa_msg_id = p_wa_msg_id, erro = left(p_erro, 500)
  where id = p_id
$$;
revoke all on function reservar_avisos_equipe(int), concluir_aviso_equipe(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function reservar_avisos_equipe(int), concluir_aviso_equipe(uuid, boolean, text, text) to service_role;

-- ───────────── nota fiscal de serviço (NFS-e) ─────────────
create table fiscal_salao (
  salao_id uuid primary key default meu_salao() references saloes (id) on delete cascade,
  cnpj text check (cnpj ~ '^[0-9]{14}$'),
  razao_social text check (length(razao_social) between 2 and 150),
  inscricao_municipal text check (inscricao_municipal ~ '^[0-9A-Za-z./-]{1,20}$'),
  codigo_municipio text check (codigo_municipio ~ '^[0-9]{7}$'),   -- código IBGE da cidade
  item_lista_servico text check (item_lista_servico ~ '^[0-9]{2}\.?[0-9]{2}$'),   -- 06.01 = cabeleireiros, manicures e afins
  codigo_tributario_municipio text check (length(codigo_tributario_municipio) <= 20),
  aliquota numeric(5, 2) check (aliquota between 0 and 5),
  simples_nacional boolean not null default true,
  ambiente text not null default 'homologacao' check (ambiente in ('homologacao', 'producao')),
  token_emissor text check (length(token_emissor) between 10 and 200),   -- segredo do emissor: só o servidor lê
  ativo boolean not null default false,
  atualizado_em timestamptz not null default now()
);
alter table fiscal_salao enable row level security;
create policy fiscal_ler on fiscal_salao for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy fiscal_criar on fiscal_salao for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy fiscal_editar on fiscal_salao for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on fiscal_salao from anon, authenticated;
grant select (salao_id, cnpj, razao_social, inscricao_municipal, codigo_municipio, item_lista_servico, codigo_tributario_municipio, aliquota, simples_nacional, ambiente, ativo, atualizado_em) on fiscal_salao to authenticated;
grant insert (cnpj, razao_social, inscricao_municipal, codigo_municipio, item_lista_servico, codigo_tributario_municipio, aliquota, simples_nacional, ambiente, token_emissor, ativo) on fiscal_salao to authenticated;
grant update (cnpj, razao_social, inscricao_municipal, codigo_municipio, item_lista_servico, codigo_tributario_municipio, aliquota, simples_nacional, ambiente, token_emissor, ativo, atualizado_em) on fiscal_salao to authenticated;

-- A tela só precisa saber se já existe token (o valor nunca volta para o navegador).
create function fiscal_tem_token() returns boolean
language sql stable security definer set search_path = public, pg_temp as
$$ select exists (select 1 from fiscal_salao where salao_id = meu_salao() and meu_papel() = 'admin' and token_emissor is not null) $$;
revoke all on function fiscal_tem_token() from public, anon;
grant execute on function fiscal_tem_token() to authenticated;

-- As notas são escritas só pelo servidor (que fala com o emissor); a equipe lê.
create table notas_fiscais (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  comanda_id uuid not null,
  ref text not null unique check (length(ref) between 8 and 60),
  status text not null default 'processando' check (status in ('processando', 'autorizada', 'erro', 'cancelada')),
  ambiente text not null check (ambiente in ('homologacao', 'producao', 'simulacao')),
  numero text,
  codigo_verificacao text,
  valor_centavos int not null check (valor_centavos > 0),
  tomador_nome text,
  tomador_documento text check (tomador_documento ~ '^([0-9]{11}|[0-9]{14})$'),
  url_pdf text check (url_pdf ~ '^https://'),
  url_xml text check (url_xml ~ '^https://'),
  mensagem text check (length(mensagem) <= 1000),
  emitida_por uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  foreign key (comanda_id, salao_id) references comandas (id, salao_id) on delete cascade
);
create unique index notas_uma_valida on notas_fiscais (comanda_id) where status in ('processando', 'autorizada');
create index on notas_fiscais (salao_id, criado_em desc);
alter table notas_fiscais enable row level security;
-- Comanda com nota emitida (ou em emissão) não reabre: primeiro cancela a nota.
create function comanda_com_nota() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if old.status = 'fechada' and new.status <> 'fechada'
     and exists (select 1 from notas_fiscais where comanda_id = new.id and status in ('processando', 'autorizada')) then
    raise exception 'comanda_com_nota' using errcode = '55000';
  end if;
  return new;
end
$$;
revoke execute on function comanda_com_nota() from public, anon, authenticated;
create trigger comanda_com_nota before update of status on comandas for each row execute function comanda_com_nota();
create policy notas_ler on notas_fiscais for select to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) in ('admin', 'recepcao'));
revoke all on notas_fiscais from anon, authenticated;
grant select on notas_fiscais to authenticated;

-- ───────────── termos com assinatura digital ─────────────
create table termos_modelos (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  tipo text not null check (tipo in ('quimica', 'imagem', 'outro')),
  titulo text not null check (length(titulo) between 3 and 80),
  texto text not null check (length(texto) between 20 and 8000),
  atualizado_em timestamptz not null default now(),
  unique (salao_id, titulo)
);
alter table termos_modelos enable row level security;
create policy tmod_ler on termos_modelos for select to authenticated using (salao_id = (select meu_salao()));
create policy tmod_criar on termos_modelos for insert to authenticated with check (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy tmod_editar on termos_modelos for update to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
create policy tmod_apagar on termos_modelos for delete to authenticated using (salao_id = (select meu_salao()) and (select meu_papel()) = 'admin');
revoke all on termos_modelos from anon, authenticated;
grant select, delete on termos_modelos to authenticated;
grant insert (tipo, titulo, texto) on termos_modelos to authenticated;
grant update (titulo, texto, atualizado_em) on termos_modelos to authenticated;

-- Cada termo guarda o texto exatamente como estava na hora (com o hash), quem assinou, a assinatura, IP e aparelho.
create table termos_assinados (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null references saloes (id) on delete cascade,
  cliente_id uuid not null,
  tipo text not null check (tipo in ('quimica', 'imagem', 'outro')),
  titulo text not null check (length(titulo) between 3 and 80),
  texto text not null check (length(texto) between 20 and 8000),
  texto_hash text not null,
  token_hash text not null unique,
  expira_em timestamptz not null default now() + interval '7 days',
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  assinado_em timestamptz,
  nome_assinado text check (length(nome_assinado) between 3 and 120),
  documento text check (documento ~ '^[0-9]{11}$'),
  respostas jsonb,
  assinatura text check (assinatura ~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' and length(assinatura) <= 400000),
  ip text check (length(ip) <= 64),
  aparelho text check (length(aparelho) <= 300),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on termos_assinados (cliente_id, criado_em desc);
alter table termos_assinados enable row level security;
create policy tass_ler on termos_assinados for select to authenticated using (salao_id = (select meu_salao()));
revoke all on termos_assinados from anon, authenticated;
grant select (id, salao_id, cliente_id, tipo, titulo, texto, texto_hash, expira_em, criado_por, criado_em, assinado_em, nome_assinado, documento, respostas, assinatura, ip, aparelho) on termos_assinados to authenticated;

-- Cria o link de assinatura (segredo aleatório; só o hash fica no banco).
create function criar_termo(p_cliente uuid, p_tipo text, p_titulo text, p_texto text) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_salao uuid := meu_salao();
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not exists (select 1 from clientes where id = p_cliente and salao_id = v_salao) then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
  insert into termos_assinados (salao_id, cliente_id, tipo, titulo, texto, texto_hash, token_hash)
  values (v_salao, p_cliente, p_tipo, p_titulo, p_texto, encode(sha256(convert_to(p_texto, 'UTF8')), 'hex'), encode(sha256(convert_to(v_token, 'UTF8')), 'hex'));
  return v_token;
end
$$;
revoke all on function criar_termo(uuid, text, text, text) from public, anon;
grant execute on function criar_termo(uuid, text, text, text) to authenticated;

create function termo_publico(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'cliente', c.nome, 'tipo', t.tipo, 'titulo', t.titulo, 'texto', t.texto,
    'assinado', t.assinado_em is not null, 'assinado_em', t.assinado_em, 'expirado', t.expira_em < now() and t.assinado_em is null)
  from termos_assinados t join clientes c on c.id = t.cliente_id join saloes s on s.id = t.salao_id
  where t.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;

create function assinar_termo(p_token text, p_nome text, p_documento text, p_respostas jsonb, p_assinatura text, p_ip text, p_aparelho text) returns text
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  t termos_assinados;
begin
  select * into t from termos_assinados where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if t.id is null then return 'nao_encontrado'; end if;
  if t.assinado_em is not null then return 'ja_assinado'; end if;
  if t.expira_em < now() then return 'expirado'; end if;
  if length(trim(coalesce(p_nome, ''))) < 3 or coalesce(p_assinatura, '') !~ '^data:image/png;base64,' then return 'invalido'; end if;
  update termos_assinados set assinado_em = now(), nome_assinado = left(trim(p_nome), 120), documento = nullif(p_documento, ''),
    respostas = p_respostas, assinatura = p_assinatura, ip = left(p_ip, 64), aparelho = left(p_aparelho, 300)
  where id = t.id;
  if t.tipo = 'imagem' then
    update clientes set consentimento_imagem_em = coalesce(consentimento_imagem_em, now()) where id = t.cliente_id;
  end if;
  return 'assinado';
end
$$;
revoke all on function termo_publico(text), assinar_termo(text, text, text, jsonb, text, text, text) from public, anon, authenticated;
grant execute on function termo_publico(text), assinar_termo(text, text, text, jsonb, text, text, text) to service_role;

-- ───────────── unir cadastros: leva também fila, termos, etiquetas e marcações ─────────────
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
  update fila_atendimento set cliente_id = a.id where cliente_id = b.id;
  update termos_assinados set cliente_id = a.id where cliente_id = b.id;
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
