"""
Register Agent 4 model version in the existing PostgreSQL/Supabase database.

This script:
- Reads DATABASE_URL from backend/.env
- Finds A28_INDUSTRY_INTERACTION in agentops.agent
- Registers recommendation-1.0 in agentops.model_version
- Safely handles repeated execution
- Marks the model ACTIVE
- Does NOT create/reset/replace the database
- Never prints the database password
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb


AGENT_CODE = "A28_INDUSTRY_INTERACTION"
MODEL_VERSION = "recommendation-1.0"
MODEL_TYPE = "RULE_BASED"
MODEL_STATUS = "ACTIVE"


def load_env_file(env_path: Path) -> None:
    """Load simple KEY=VALUE entries from a .env file."""
    if not env_path.exists():
        raise FileNotFoundError(f".env file not found: {env_path}")

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#"):
            continue

        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if (
            len(value) >= 2
            and value[0] == value[-1]
            and value[0] in {"'", '"'}
        ):
            value = value[1:-1]

        os.environ.setdefault(key, value)


def main() -> int:
    # backend/
    backend_root = Path(__file__).resolve().parents[1]

    # backend/.env
    env_path = backend_root / ".env"

    try:
        load_env_file(env_path)
    except Exception as exc:
        print(f"ERROR: Could not load backend/.env: {exc}")
        return 1

    database_url = os.getenv("DATABASE_URL")

    if not database_url:
        print("ERROR: DATABASE_URL was not found in backend/.env")
        return 1

    feature_list = {
        "purpose": (
            "Deterministic partner-level industry interaction "
            "recommendations"
        ),
        "inputs": [
            "partner health snapshot",
            "MoU renewal state",
            "MoU deliverable status",
            "partner activity ledger",
            "placement relationship signals",
            "event evidence",
            "industry activity feedback",
        ],
        "rules": [
            "renewal window without open renewal discussion",
            "overdue incomplete deliverable",
            "dormant partner",
            "at-risk partner",
            "stable partner with low recent activity",
            "strong partner with activity and student outcomes",
        ],
        "priority_bands": [
            "CRITICAL",
            "HIGH",
            "MEDIUM",
            "LOW",
        ],
    }

    excluded_features = {
        "note": (
            "No protected personal attributes are used. "
            "Student-level identifiers are not used in "
            "recommendation outputs."
        )
    }

    try:
        with psycopg.connect(database_url) as conn:
            with conn.cursor() as cur:

                # ---------------------------------------------------------
                # 1. Find the existing Agent 28 registry record.
                # ---------------------------------------------------------
                cur.execute(
                    """
                    SELECT agent_id
                    FROM agentops.agent
                    WHERE code = %s
                      AND status = 'ACTIVE'
                    LIMIT 1
                    """,
                    (AGENT_CODE,),
                )

                agent_row = cur.fetchone()

                if agent_row is None:
                    print(
                        f"ERROR: Active agent {AGENT_CODE} was not found "
                        "in agentops.agent."
                    )
                    return 1

                agent_id = agent_row[0]

                # ---------------------------------------------------------
                # 2. Check whether recommendation-1.0 already exists.
                # ---------------------------------------------------------
                cur.execute(
                    """
                    SELECT
                        model_version_id,
                        model_type,
                        status
                    FROM agentops.model_version
                    WHERE agent_id = %s
                      AND version = %s
                    LIMIT 1
                    """,
                    (agent_id, MODEL_VERSION),
                )

                existing_row = cur.fetchone()

                if existing_row is not None:
                    model_version_id = existing_row[0]

                    # Make sure the existing registry row is active and
                    # contains the correct Agent 4 metadata.
                    cur.execute(
                        """
                        UPDATE agentops.model_version
                        SET
                            model_type = %s,
                            feature_list = %s,
                            excluded_features = %s,
                            validated_on = CURRENT_DATE,
                            status = %s
                        WHERE model_version_id = %s
                        """,
                        (
                            MODEL_TYPE,
                            Jsonb(feature_list),
                            Jsonb(excluded_features),
                            MODEL_STATUS,
                            model_version_id,
                        ),
                    )

                    action = "updated existing"

                else:
                    # -----------------------------------------------------
                    # 3. Register the missing model version.
                    # -----------------------------------------------------
                    cur.execute(
                        """
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
                        VALUES (
                            gen_random_uuid(),
                            %s,
                            %s,
                            %s,
                            %s,
                            %s,
                            CURRENT_DATE,
                            %s
                        )
                        RETURNING model_version_id
                        """,
                        (
                            agent_id,
                            MODEL_VERSION,
                            MODEL_TYPE,
                            Jsonb(feature_list),
                            Jsonb(excluded_features),
                            MODEL_STATUS,
                        ),
                    )

                    model_version_id = cur.fetchone()[0]
                    action = "created"

            conn.commit()

        # -------------------------------------------------------------
        # 4. Success message.
        #
        # Never print DATABASE_URL or credentials.
        # -------------------------------------------------------------
        print()
        print("SUCCESS: Agent 4 model registration completed.")
        print(f"Action: {action}")
        print(f"Agent: {AGENT_CODE}")
        print(f"Model version: {MODEL_VERSION}")
        print(f"Model type: {MODEL_TYPE}")
        print(f"Status: {MODEL_STATUS}")
        print(f"Model version ID: {model_version_id}")
        print()

        return 0

    except psycopg.Error as exc:
        print("ERROR: PostgreSQL operation failed.")
        print(f"Details: {exc}")
        return 1

    except Exception as exc:
        print("ERROR: Unexpected failure.")
        print(f"Details: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())