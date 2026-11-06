import { createClient } from "@supabase/supabase-js";

/**
 * Cliente com a chave de serviço: ignora as regras de acesso do banco. Só no servidor (ações, rotas e páginas públicas),
 * e toda consulta com ele precisa filtrar pelo salão certo. Nunca importe em componente de cliente.
 */
export function clienteAdmin() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
