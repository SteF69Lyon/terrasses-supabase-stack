// Deno edge-function shared AI router.
// Uses fetch directly against each provider's REST API so we don't need
// NPM SDKs inside the Deno runtime — fewer dependencies and cold-start
// overhead, smaller attack surface.
//
// Fallback chain: Claude Sonnet → GPT-4o-mini → Gemini 2.5 Flash.

export type AIMessage =
  | { role: 'assistant'; content: string }
  | { role: 'user'; content: string };

export type AIRequest = {
  system?: string;
  messages: AIMessage[];
  temperature?: number;
  maxTokens?: number;
};

export type ProviderId = 'anthropic' | 'openai' | 'google';

export type AIResponse = {
  text: string;
  provider: ProviderId;
  model: string;
  latencyMs: number;
};

export class AIProviderError extends Error {
  constructor(
    public readonly provider: ProviderId,
    message: string
  ) {
    super(`[${provider}] ${message}`);
    this.name = 'AIProviderError';
  }
}

type Provider = {
  id: ProviderId;
  model: string;
  isAvailable: boolean;
  call(req: AIRequest): Promise<AIResponse>;
};

// ---------- Anthropic Claude ----------

const CLAUDE_MODEL = 'claude-sonnet-4-5-20250929';

function anthropic(apiKey: string | undefined): Provider {
  return {
    id: 'anthropic',
    model: CLAUDE_MODEL,
    isAvailable: !!apiKey,
    async call(req) {
      if (!apiKey) throw new AIProviderError('anthropic', 'ANTHROPIC_API_KEY not set');
      const started = Date.now();
      const messages = req.messages.map((m) => ({ role: m.role, content: m.content }));

      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model: CLAUDE_MODEL,
          max_tokens: req.maxTokens ?? 1024,
          temperature: req.temperature,
          system: req.system,
          messages,
        }),
      });
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        throw new AIProviderError('anthropic', `HTTP ${res.status}: ${body.slice(0, 200)}`);
      }
      const json = await res.json();
      const text = json?.content?.find((c: { type: string }) => c.type === 'text')?.text?.trim();
      if (!text) throw new AIProviderError('anthropic', 'empty response');
      return { text, provider: 'anthropic', model: CLAUDE_MODEL, latencyMs: Date.now() - started };
    },
  };
}

// ---------- OpenAI ----------

const OPENAI_MODEL = 'gpt-4o-mini';

function openai(apiKey: string | undefined): Provider {
  return {
    id: 'openai',
    model: OPENAI_MODEL,
    isAvailable: !!apiKey,
    async call(req) {
      if (!apiKey) throw new AIProviderError('openai', 'OPENAI_API_KEY not set');
      const started = Date.now();
      const messages: unknown[] = [];
      if (req.system) messages.push({ role: 'system', content: req.system });
      for (const m of req.messages) {
        messages.push({ role: m.role, content: m.content });
      }

      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: OPENAI_MODEL,
          messages,
          temperature: req.temperature,
          max_tokens: req.maxTokens,
        }),
      });
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        throw new AIProviderError('openai', `HTTP ${res.status}: ${body.slice(0, 200)}`);
      }
      const json = await res.json();
      const text = json?.choices?.[0]?.message?.content?.trim();
      if (!text) throw new AIProviderError('openai', 'empty response');
      return { text, provider: 'openai', model: OPENAI_MODEL, latencyMs: Date.now() - started };
    },
  };
}

// ---------- Google Gemini ----------

const GEMINI_MODEL = 'gemini-2.5-flash';

function google(apiKey: string | undefined): Provider {
  return {
    id: 'google',
    model: GEMINI_MODEL,
    isAvailable: !!apiKey,
    async call(req) {
      if (!apiKey) throw new AIProviderError('google', 'GEMINI_API_KEY not set');
      const started = Date.now();

      const contents = req.messages.map((m) => {
        const parts = [{ text: m.content }];
        return { role: m.role === 'assistant' ? 'model' : 'user', parts };
      });

      const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents,
          ...(req.system ? { systemInstruction: { parts: [{ text: req.system }] } } : {}),
          generationConfig: {
            temperature: req.temperature,
            maxOutputTokens: req.maxTokens,
          },
        }),
      });
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        throw new AIProviderError('google', `HTTP ${res.status}: ${body.slice(0, 200)}`);
      }
      const json = await res.json();
      const text = json?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
      if (!text) throw new AIProviderError('google', 'empty response');
      return { text, provider: 'google', model: GEMINI_MODEL, latencyMs: Date.now() - started };
    },
  };
}

// ---------- Router ----------

const ORDER: ProviderId[] = ['anthropic', 'openai', 'google'];

export async function generate(req: AIRequest): Promise<AIResponse> {
  const env = typeof Deno !== 'undefined' ? Deno.env : { get: (_k: string) => undefined };
  const providers: Record<ProviderId, Provider> = {
    anthropic: anthropic(env.get('ANTHROPIC_API_KEY')),
    openai: openai(env.get('OPENAI_API_KEY')),
    google: google(env.get('GEMINI_API_KEY')),
  };

  const errors: string[] = [];
  for (const id of ORDER) {
    const p = providers[id];
    if (!p.isAvailable) continue;
    try {
      return await p.call(req);
    } catch (e) {
      const msg = (e as Error).message;
      console.warn(`[ai-router] ${id} failed: ${msg}`);
      errors.push(`${id}: ${msg}`);
    }
  }

  if (errors.length === 0) {
    throw new Error(
      'No AI provider configured. Set at least one of ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY.'
    );
  }
  throw new Error(`All AI providers failed. Tried: ${errors.join(' · ')}`);
}

// ---------- JSON response helpers ----------

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
      ...(init.headers ?? {}),
    },
  });
}

export function errorResponse(status: number, message: string): Response {
  return jsonResponse({ error: message }, { status });
}
