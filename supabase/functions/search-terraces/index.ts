// Edge Function: search-terraces
// Remplace l'ancienne Cloud Function geminiSearch.
//
// Flux :
//   1. Géocode location via Nominatim si pas de lat/lng
//   2. Cherche dans osm_cache (TTL 7j)
//   3. MISS → Overpass query, INSERT dans osm_cache
//   4. AI router : LLM analyse l'ensoleillement de chaque POI
//   5. Renvoie { results, sources: [], provider, model }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  generate,
  corsHeaders,
  jsonResponse,
  errorResponse,
} from '../_shared/ai-router.ts';

type Input = {
  location: string;
  type: 'bar' | 'restaurant' | 'cafe' | 'hotel' | 'all';
  date: string;       // YYYY-MM-DD
  time: string;       // HH:MM
  lat?: number;
  lng?: number;
};

type OsmElement = {
  type: 'node' | 'way' | 'relation';
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
};

const RADIUS_M = 1000;
const TTL_MS = 7 * 24 * 60 * 60 * 1000;
const OVERPASS_MIRRORS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];
const NOMINATIM = 'https://nominatim.openstreetmap.org/search';

function validate(d: unknown): string | null {
  if (!d || typeof d !== 'object') return 'Invalid payload';
  const i = d as Partial<Input>;
  if (!i.location || typeof i.location !== 'string') return 'location required';
  if (!i.type || typeof i.type !== 'string') return 'type required';
  if (!i.date || !/^\d{4}-\d{2}-\d{2}$/.test(i.date)) return 'date must be YYYY-MM-DD';
  if (!i.time || !/^\d{1,2}:\d{2}$/.test(i.time)) return 'time must be HH:MM';
  return null;
}

async function geocode(location: string): Promise<{ lat: number; lng: number }> {
  const url = `${NOMINATIM}?format=json&limit=1&q=${encodeURIComponent(location)}`;
  const res = await fetch(url, {
    headers: { 'User-Agent': 'terrasse-au-soleil/1.0 (https://terrasse-au-soleil.fr; contact: sflandrin@outlook.com)' },
  });
  if (!res.ok) throw new Error(`Nominatim ${res.status}`);
  const arr = await res.json();
  if (!arr.length) throw new Error(`Location not found: ${location}`);
  return { lat: parseFloat(arr[0].lat), lng: parseFloat(arr[0].lon) };
}

async function overpassQuery(lat: number, lng: number, type: string): Promise<OsmElement[]> {
  const amenityFilter = type === 'all'
    ? '["amenity"~"^(bar|restaurant|cafe)$"]'
    : `["amenity"="${type}"]`;
  const q = `
    [out:json][timeout:15];
    (
      node${amenityFilter}["outdoor_seating"="yes"](around:${RADIUS_M},${lat},${lng});
      way${amenityFilter}["outdoor_seating"="yes"](around:${RADIUS_M},${lat},${lng});
    );
    out center 50;
  `.trim();

  const errors: string[] = [];
  for (const mirror of OVERPASS_MIRRORS) {
    try {
      const res = await fetch(mirror, {
        method: 'POST',
        body: 'data=' + encodeURIComponent(q),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          // OSM/Overpass demande un UA identifiable, sinon 406/429 par les anti-abus.
          'User-Agent': 'terrasse-au-soleil/1.0 (https://terrasse-au-soleil.fr; contact: sflandrin@outlook.com)',
        },
      });
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        const err = `${mirror} HTTP ${res.status}: ${body.slice(0, 200)}`;
        errors.push(err);
        console.error(`[search-terraces] ${err}`);
        continue;
      }
      const json = await res.json();
      return (json.elements ?? []) as OsmElement[];
    } catch (e) {
      const msg = (e as Error).message;
      errors.push(`${mirror}: ${msg}`);
      console.error(`[search-terraces] Overpass ${mirror} threw: ${msg}`);
    }
  }
  throw new Error(`All Overpass mirrors failed: ${errors.join(' | ')}`);
}

