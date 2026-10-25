// Receives Paystack webhooks. See handler.ts.

import { adminClient } from '../_shared/supabase.ts';
import { handlePaystackWebhook } from './handler.ts';

Deno.serve((req) => handlePaystackWebhook(req, adminClient));
