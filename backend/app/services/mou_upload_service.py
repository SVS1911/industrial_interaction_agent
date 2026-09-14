from __future__ import annotations

import hashlib
import re
from datetime import date, datetime, timezone
from pathlib import Path
from uuid import UUID, uuid4

from pypdf import PdfReader
from app.core.database import get_connection

UPLOAD_DIR = Path(__file__).resolve().parents[2] / "uploads" / "mous"
MAX_FILE_BYTES = 15 * 1024 * 1024
CHUNK_CHARS = 7000


def _safe_filename(filename: str) -> str:
    name = Path(filename or "mou.pdf").name
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._")
    return name or "mou.pdf"


def _chunks_from_pdf(path: Path) -> tuple[list[dict], int]:
    reader = PdfReader(str(path))
    chunks: list[dict] = []
    seq = 1
    for page_index, page in enumerate(reader.pages, start=1):
        text = (page.extract_text() or "").replace("\x00", " ").strip()
        if not text:
            continue
        # Keep page boundaries for citations while splitting very long pages.
        for start in range(0, len(text), CHUNK_CHARS):
            piece = text[start:start + CHUNK_CHARS].strip()
            if not piece:
                continue
            chunks.append({
                "seq_no": seq,
                "heading_path": None,
                "page_no": page_index,
                "chunk_text": piece,
                "token_count": max(1, min(32767, len(piece) // 4)),
            })
            seq += 1
    if not chunks:
        raise ValueError(
            "The PDF has no readable text. It may be a scanned/image-only MoU; OCR is not configured yet."
        )
    return chunks, len(reader.pages)


def _validate_dates(signed_on: date, valid_from: date | None, valid_until: date | None) -> None:
    vf = valid_from or signed_on
    if valid_until and valid_until < vf:
        raise ValueError("Valid until cannot be earlier than valid from.")


def upload_and_run_mou(
    *,
    file_bytes: bytes,
    filename: str,
    partner_name: str,
    title: str,
    partner_type: str,
    signed_on: date,
    valid_from: date | None,
    valid_until: date | None,
    renewal_alert_days: int,
):
    if not file_bytes:
        raise ValueError("The uploaded MoU file is empty.")
    if len(file_bytes) > MAX_FILE_BYTES:
        raise ValueError("MoU file is too large. Maximum supported size is 15 MB.")
    if not filename.lower().endswith(".pdf"):
        raise ValueError("Agent 1 upload currently supports PDF MoUs only.")
    partner_name = partner_name.strip()
    title = title.strip()
    if not partner_name or not title:
        raise ValueError("Partner name and MoU title are required.")
    _validate_dates(signed_on, valid_from, valid_until)
    valid_from = valid_from or signed_on

    content_hash = hashlib.sha256(file_bytes).hexdigest()
    safe_name = _safe_filename(filename)
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

    with get_connection() as conn:
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT institution_id FROM core.institution WHERE is_active = true ORDER BY code LIMIT 1")
                institution = cur.fetchone()
                if not institution:
                    raise ValueError("No active institution exists in the database.")
                institution_id = institution["institution_id"]

                cur.execute("SELECT document_id FROM knowledge.document WHERE content_hash = %s", (content_hash,))
                if cur.fetchone():
                    raise ValueError("This exact MoU file has already been uploaded.")

                document_id = uuid4()
                storage_path = UPLOAD_DIR / f"{document_id}_{safe_name}"
                storage_path.write_bytes(file_bytes)
                storage_uri = f"local://uploads/mous/{storage_path.name}"

                cur.execute(
                    """
                    INSERT INTO knowledge.document
                      (document_id, institution_id, title, document_class, mime_type, storage_uri,
                       content_hash, page_count, language, is_retrievable_by_agents)
                    VALUES (%s, %s, %s, 'MOU', 'application/pdf', %s, %s, %s, 'en', true)
                    RETURNING document_id
                    """,
                    (document_id, institution_id, title, storage_uri, content_hash, 0),
                )

                chunks, page_count = _chunks_from_pdf(storage_path)
                cur.execute(
                    "UPDATE knowledge.document SET page_count = %s WHERE document_id = %s",
                    (page_count, document_id),
                )
                for chunk in chunks:
                    cur.execute(
                        """
                        INSERT INTO knowledge.document_chunk
                          (document_id, seq_no, heading_path, page_no, chunk_text, token_count)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        """,
                        (document_id, chunk["seq_no"], chunk["heading_path"], chunk["page_no"], chunk["chunk_text"], chunk["token_count"]),
                    )

                cur.execute(
                    """
                    INSERT INTO knowledge.extraction_job
                      (document_id, source_uri, detected_document_type, extraction_method, status, started_at)
                    VALUES (%s, %s, 'MOU', 'TEXT', 'RUNNING', %s)
                    RETURNING extraction_job_id
                    """,
                    (document_id, storage_uri, datetime.now(timezone.utc)),
                )
                extraction_job_id = cur.fetchone()["extraction_job_id"]

                # Reuse an existing partner, otherwise create the partner record.
                cur.execute(
                    """
                    SELECT industry_partner_id FROM engagement.industry_partner
                    WHERE institution_id = %s AND lower(name) = lower(%s)
                    LIMIT 1
                    """,
                    (institution_id, partner_name),
                )
                partner = cur.fetchone()
                if partner:
                    partner_id = partner["industry_partner_id"]
                else:
                    cur.execute(
                        """
                        INSERT INTO engagement.industry_partner
                          (institution_id, name, status)
                        VALUES (%s, %s, 'ACTIVE')
                        RETURNING industry_partner_id
                        """,
                        (institution_id, partner_name),
                    )
                    partner_id = cur.fetchone()["industry_partner_id"]

                cur.execute(
                    """
                    INSERT INTO engagement.mou
                      (industry_partner_id, partner_name, partner_type, title, scope,
                       signed_on, valid_from, valid_until, document_ref, status,
                       renewal_alert_days, extraction_job_id)
                    VALUES (%s, %s, %s, %s, NULL, %s, %s, %s, %s, 'ACTIVE', %s, %s)
                    RETURNING mou_id
                    """,
                    (partner_id, partner_name, partner_type, title, signed_on, valid_from,
                     valid_until, document_id, renewal_alert_days, extraction_job_id),
                )
                mou_id = cur.fetchone()["mou_id"]
                conn.commit()
        except Exception:
            conn.rollback()
            try:
                storage_path.unlink(missing_ok=True)
            except Exception:
                pass
            raise

    try:
        from app.services.mou_intelligence_agent import run_mou_intelligence
        result = run_mou_intelligence(str(mou_id))
        with get_connection() as conn:
            with conn.cursor() as cur:
                if result.get("reports_created", 0) > 0:
                    cur.execute(
                        "UPDATE knowledge.extraction_job SET status='COMPLETED', finished_at=%s, error_detail=NULL WHERE extraction_job_id=%s",
                        (datetime.now(timezone.utc), extraction_job_id),
                    )
                else:
                    cur.execute(
                        "UPDATE knowledge.extraction_job SET status='FAILED', finished_at=%s, error_detail=%s WHERE extraction_job_id=%s",
                        (datetime.now(timezone.utc), "Agent 1 completed without creating a report.", extraction_job_id),
                    )
                conn.commit()
    except Exception as exc:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE knowledge.extraction_job SET status='FAILED', finished_at=%s, error_detail=%s WHERE extraction_job_id=%s",
                    (datetime.now(timezone.utc), str(exc)[:4000], extraction_job_id),
                )
                conn.commit()
        result = {
            "status": "FAILED",
            "mous_processed": 1,
            "reports_created": 0,
            "failures": [{"mou_id": str(mou_id), "title": title, "error": str(exc)}],
            "reports": [],
        }

    return {
        "mou_id": str(mou_id),
        "document_id": str(document_id),
        "extraction_job_id": str(extraction_job_id),
        "partner_name": partner_name,
        "title": title,
        "filename": safe_name,
        "page_count": page_count,
        "chunks_created": len(chunks),
        "agent_1": result,
    }
