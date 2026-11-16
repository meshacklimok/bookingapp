// Sends new notifications to the user's phones as push messages. See handler.ts.

import { sendPush } from '../_shared/fcm.ts';
import { adminClient } from '../_shared/supabase.ts';
import { handleSendPush } from './handler.ts';

Deno.serve((req) => handleSendPush(req, adminClient, sendPush));
