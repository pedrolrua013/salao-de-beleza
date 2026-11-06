-- Endereço da cliente (opcional): atendimento em casa, nota fiscal e "de onde vêm as clientes".
alter table clientes
  add column cep text check (cep ~ '^[0-9]{8}$'),
  add column logradouro text check (char_length(logradouro) <= 200),
  add column numero text check (char_length(numero) <= 20),
  add column complemento text check (char_length(complemento) <= 100),
  add column bairro text check (char_length(bairro) <= 100),
  add column cidade text check (char_length(cidade) <= 100),
  add column uf text check (uf ~ '^[A-Z]{2}$');

grant insert (cep, logradouro, numero, complemento, bairro, cidade, uf) on clientes to authenticated;
grant update (cep, logradouro, numero, complemento, bairro, cidade, uf) on clientes to authenticated;

-- Unir cadastros: o endereço vem inteiro de um dos dois (nunca rua de um com número do outro).
do $$
declare d text;
begin
  d := pg_get_functiondef('unir_clientes(uuid, uuid)'::regprocedure);
  if position('vip = a.vip or b.vip,' in d) = 0 then raise exception 'unir_clientes mudou'; end if;
  d := replace(d, 'vip = a.vip or b.vip,', 'cep = case when a.logradouro is null and a.cep is null then b.cep else a.cep end,
    logradouro = case when a.logradouro is null and a.cep is null then b.logradouro else a.logradouro end,
    numero = case when a.logradouro is null and a.cep is null then b.numero else a.numero end,
    complemento = case when a.logradouro is null and a.cep is null then b.complemento else a.complemento end,
    bairro = case when a.logradouro is null and a.cep is null then b.bairro else a.bairro end,
    cidade = case when a.logradouro is null and a.cep is null then b.cidade else a.cidade end,
    uf = case when a.logradouro is null and a.cep is null then b.uf else a.uf end,
    vip = a.vip or b.vip,');
  execute d;
end
$$;

-- Relatórios: bairros com mais clientes (entre as que têm endereço).
create function bairros_clientes() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as
$$
declare v_salao uuid := meu_salao();
begin
  if not pode('painel') then raise exception 'sem permissão para relatórios' using errcode = '42501'; end if;
  return jsonb_build_object(
    'com_endereco', (select count(*) from clientes where salao_id = v_salao and bairro is not null),
    'total', (select count(*) from clientes where salao_id = v_salao),
    'bairros', (select coalesce(jsonb_agg(jsonb_build_object('bairro', b, 'cidade', c, 'clientes', n) order by n desc, b), '[]') from (
      select min(trim(bairro)) b, min(cidade) c, count(*) n from clientes
      where salao_id = v_salao and nullif(trim(bairro), '') is not null
      group by lower(trim(bairro)), lower(coalesce(cidade, '')) order by 3 desc, 1 limit 10) x)
  );
end
$$;
revoke all on function bairros_clientes() from public, anon;
grant execute on function bairros_clientes() to authenticated;
