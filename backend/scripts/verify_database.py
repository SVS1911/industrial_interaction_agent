import os
from pathlib import Path
from dotenv import load_dotenv
import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")
TABLES = ['engagement.industry_partner', 'engagement.partner_contact', 'engagement.partner_expertise', 'engagement.mou', 'engagement.mou_deliverable', 'engagement.mou_deliverable_fulfilment', 'engagement.mou_renewal', 'engagement.industry_activity', 'engagement.activity_course_alignment', 'engagement.partner_health_snapshot', 'placement.company', 'placement.offer', 'placement.internship', 'knowledge.document', 'agentops.agent_run', 'agentops.agent_output', 'agentops.alert', 'quality.evidence_item', 'engagement.guest_lecture']

def main():
    url = os.getenv("DATABASE_URL")
    if not url:
        print("ERROR: DATABASE_URL is not configured in .env")
        return 1
    try:
        with psycopg.connect(url) as conn:
            with conn.cursor() as cur:
                failed = False
                for qualified in TABLES:
                    schema, table = qualified.split(".", 1)
                    cur.execute("SELECT to_regclass(%s)", (qualified,))
                    if cur.fetchone()[0] is None:
                        failed = True
                        print(f"✗ {qualified} missing")
                        continue
                    query = sql.SQL("SELECT count(*) FROM {}.{}").format(
                        sql.Identifier(schema), sql.Identifier(table)
                    )
                    cur.execute(query)
                    print(f"✓ {qualified} exists — {cur.fetchone()[0]} rows")

                cur.execute("SELECT to_regclass(%s)", ('engagement.v_guest_lecture_register',))
                if cur.fetchone()[0] is None:
                    failed = True
                    print("✗ engagement.v_guest_lecture_register missing")
                else:
                    print("✓ engagement.v_guest_lecture_register exists")

                return 1 if failed else 0
    except Exception as exc:
        print(f"ERROR: verification failed: {exc}")
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
