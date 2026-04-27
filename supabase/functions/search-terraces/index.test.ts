import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

// Mock global fetch pour Nominatim + Overpass + LLM
const originalFetch = globalThis.fetch;

Deno.test('search-terraces returns Terrace[] in expected shape', async () => {
  globalThis.fetch = (input: Request | URL | string, _init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input.toString();
    if (url.includes('nominatim')) {
      return Promise.resolve(new Response(JSON.stringify([{ lat: '45.75', lon: '4.85' }])));
    }
    if (url.includes('overpass')) {
      return Promise.resolve(new Response(JSON.stringify({
        elements: [
          { type: 'node', id: 1, lat: 45.75, lon: 4.85, tags: { name: 'Le Solar', amenity: 'bar' } },
        ],
      })));
    }
    if (url.includes('anthropic.com')) {
      return Promise.resolve(new Response(JSON.stringify({
        content: [{ type: 'text', text: '[{"id":"1","name":"Le Solar","sunExposure":75}]' }],
      })));
    }
    return Promise.resolve(new Response('{}', { status: 200 }));
  };

  const { default: handler } = await import('./index.ts');
  const req = new Request('http://localhost/functions/v1/search-terraces', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ location: 'Lyon', type: 'bar', date: '2026-04-30', time: '18:00' }),
  });
  const res = await handler(req);
  const json = await res.json();

  assertEquals(res.status, 200);
  assertEquals(Array.isArray(json.results), true);
  assertEquals(json.results[0].name, 'Le Solar');
  assertEquals(typeof json.provider, 'string');

  globalThis.fetch = originalFetch;
});
