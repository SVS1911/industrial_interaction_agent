"""Register Agent 1's Gemini model version in the existing AgentOps database."""

from pathlib import Path
import os

import psycopg
from dotenv import load_dotenv
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

DATABASE_URL = os.getenv("DATABASE_URL", "")
if not DATABASE_URL:
    raise SystemExit("DATABASE_URL is not configured in backend/.env")

with psycopg.connect(DATABASE_URL) as conn:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT agent_id FROM agentops.agent WHERE code = %s AND status = 'ACTIVE'",
            ("A28_INDUSTRY_INTERACTION",),
        )
        agent = cur.fetchone()
        if not agent:
            raise SystemExit("Active A28_INDUSTRY_INTERACTION agent was not found")
        cur.execute(
            """
            INSERT INTO agentops.model_version
                (agent_id, version, model_type, feature_list, excluded_features, status)
            VALUES (%s, 'mou-1.0', 'LLM_PROMPT', %s, %s, 'ACTIVE')
            ON CONFLICT (agent_id, version) DO UPDATE SET
                model_type = EXCLUDED.model_type,
                feature_list = EXCLUDED.feature_list,
                excluded_features = EXCLUDED.excluded_features,
                status = 'ACTIVE'
            RETURNING model_version_id
            """,
            (
                agent[0],
                Jsonb({
                    "provider": "Google Gemini",
                    "model_env": "GEMINI_MODEL",
                    "purpose": "Semantic extraction and evidence citation from MoU source text",
                    "structured_output": True,
                    "deterministic_reconciliation": True,
                }),
                Jsonb({
                    "note": "LLM does not write engagement tables directly; authoritative database facts are reconciled after extraction."
                }),
            ),
        )
        model_id = cur.fetchone()[0]
    conn.commit()

print("SUCCESS: Agent 1 model registration completed.")
print("Model version: mou-1.0")
print(f"Model version ID: {model_id}")
