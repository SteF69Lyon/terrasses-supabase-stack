// Edge Function: live-token
// Mint un accès à Gemini Live API pour un client authentifié.
// Port direct de l'ancienne Cloud Function geminiLiveToken.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, jsonResponse, errorResponse } from '../_shared/ai-router.ts';

const handler = async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST' && req.method !== 'GET') return errorResponse(405, 'GET/POST only');

  // Vérifie le JWT utilisateur via header Authorization
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return errorResponse(401, 'Connexion requise pour accéder à l\'assistant vocal.');
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) {
    return errorResponse(401, 'Connexion requise pour accéder à l\'assistant vocal.');
  }

  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) return errorResponse(500, 'Clé API non configurée.');

  return jsonResponse({ apiKey });
};

Deno.serve(handler);
export default handler;
