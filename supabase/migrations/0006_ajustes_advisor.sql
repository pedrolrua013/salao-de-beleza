-- Belezando · ajustes apontados pelos avisos de segurança e desempenho do Supabase (24/10/2026).

-- 1) Funções de gatilho não são chamadas pela API: ninguém, além do dono, precisa executá-las.
revoke execute on function auditar(), limitar_agendamentos_whatsapp()
  from public, anon, authenticated;
revoke execute on function trg_lembretes_agendamento(), trg_lembretes_cliente(), trg_lembretes_salao()
  from public, anon, authenticated;

-- 2) search_path fixo nas funções que ainda não tinham.
alter function tel_nacional(text) set search_path = public, pg_temp;

-- 3) Índices nas chaves estrangeiras compostas (acelera exclusões em cascata e junções).
create index on agendamentos (cliente_id, salao_id);
create index on agendamentos (profissional_id, salao_id);
create index on agendamentos (servico_id, salao_id);
create index on conversas (cliente_id, salao_id);
create index on lembretes (salao_id);
create index on lembretes (agendamento_id, salao_id);
create index on mensagens (conversa_id, salao_id);
