-- Belezando · ficha da cliente: dados de salão, ficha técnica de química, testes de alergia e de mecha, fotos e união de cadastros.
-- A ficha técnica é o que faz a cor sair igual na próxima vez, prova o teste feito e fica com o salão mesmo se o profissional sair.

alter table clientes add column alergias text check (length(alergias) <= 500);
alter table clientes add column tipo_cabelo text check (tipo_cabelo in ('liso', 'ondulado', 'cacheado', 'crespo'));
alter table clientes add column preferencias text check (length(preferencias) <= 1000);
alter table clientes add column origem text check (origem in ('indicacao', 'instagram', 'google', 'whatsapp', 'passante', 'facebook', 'tiktok', 'outro'));
alter table clientes add column indicado_por uuid;
alter table clientes add column consentimento_imagem_em timestamptz;   -- uso de fotos antes/depois no portfólio do salão
alter table clientes add constraint indicado_ok foreign key (indicado_por, salao_id) references clientes (id, salao_id) on delete set null (indicado_por);
grant insert (alergias, tipo_cabelo, preferencias, origem, indicado_por) on clientes to authenticated;
grant update (alergias, tipo_cabelo, preferencias, origem, indicado_por) on clientes to authenticated;

-- Fórmula: lista de {"zona": "raiz", "produto": "Koleston 7.1", "gramas": 30, "oxidante": 20, "oxidante_gramas": 45}.
create function formula_valida(f jsonb) returns boolean
language sql immutable set search_path = public, pg_temp as
$$
  select jsonb_typeof(f) = 'array' and jsonb_array_length(f) <= 20
    and not exists (select 1 from jsonb_array_elements(f) e
                    where jsonb_typeof(e) <> 'object' or coalesce(length(e ->> 'produto'), 0) not between 1 and 120
                       or length(coalesce(e ->> 'zona', '')) > 60)
$$;
revoke all on function formula_valida(jsonb) from public, anon;
grant execute on function formula_valida(jsonb) to authenticated, service_role;

create table fichas_tecnicas (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  agendamento_id uuid,
  profissional_id uuid default auth.uid(),
  data date not null default current_date,
  servico text not null check (length(servico) between 2 and 120),
  tecnica text check (length(tecnica) <= 200),        -- ex.: mechas no papel, babylights, retoque de raiz
  formula jsonb not null default '[]' check (formula_valida(formula)),
  pausa_min int check (pausa_min between 0 and 240),
  resultado text check (length(resultado) <= 1000),
  observacoes text check (length(observacoes) <= 2000),
  criado_em timestamptz not null default now(),
  unique (id, salao_id),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (agendamento_id, salao_id) references agendamentos (id, salao_id) on delete set null (agendamento_id),
  foreign key (profissional_id, salao_id) references membros (user_id, salao_id)
);
create index on fichas_tecnicas (cliente_id, data desc);
create index on fichas_tecnicas (salao_id);

-- Testes de alergia (toque) e de mecha: data e resultado guardados são a prova de que o salão fez o teste.
create table testes_cliente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  tipo text not null check (tipo in ('alergia', 'mecha')),
  produto text not null check (length(produto) between 2 and 120),
  resultado text not null check (resultado in ('sem_reacao', 'reacao', 'nao_recomendado', 'aprovado')),
  feito_em date not null default current_date,
  observacoes text check (length(observacoes) <= 500),
  registrado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade
);
create index on testes_cliente (cliente_id, feito_em desc);

-- Fotos ficam no Storage (balde "fotos", pasta <salao_id>/); aqui só o caminho.
create table fotos_cliente (
  id uuid primary key default gen_random_uuid(),
  salao_id uuid not null default meu_salao() references saloes (id) on delete cascade,
  cliente_id uuid not null,
  ficha_id uuid,
  momento text not null check (momento in ('antes', 'depois', 'referencia')),
  caminho text not null check (length(caminho) between 5 and 300),
  enviado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  foreign key (cliente_id, salao_id) references clientes (id, salao_id) on delete cascade,
  foreign key (ficha_id, salao_id) references fichas_tecnicas (id, salao_id) on delete set null (ficha_id)
);
create index on fotos_cliente (cliente_id, criado_em desc);

-- O caminho da foto precisa estar na pasta do próprio salão.
create function foto_na_pasta() returns trigger
language plpgsql set search_path = public, pg_temp as
$$
begin
  if split_part(new.caminho, '/', 1) <> new.salao_id::text then raise exception 'caminho fora da pasta do salão' using errcode = '42501'; end if;
  return new;
