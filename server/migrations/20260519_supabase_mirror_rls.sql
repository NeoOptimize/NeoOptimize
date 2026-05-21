-- NeoOptimize Supabase mirror tables + RLS policy
-- Run this in the Supabase SQL Editor for the cloud project used by SUPABASE_URL.
-- The RMM server must use SUPABASE_SERVICE_ROLE_KEY, not an anon/publishable key.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID NULL,
  actor_type TEXT NOT NULL DEFAULT 'system',
  action TEXT NOT NULL,
  target_id TEXT NULL,
  target_type TEXT NULL,
  detail JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address INET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_neo_mirror_audit_action
  ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_neo_mirror_audit_created_at
  ON public.audit_logs(created_at DESC);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "neooptimize service role audit mirror" ON public.audit_logs;
CREATE POLICY "neooptimize service role audit mirror"
  ON public.audit_logs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.action_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL DEFAULT 'neooptimize-rmm',
  action_type TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'success',
  summary TEXT NOT NULL DEFAULT 'NeoOptimize mirror event',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.action_logs
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'success';

ALTER TABLE public.action_logs
  ADD COLUMN IF NOT EXISTS summary TEXT NOT NULL DEFAULT 'NeoOptimize mirror event';

CREATE INDEX IF NOT EXISTS idx_neo_mirror_action_type
  ON public.action_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_neo_mirror_action_created_at
  ON public.action_logs(created_at DESC);

ALTER TABLE public.action_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "neooptimize service role action mirror" ON public.action_logs;
CREATE POLICY "neooptimize service role action mirror"
  ON public.action_logs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Optional, intentionally disabled:
-- Only enable a narrower authenticated policy if you create a dedicated Supabase
-- service account and add tenant-scoped checks. The RMM mirror should normally use
-- service_role instead.
