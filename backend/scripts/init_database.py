import os
import shutil
import subprocess
from pathlib import Path
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
SQL_FILE = ROOT / "database" / "agent28_synthetic_database.sql"

def main():
    load_dotenv(ROOT / ".env")
    database_url = os.getenv("DATABASE_URL")
    psql_path = os.getenv("PSQL_PATH", "psql")

    if not database_url:
        print("ERROR: DATABASE_URL is not configured in .env")
        return 1
    if not SQL_FILE.exists():
        print(f"ERROR: SQL source file not found: {SQL_FILE}")
        return 1
    if shutil.which(psql_path) is None and not Path(psql_path).exists():
        print(f"ERROR: psql executable not found: {psql_path}")
        return 1

    print("Initializing Agent 28 database...")
    result = subprocess.run(
        [psql_path, database_url, "-v", "ON_ERROR_STOP=1", "-f", str(SQL_FILE)],
        cwd=ROOT,
    )
    if result.returncode == 0:
        print("SUCCESS: database initialized.")
    else:
        print(f"ERROR: database initialization failed with exit code {result.returncode}.")
    return result.returncode

if __name__ == "__main__":
    raise SystemExit(main())
