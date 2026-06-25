"""One-shot seeder for the YPYW Azure SQL database.

Loads the synthetic ``sample_estimates.csv`` into the ``RawEstimates`` table so the
database has demo data without having to run the live ``dataingest.py`` watcher.
Connection settings are read from ``azure/.env`` (never committed).

Usage:
    python azure/seed_sample_data.py
"""
import os
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine, text

HERE = Path(__file__).resolve().parent          # azure/
REPO = HERE.parent                              # repo root
ENV_FILE = HERE / ".env"
CSV_FILE = REPO / "ypyw_clean" / "Processed" / "sample_estimates.csv"


def load_env(path: Path) -> None:
    """Minimal .env loader (no external dependency)."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip())


load_env(ENV_FILE)

SERVER = os.environ.get("SQL_SERVER", "ypyw-sql-ahmedsohail.database.windows.net")
DATABASE = os.environ.get("SQL_DATABASE", "ypyw-bi-db")
USER = os.environ.get("SQL_ADMIN_USER", "ypywadmin")
PASSWORD = os.environ.get("SQL_ADMIN_PASSWORD")
DRIVER = os.environ.get("SQL_DRIVER", "ODBC Driver 18 for SQL Server")

if not PASSWORD:
    raise SystemExit("SQL_ADMIN_PASSWORD not set (check azure/.env)")

odbc = quote_plus(
    f"Driver={{{DRIVER}}};"
    f"Server=tcp:{SERVER},1433;"
    f"Database={DATABASE};"
    f"Uid={USER};"
    f"Pwd={PASSWORD};"
    "Encrypt=yes;"
    "TrustServerCertificate=no;"
    "Connection Timeout=30;"
)
engine = create_engine(f"mssql+pyodbc:///?odbc_connect={odbc}")

df = pd.read_csv(CSV_FILE)
df.columns = df.columns.str.strip()
print(f"Read {len(df)} rows from {CSV_FILE.name}; columns: {list(df.columns)}")

df.to_sql("RawEstimates", engine, if_exists="append", index=False)

with engine.connect() as conn:
    total = conn.execute(text("SELECT COUNT(*) FROM RawEstimates")).scalar()

print(f"SUCCESS: inserted {len(df)} rows. RawEstimates now has {total} rows.")
