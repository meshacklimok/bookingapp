// Receives the Daraja STK Push result. See handler.ts.

import { adminClient } from '../_shared/supabase.ts';
import { handleMpesaCallback } from './handler.ts';

Deno.serve((req) => handleMpesaCallback(req, adminClient));
