// Sends pending refunds back through the provider. See handler.ts.

import { createPaystackRefund } from '../_shared/paystack.ts';
import { adminClient, userFromRequest } from '../_shared/supabase.ts';
import { handleProcessRefund } from './handler.ts';

Deno.serve((req) => handleProcessRefund(req, adminClient, userFromRequest, createPaystackRefund));