end
$$;
create trigger foto_na_pasta before insert or update on fotos_cliente for each row execute function foto_na_pasta();
revoke execute on function foto_na_pasta() from public, anon, authenticated;

alter table fichas_tecnicas enable row level security;
alter table testes_cliente enable row level security;
alter table fotos_cliente enable row level security;

-- A equipe toda lê (a recepção prepara o atendimento); quem atende escreve; só o administrador apaga.
create policy fichas_ler on fichas_tecnicas for select to authenticated using (salao_id = meu_salao());
create policy fichas_criar on fichas_tecnicas for insert to authenticated with check (salao_id = meu_salao());
create policy fichas_editar on fichas_tecnicas for update to authenticated
  using (salao_id = meu_salao() and (meu_papel() = 'admin' or profissional_id = auth.uid())) with check (salao_id = meu_salao());
create policy fichas_apagar on fichas_tecnicas for delete to authenticated using (salao_id = meu_salao() and meu_papel() = 'admin');
create policy testes_ler on testes_cliente for select to authenticated using (salao_id = meu_salao());
create policy testes_criar on testes_cliente for insert to authenticated with check (salao_id = meu_salao());
create policy fotos_ler on fotos_cliente for select to authenticated using (salao_id = meu_salao());
create policy fotos_criar on fotos_cliente for insert to authenticated with check (salao_id = meu_salao());
create policy fotos_apagar on fotos_cliente for delete to authenticated using (salao_id = meu_salao() and (meu_papel() = 'admin' or enviado_por = auth.uid()));

revoke all on fichas_tecnicas, testes_cliente, fotos_cliente from anon, authenticated;
grant select, delete on fichas_tecnicas to authenticated;
grant insert (cliente_id, agendamento_id, profissional_id, data, servico, tecnica, formula, pausa_min, resultado, observacoes) on fichas_tecnicas to authenticated;
grant update (data, servico, tecnica, formula, pausa_min, resultado, observacoes) on fichas_tecnicas to authenticated;
grant select on testes_cliente to authenticated;           -- teste registrado não muda nem some: é prova
grant insert (cliente_id, tipo, produto, resultado, feito_em, observacoes) on testes_cliente to authenticated;
grant select, delete on fotos_cliente to authenticated;
grant insert (cliente_id, ficha_id, momento, caminho) on fotos_cliente to authenticated;

create trigger aud_fichas after insert or update or delete on fichas_tecnicas for each row execute function auditar();
create trigger aud_testes after insert on testes_cliente for each row execute function auditar();
create trigger aud_fotos after insert or delete on fotos_cliente for each row execute function auditar();

-- Aceite de uso de imagem: só por função (fica auditado). Retirar o aceite também é registrado.
create function registrar_aceite_imagem(p_cliente uuid, p_aceita boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  update clientes set consentimento_imagem_em = case when p_aceita then coalesce(consentimento_imagem_em, now()) else null end
  where id = p_cliente and salao_id = meu_salao();
  if not found then raise exception 'cliente não encontrado' using errcode = 'P0002'; end if;
end
$$;
revoke all on function registrar_aceite_imagem(uuid, boolean) from public, anon;
grant execute on function registrar_aceite_imagem(uuid, boolean) to authenticated;

-- Une dois cadastros da mesma pessoa: tudo do duplicado passa para o que fica, e o duplicado some.
create function unir_clientes(p_manter uuid, p_remover uuid) returns void
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
  update comandas set cliente_id = a.id where cliente_id = b.id;
  update conversas set cliente_id = a.id where cliente_id = b.id;
  update fichas_tecnicas set cliente_id = a.id where cliente_id = b.id;
  update testes_cliente set cliente_id = a.id where cliente_id = b.id;
  update fotos_cliente set cliente_id = a.id where cliente_id = b.id;
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
revoke all on function unir_clientes(uuid, uuid) from public, anon;
grant execute on function unir_clientes(uuid, uuid) to authenticated;

-- Storage: balde privado de fotos, cada salão só na própria pasta. Só existe no Supabase (o teste local não tem o schema storage).
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('fotos', 'fotos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
    on conflict (id) do nothing;
    execute $p$create policy fotos_salao_ler on storage.objects for select to authenticated
      using (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.meu_salao()::text)$p$;
    execute $p$create policy fotos_salao_enviar on storage.objects for insert to authenticated
      with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.meu_salao()::text)$p$;
    execute $p$create policy fotos_salao_apagar on storage.objects for delete to authenticated
      using (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.meu_salao()::text)$p$;
  end if;
end $$;
