// Texts new booking confirmations and reminders to customers. See handler.ts.

import { sendSms } from '../_shared/africastalking.ts';
import { adminClient } from '../_shared/supabase.ts';
import { handleSendSms } from './handler.ts';

Deno.serve((req) => handleSendSms(req, adminClient, sendSms));
