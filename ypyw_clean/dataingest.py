import logging
import os
import time
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

logger = logging.getLogger(__name__)

# --- CONFIGURATION (Azure SQL via environment variables) ---
SERVER = os.environ.get('SQL_SERVER', 'ypyw-sql-ahmedsohail.database.windows.net')
DATABASE = os.environ.get('SQL_DATABASE', 'ypyw-bi-db')
SQL_ADMIN_USER = os.environ.get('SQL_ADMIN_USER', 'ypywadmin')
DRIVER = os.environ.get('SQL_DRIVER', 'ODBC Driver 18 for SQL Server')

# Folder paths (configurable via environment, with a relative fallback)
BASE_DIR = os.environ.get(
    'YPYW_BASE_DIR',
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "YourPaintingYourWay"),
)
WATCH_FOLDER = os.path.join(BASE_DIR, "DropZone")
PROCESSED_FOLDER = os.path.join(BASE_DIR, "Processed")


def get_engine():
    """Build the SQLAlchemy engine for the Azure SQL database.

    The password is read from SQL_ADMIN_PASSWORD at call time (not import time),
    so this module can be imported and unit-tested without a live database or driver.
    """
    password = os.environ.get('SQL_ADMIN_PASSWORD')
    if not password:
        raise ValueError("SQL_ADMIN_PASSWORD environment variable not set")

    odbc_params = quote_plus(
        f"Driver={{{DRIVER}}};"
        f"Server=tcp:{SERVER},1433;"
        f"Database={DATABASE};"
        f"Uid={SQL_ADMIN_USER};"
        f"Pwd={password};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=30;"
    )
    connection_url = f"mssql+pyodbc:///?odbc_connect={odbc_params}"
    return create_engine(connection_url)


def clean_headers(df):
    """Return the dataframe with surrounding whitespace stripped from column names."""
    df.columns = df.columns.str.strip()
    return df


def build_archive_path(processed_folder, filename, exists_fn=os.path.exists,
                       timestamp_fn=lambda: int(time.time())):
    """Resolve where a processed file should be archived.

    Returns the plain destination, or a timestamp-prefixed name when a file already
    exists there (collision handling). ``exists_fn`` and ``timestamp_fn`` are injectable
    so the collision logic can be unit-tested deterministically.
    """
    destination = os.path.join(processed_folder, filename)
    if exists_fn(destination):
        destination = os.path.join(processed_folder, f"{timestamp_fn()}_{filename}")
    return destination


def process_data(filepath, engine=None):
    """Read a CSV, load it into Azure SQL, and archive the processed file."""
    if engine is None:
        engine = get_engine()
    try:
        logger.info("Reading CSV: %s", filepath)
        df = pd.read_csv(filepath)
        df = clean_headers(df)

        logger.info("Uploading %d rows to %s...", len(df), DATABASE)
        df.to_sql('RawEstimates', engine, if_exists='append', index=False)
        logger.info("Data saved to database.")

        filename = os.path.basename(filepath)
        destination = build_archive_path(PROCESSED_FOLDER, filename)
        os.rename(filepath, destination)
        logger.info("File archived to: %s", destination)
    except Exception:
        logger.exception("Failed to process %s", filepath)


class IngestHandler(FileSystemEventHandler):
    def __init__(self, engine):
        self._engine = engine

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.csv'):
            logger.info("New file detected: %s", event.src_path)
            time.sleep(1)
            process_data(event.src_path, self._engine)


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )
    os.makedirs(WATCH_FOLDER, exist_ok=True)
    os.makedirs(PROCESSED_FOLDER, exist_ok=True)

    engine = get_engine()
    logger.info("System online. Watching %s ...", WATCH_FOLDER)

    observer = Observer()
    observer.schedule(IngestHandler(engine), WATCH_FOLDER, recursive=False)
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        observer.join()


if __name__ == "__main__":
    main()
