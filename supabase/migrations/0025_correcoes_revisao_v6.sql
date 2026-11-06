-- Belezando · correções da sexta revisão.

-- Sinal pago por Pix depois do prazo, com o horário já ocupado por outra cliente: antes dava erro e a recepção não conseguia registrar o pagamento.
create or replace function confirmar_sinal(p_agendamento uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as
$$
begin
  if meu_papel() not in ('admin', 'recepcao') then raise exception 'só administrador ou recepção confirmam sinal' using errcode = '42501'; end if;
  update sinais set status = 'pago', pago_em = now(), confirmado_por = auth.uid()
  where agendamento_id = p_agendamento and salao_id = meu_salao() and status in ('pendente', 'expirado');
  if not found then raise exception 'sinal_nao_encontrado' using errcode = 'P0002'; end if;
  begin
    update agendamentos set status = 'confirmado' where id in (select id from do_grupo(p_agendamento)) and status in ('agendado', 'cancelado');
  exception when exclusion_violation then
    -- pagou depois do prazo e o horário já foi ocupado: o sinal vira crédito
    update sinais set status = 'credito' where agendamento_id = p_agendamento and salao_id = meu_salao();
  end;
end
$$;