function locationKey(lat: number, lng: number, type: string): string {
  // round to 4 decimals (~11m precision) + type — deterministic
  const k = `${lat.toFixed(4)}:${lng.toFixed(4)}:${type}:${RADIUS_M}`;
  // simple hash : sha256 hex would be safer mais here clé en clair OK (DB privée)
  return k;
}

function osmToTerrace(el: OsmElement) {
  const lat = el.lat ?? el.center?.lat;
  const lon = el.lon ?? el.center?.lon;
  return {
    id: String(el.id),
    name: el.tags?.name ?? 'Établissement sans nom',
    address: [el.tags?.['addr:street'], el.tags?.['addr:postcode'], el.tags?.['addr:city']]
      .filter(Boolean).join(' '),
    type: el.tags?.amenity ?? 'bar',
    lat,
    lng: lon,
    rating: 0, // OSM ne fournit pas de rating
    sunExposure: null as number | null,
    description: '',
    sunLevel: '',
    imageUrl: '',
    coordinates: { lat: lat ?? 0, lng: lon ?? 0 },
  };
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return errorResponse(405, 'POST only');

  const body = await req.json().catch(() => null);
  const err = validate(body);
  if (err) return errorResponse(400, err);
  const input = body as Input;

  try {
    // 1. coords
    const coords = (input.lat != null && input.lng != null)
      ? { lat: input.lat, lng: input.lng }
      : await geocode(input.location);

    // 2. cache lookup
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const key = locationKey(coords.lat, coords.lng, input.type);

    const { data: cached } = await supabase
      .from('osm_cache')
      .select('results, fetched_at')
      .eq('location_key', key)
      .single();

    let elements: OsmElement[];
    const fresh = cached
      && (Date.now() - new Date(cached.fetched_at).getTime() < TTL_MS);

    if (fresh) {
      elements = cached!.results as OsmElement[];
    } else {
      elements = await overpassQuery(coords.lat, coords.lng, input.type);
      await supabase.from('osm_cache').upsert({
        location_key: key,
        results: elements,
        fetched_at: new Date().toISOString(),
      });
    }

    // 3. LLM enrichment — ensoleillement
    const terraces = elements.map(osmToTerrace).filter((t) => t.lat && t.lng);
    if (terraces.length === 0) {
      return jsonResponse({ results: [], sources: [], provider: null, model: null });
    }

    const prompt = `Voici une liste de POI OpenStreetMap à analyser pour leur ensoleillement le ${input.date} à ${input.time} :

${JSON.stringify(terraces.map((t) => ({ id: t.id, name: t.name, lat: t.lat, lng: t.lng })), null, 2)}

Pour chaque POI, calcule un sunExposure entre 0 (totalement à l'ombre) et 100 (en plein soleil) en tenant compte de l'orientation des rues environnantes et de la position du soleil à l'heure indiquée. Si tu ne peux pas estimer, mets sunExposure: null.

Réponds EXCLUSIVEMENT par un tableau JSON de la forme :
[{"id":"<id>","sunExposure":<0-100|null>,"description":"<courte analyse>"}]`;

    const ai = await generate({
      system: 'Tu es un expert en analyse d\'ensoleillement urbain. Tu réponds uniquement en JSON.',
      messages: [{ role: 'user', content: prompt }],
      maxTokens: 2000,
    });

    // Parser le JSON
    const match = ai.text.match(/\[[\s\S]*\]/);
    let enrichments: Array<{ id: string; sunExposure: number | null; description: string }> = [];
    if (match) {
      try {
        enrichments = JSON.parse(match[0]);
      } catch {
        // si le LLM rend du JSON cassé, on retourne quand même les terraces sans enrichissement
      }
    }

    const enriched = terraces.map((t) => {
      const e = enrichments.find((x) => x.id === t.id);
      return e
        ? { ...t, sunExposure: e.sunExposure, description: e.description }
        : t;
    });

    return jsonResponse({
      results: enriched,
      sources: [],
      provider: ai.provider,
      model: ai.model,
    });
  } catch (e) {
    console.error('search-terraces error:', e);
    return errorResponse(500, (e as Error).message);
  }
};

Deno.serve(handler);
export default handler;
