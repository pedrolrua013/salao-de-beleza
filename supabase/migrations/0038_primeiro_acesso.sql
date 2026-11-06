-- Primeiro acesso guiado: o salão novo passa por salão, serviços, equipe, clientes e link. Fica marcado quando termina.
alter table saloes add column guia_concluido_em timestamptz;
-- Quem já usa o sistema não precisa do passo a passo.
update saloes set guia_concluido_em = now();
grant update (guia_concluido_em) on saloes to authenticated;
