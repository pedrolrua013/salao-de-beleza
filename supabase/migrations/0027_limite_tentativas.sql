-- Belezando · limite de tentativas (login, cadastro). O login passa pelo servidor do app, então o Supabase
-- vê todas as tentativas vindo do mesmo endereço: o limite por pessoa (endereço e e-mail) fica aqui.

create table tentativas (
  chave text not null check (length(chave) <= 200),
  em timestamptz not null default now()
);
create index on tentativas (chave, em);
alter table tentativas enable row level security;
revoke all on tentativas from anon, authenticated;

-- Registra uma tentativa e diz se ainda está dentro do limite. Só o servidor (chave de serviço) chama.
create function registrar_tentativa(p_chave text, p_limite int, p_janela_min int) returns boolean
language plpgsql security definer set search_path = public, pg_temp as
$$
declare
  n int;
begin
  perform pg_advisory_xact_lock(hashtext(p_chave));
  delete from tentativas where chave = p_chave and em < now() - make_interval(mins => p_janela_min);
  select count(*) into n from tentativas where chave = p_chave;
  if n >= p_limite then return false; end if;
  insert into tentativas (chave) values (left(p_chave, 200));
  return true;
end
$$;
revoke all on function registrar_tentativa(text, int, int) from public, anon, authenticated;
grant execute on function registrar_tentativa(text, int, int) to service_role;

-- Limpeza do que já passou da janela (chamada pelo agendador junto com os lembretes).
create function limpar_tentativas() returns void
language sql security definer set search_path = public, pg_temp as
$$ delete from tentativas where em < now() - interval '1 day' $$;
revoke all on function limpar_tentativas() from public, anon, authenticated;
grant execute on function limpar_tentativas() to service_role;
