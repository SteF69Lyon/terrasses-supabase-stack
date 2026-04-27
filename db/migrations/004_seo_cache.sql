-- 004_seo_cache.sql
-- Generic key-value cache for the SEO build pipeline (Astro static generation).
-- Replaces 6 separate Firestore collections (osmCache, osmBuildings, sunScores,
-- pageIntros, pageFaqs, cityGeo) with a single jsonb-typed table.
-- Service role only (build-time on GitHub Action). RLS denies all public access.

CREATE TABLE IF NOT EXISTS seo_cache (
  collection text NOT NULL,
  id text NOT NULL,
  data jsonb NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (collection, id)
);

CREATE INDEX IF NOT EXISTS idx_seo_cache_fetched_at ON seo_cache (fetched_at DESC);

ALTER TABLE seo_cache ENABLE ROW LEVEL SECURITY;

-- No policies = no public/anon access. Service role bypasses RLS by design.

COMMENT ON TABLE seo_cache IS
  'Build-time cache for Astro SEO pipeline. Service role only. ' ||
  'Replaces Firestore collections: osmCache, osmBuildings, sunScores, ' ||
  'pageIntros, pageFaqs, cityGeo.';
