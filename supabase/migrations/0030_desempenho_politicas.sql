-- Belezando · desempenho das regras de acesso (RLS).
-- meu_salao(), meu_papel() e auth.uid() dentro de "(select ...)" são calculados uma vez por consulta, não uma vez por linha.
-- Com milhares de agendamentos e comandas, isso é a diferença entre a tela abrir na hora ou demorar.
do $$
declare
  p record;
  usar text;
  conferir text;
  troca constant text[] := array['meu_salao()', 'meu_papel()', 'auth.uid()'];
  f text;
begin
  for p in select schemaname, tablename, policyname, qual, with_check from pg_policies where schemaname = 'public' loop
    usar := p.qual;
    conferir := p.with_check;
    foreach f in array troca loop
      -- só o que ainda não está dentro de um select
      usar := regexp_replace(usar, '(?<![Ss][Ee][Ll][Ee][Cc][Tt] )' || replace(replace(f, '(', '\('), ')', '\)'), '(select ' || f || ')', 'g');
      conferir := regexp_replace(conferir, '(?<![Ss][Ee][Ll][Ee][Cc][Tt] )' || replace(replace(f, '(', '\('), ')', '\)'), '(select ' || f || ')', 'g');
    end loop;
    if usar is distinct from p.qual then
      execute format('alter policy %I on %I.%I using (%s)', p.policyname, p.schemaname, p.tablename, usar);
    end if;
    if conferir is distinct from p.with_check then
      execute format('alter policy %I on %I.%I with check (%s)', p.policyname, p.schemaname, p.tablename, conferir);
    end if;
  end loop;
end $$;

-- Tabela de tentativas ganha chave primária (o Supabase recomenda; ajuda na limpeza).
alter table tentativas add column id bigint generated always as identity primary key;
