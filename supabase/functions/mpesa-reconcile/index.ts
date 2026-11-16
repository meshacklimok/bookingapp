// Settles M-Pesa payments whose callback never arrived. See handler.ts.

import { stkQuery } from '../_shared/mpesa.ts';
import { adminClient } from '../_shared/supabase.ts';
import { handleMpesaReconcile } from './handler.ts';

Deno.serve((req) => handleMpesaReconcile(req, adminClient, stkQuery));
