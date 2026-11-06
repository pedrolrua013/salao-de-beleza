-- A ficha só pede a data de nascimento quando o cadastro ainda não tem (quem marcou sozinha pelo link ou WhatsApp).
create or replace function ficha_publica(p_token text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as
$$
  select jsonb_build_object('salao', s.nome, 'slug', s.slug, 'cliente', split_part(c.nome, ' ', 1), 'respondida', f.respondida_em is not null,
    'expirada', f.expira_em < now() and f.respondida_em is null, 'pedir_nascimento', c.nascimento is null)
  from fichas_previas f join clientes c on c.id = f.cliente_id join saloes s on s.id = f.salao_id
  where f.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;
