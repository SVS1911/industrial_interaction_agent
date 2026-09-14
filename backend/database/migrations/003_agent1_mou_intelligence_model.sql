-- Agent 1: Gemini-backed MoU Intelligence model registration.
-- Safe to run against the existing PostgreSQL/Supabase database.
-- Does not recreate tables or replace the database.

INSERT INTO agentops.model_version (
    model_version_id,
    agent_id,
    version,
    model_type,
    feature_list,
    excluded_features,
    validated_on,
    status
)
SELECT
    gen_random_uuid(),
    a.agent_id,
    'mou-1.0',
    'LLM_PROMPT',
    jsonb_build_object(
        'provider', 'Google Gemini',
        'model_env', 'GEMINI_MODEL',
        'purpose', 'Semantic extraction and evidence citation from MoU source text',
        'structured_output', true,
        'deterministic_reconciliation', true
    ),
    jsonb_build_object(
        'note', 'LLM does not write engagement tables directly; dates, status, scope and recorded deliverables are reconciled from authoritative database records.'
    ),
    NULL,
    'ACTIVE'
FROM agentops.agent a
WHERE a.code = 'A28_INDUSTRY_INTERACTION'
  AND a.status = 'ACTIVE'
  AND NOT EXISTS (
      SELECT 1 FROM agentops.model_version mv
      WHERE mv.agent_id = a.agent_id AND mv.version = 'mou-1.0'
  );
