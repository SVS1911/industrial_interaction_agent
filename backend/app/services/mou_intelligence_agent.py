"""Gemini-backed MoU Intelligence Agent for Agent 28.

The LLM extracts semantics from MoU source text. Database facts are reconciled
separately and the combined report is written only to AgentOps; this agent does
not mutate the engagement MoU or deliverable tables.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from app.core.database import get_connection
from app.core.config import settings
from app.services.gemini_mou_extractor import GeminiMouExtractor
from app.schemas.mou_intelligence import DeterministicValidation

AGENT_CODE = "A28_INDUSTRY_INTERACTION"
AGENT_VERSION = "1.2"
MODEL_VERSION = "mou-1.0"


MOU_QUERY = """
SELECT
    m.mou_id, m.partner_name, m.title, m.scope, m.signed_on, m.valid_from,
    m.valid_until, m.status, m.document_ref, m.extraction_job_id,
    p.name AS industry_partner_name
FROM engagement.mou m
LEFT JOIN engagement.industry_partner p ON p.industry_partner_id = m.industry_partner_id
WHERE (%(mou_id)s::uuid IS NULL OR m.mou_id = %(mou_id)s::uuid)
ORDER BY m.partner_name, m.title;
"""

CHUNK_QUERY = """
SELECT document_chunk_id, seq_no, heading_path, page_no, chunk_text
FROM knowledge.document_chunk
WHERE document_id = %s
ORDER BY seq_no;
"""

DELIVERABLE_QUERY = """
SELECT mou_deliverable_id, description, deliverable_type, target_count,
       achieved_count, due_date, status
