import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { requireEnv } from './http.ts';

// Service-role client: bypasses RLS. Only use it inside Edge Functions.
export function adminClient() {
  return createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  });
}

export async function userFromRequest(req: Request) {
  const token = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (!token) return null;
  const { data } = await adminClient().auth.getUser(token);
  return data.user ?? null;
}
