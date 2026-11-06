-- Função das etiquetas com search_path fixo (aviso do Supabase).
alter function etiquetas_ok(text[]) set search_path = public, pg_temp;
