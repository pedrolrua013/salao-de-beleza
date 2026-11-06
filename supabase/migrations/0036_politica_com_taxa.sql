-- A política que a cliente aceita no link já mostra a taxa por falta; o registro do aceite passa a guardar o mesmo texto.
create function politica_com_taxa() returns trigger
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  v_taxa int;
begin
  select taxa_falta_centavos into v_taxa from saloes where id = new.salao_id;
  if v_taxa > 0 and position('Falta sem aviso' in new.texto) = 0 then
    new.texto := new.texto || ' Falta sem aviso: taxa de R$ ' || replace(to_char(v_taxa / 100.0, 'FM999990.00'), '.', ',') || ' cobrada na próxima visita.';
  end if;
  return new;
end
$$;
revoke execute on function politica_com_taxa() from public, anon, authenticated;
create trigger politica_com_taxa before insert on aceites_politica for each row execute function politica_com_taxa();