FROM engagement.mou_deliverable
WHERE mou_id = %s
ORDER BY due_date NULLS LAST, description;
"""


def _json_value(value: Any) -> Any:
    if isinstance(value, (UUID, date, datetime, Decimal)):
        return str(value)
    if isinstance(value, dict):
        return {k: _json_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_value(v) for v in value]
    return value


def _deterministic_validate(mou: dict, deliverables: list[dict], extraction) -> DeterministicValidation:
    discrepancies: list[str] = []
    extracted_deliverables = [c for c in extraction.commitments if c.commitment_type == "DELIVERABLE"]
    if not extraction.scope and mou.get("scope"):
        discrepancies.append("LLM extraction did not identify a scope even though engagement.mou.scope is populated.")
    if extraction.scope and mou.get("scope"):
        if extraction.scope.strip().lower() != str(mou["scope"]).strip().lower():
            discrepancies.append("LLM scope differs from the authoritative engagement.mou.scope value; database value retained as authoritative.")

    db_deliverables = [_json_value(d) for d in deliverables]
    if deliverables and len(extracted_deliverables) == 0:
        discrepancies.append("Database has MoU deliverables but Gemini did not identify a deliverable commitment.")
    review = bool(discrepancies or extraction.review_required or any(c.review_required for c in extraction.commitments))
    return DeterministicValidation(
        db_scope=mou.get("scope"),
        db_valid_from=mou.get("valid_from"),
        db_valid_until=mou.get("valid_until"),
        db_deliverables=db_deliverables,
        extracted_deliverables_count=len(extracted_deliverables),
        reconciled_deliverables_count=min(len(extracted_deliverables), len(deliverables)) if deliverables else 0,
        discrepancies=discrepancies,
        review_required=review,
    )


def _citation_list(extraction) -> list[dict]:
    citations: list[dict] = []
    for commitment in extraction.commitments:
        for evidence in commitment.evidence:
            citations.append({
                "type": "MOU_CLAUSE",
                "page_no": evidence.page_no,
                "heading_path": evidence.heading_path,
                "source_text": evidence.source_text,
                "commitment": commitment.description,
            })
    for evidence in extraction.renewal_terms.evidence:
        citations.append({
            "type": "RENEWAL_CLAUSE",
            "page_no": evidence.page_no,
            "heading_path": evidence.heading_path,
            "source_text": evidence.source_text,
        })
    return citations


def _load_mous(cur, mou_id: str | None) -> list[dict]:
    cur.execute(MOU_QUERY, {"mou_id": mou_id})
    return cur.fetchall()


def run_mou_intelligence(mou_id: str | None = None) -> dict[str, Any]:
    started = datetime.now(timezone.utc)
    extractor = GeminiMouExtractor()

    with get_connection() as conn:
        try:
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    "SELECT agent_id, version FROM agentops.agent WHERE code = %s AND status = 'ACTIVE'",
                    (AGENT_CODE,),
                )
                agent = cur.fetchone()
                if not agent:
                    raise RuntimeError(f"Active agent {AGENT_CODE} was not found")

                cur.execute(
                    """
                    SELECT model_version_id, version
                    FROM agentops.model_version
                    WHERE agent_id = %s AND version = %s AND status = 'ACTIVE'
                    LIMIT 1
                    """,
                    (agent["agent_id"], MODEL_VERSION),
                )
                model = cur.fetchone()
                if not model:
                    raise RuntimeError(f"Active model {MODEL_VERSION} was not found for {AGENT_CODE}")

                cur.execute(
                    """
                    INSERT INTO agentops.agent_run (
                        agent_id, agent_version, trigger_type, effective_role_id,
                        scope, request_text, started_at, status
                    ) VALUES (
                        %s, %s, 'USER',
                        (SELECT role_id FROM identity.role WHERE code = 'INDUSTRY_RELATIONS' LIMIT 1),
                        %s, %s, %s, 'RUNNING'
                    ) RETURNING agent_run_id
                    """,
                    (
                        agent["agent_id"], AGENT_VERSION,
                        Jsonb({"job": "MOU_INTELLIGENCE", "mou_id": mou_id}),
                        "Extract and reconcile MoU commitments from source documents.",
                        started,
                    ),
                )
                run_id = cur.fetchone()["agent_run_id"]

                mous = _load_mous(cur, mou_id)
                cur.execute(
                    """
                    INSERT INTO agentops.agent_run_input
                        (agent_run_id, source_schema, source_table, record_count, filter_expression)
                    VALUES (%s, 'engagement', 'mou', %s, %s)
                    """,
                    (run_id, len(mous), f"mou_id={mou_id}" if mou_id else "all MoUs"),
                )

                reports: list[dict[str, Any]] = []
                failures: list[dict[str, str]] = []
                for mou in mous:
                    try:
                        if not mou.get("document_ref"):
                            raise ValueError("MoU has no linked knowledge.document")
                        cur.execute(CHUNK_QUERY, (mou["document_ref"],))
                        chunks = cur.fetchall()
                        if not chunks:
                            raise ValueError("Linked MoU document has no document chunks")
                        cur.execute(DELIVERABLE_QUERY, (mou["mou_id"],))
                        deliverables = cur.fetchall()

                        db_context = {
                            "scope": mou.get("scope"),
                            "signed_on": _json_value(mou.get("signed_on")),
                            "valid_from": _json_value(mou.get("valid_from")),
                            "valid_until": _json_value(mou.get("valid_until")),
                            "status": mou.get("status"),
                            "deliverables": [_json_value(d) for d in deliverables],
                        }
                        extraction = extractor.extract(
                            partner_name=mou["partner_name"],
                            title=mou["title"],
                            chunks=chunks,
                            db_context=db_context,
                        )
                        validation = _deterministic_validate(mou, deliverables, extraction)
                        requires_review = bool(validation.review_required or extraction.review_required)
                        report = {
                            "mou_id": str(mou["mou_id"]),
                            "partner_name": mou["partner_name"],
                            "title": mou["title"],
                            "document_id": str(mou["document_ref"]) if mou.get("document_ref") else None,
                            "extraction_job_id": str(mou["extraction_job_id"]) if mou.get("extraction_job_id") else None,
                            "model_version": MODEL_VERSION,
                            "extraction": extraction.model_dump(mode="json"),
                            "validation": validation.model_dump(mode="json"),
                            "citations": _citation_list(extraction),
                            "requires_human_review": requires_review,
                        }
                        cur.execute(
                            """
                            INSERT INTO agentops.agent_output (
                                agent_run_id, output_type, subject_type, subject_id, payload,
                                reasoning_summary, citations, interpretation, confidence,
                                requires_approval, approval_status
                            ) VALUES (
                                %s, 'REPORT', 'MOU', %s, %s, %s, %s, %s, %s, %s, %s
                            )
                            RETURNING agent_output_id
                            """,
                            (
                                run_id,
                                mou["mou_id"],
                                Jsonb(report),
                                "Gemini extracted MoU semantics from cited source chunks; deterministic database reconciliation is authoritative for dates, status, scope, and recorded deliverables.",
                                Jsonb(report["citations"]),
                                Jsonb({"provider": "Google Gemini", "model": settings.gemini_model, "review_required": requires_review}),
                                extraction.overall_confidence,
                                requires_review,
                                "PENDING" if requires_review else "NOT_REQUIRED",
                            ),
                        )
                        reports.append(report)
                    except Exception as exc:
                        failures.append({"mou_id": str(mou["mou_id"]), "title": mou["title"], "error": str(exc)})

                finished = datetime.now(timezone.utc)
                status = "SUCCEEDED" if not failures else ("PARTIAL" if reports else "FAILED")
                cur.execute(
                    """
                    UPDATE agentops.agent_run
                    SET finished_at = %s,
                        latency_ms = %s,
                        token_input = NULL,
                        token_output = NULL,
                        status = %s,
                        failure_reason = %s
                    WHERE agent_run_id = %s
                    """,
                    (
                        finished,
                        int((finished - started).total_seconds() * 1000),
                        status,
                        " | ".join(f["error"] for f in failures)[:4000] if failures else None,
                        run_id,
                    ),
                )
                conn.commit()
                return {
                    "agent": AGENT_CODE,
                    "agent_version": AGENT_VERSION,
                    "model_version": MODEL_VERSION,
                    "provider": "Google Gemini",
                    "model": settings.gemini_model,
                    "run_id": str(run_id),
                    "status": status,
                    "mous_processed": len(mous),
                    "reports_created": len(reports),
                    "failures": failures,
                    "reports": reports,
                }
        except Exception:
            conn.rollback()
            raise
