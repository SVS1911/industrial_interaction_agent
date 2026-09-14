-- Agent 4 deterministic recommendation model.
-- Safe to run against the existing Agent 28 PostgreSQL database: it adds only
-- the missing model-registry row and does not recreate or replace any tables.
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
    'recommendation-1.0',
    'RULE_BASED',
    '{
      "purpose": "Deterministic partner-level industry interaction recommendations",
      "inputs": [
        "partner health snapshot",
        "MoU renewal state",
        "MoU deliverable status",
        "partner activity ledger",
        "placement relationship signals",
        "event evidence",
        "industry activity feedback"
      ],
      "rules": [
        "renewal window without open renewal discussion",
        "overdue incomplete deliverable",
        "dormant partner",
        "at-risk partner",
        "stable partner with low recent activity",
        "strong partner with activity and student outcomes"
      ],
      "priority_bands": ["CRITICAL", "HIGH", "MEDIUM", "LOW"]
    }'::jsonb,
    '{
      "note": "No protected personal attributes are used. Student-level identifiers are not used in recommendation outputs."
    }'::jsonb,
    current_date,
    'ACTIVE'
FROM agentops.agent a
WHERE a.code = 'A28_INDUSTRY_INTERACTION'
  AND a.status = 'ACTIVE'
  AND NOT EXISTS (
      SELECT 1
      FROM agentops.model_version mv
      WHERE mv.agent_id = a.agent_id
        AND mv.version = 'recommendation-1.0'
  );
