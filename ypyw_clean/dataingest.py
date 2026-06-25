import time
import os
import pandas as pd
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from sqlalchemy import create_engine

# --- CONFIGURATION ---

# 1. DATABASE CONNECTION (Azure SQL via environment variables)
from urllib.parse import quote_plus

SERVER = os.environ.get('SQL_SERVER', 'ypyw-sql-ahmedsohail.database.windows.net')
DATABASE = os.environ.get('SQL_DATABASE', 'ypyw-bi-db')
SQL_ADMIN_USER = os.environ.get('SQL_ADMIN_USER', 'ypywadmin')
SQL_ADMIN_PASSWORD = os.environ.get('SQL_ADMIN_PASSWORD')
DRIVER = os.environ.get('SQL_DRIVER', 'ODBC Driver 18 for SQL Server')

if not SQL_ADMIN_PASSWORD:
    raise ValueError("SQL_ADMIN_PASSWORD environment variable not set")

# Connection String (pyodbc + ODBC Driver 18, encrypted Azure SQL connection)
odbc_params = quote_plus(
    f"Driver={{{DRIVER}}};"
    f"Server=tcp:{SERVER},1433;"
    f"Database={DATABASE};"
    f"Uid={SQL_ADMIN_USER};"
    f"Pwd={SQL_ADMIN_PASSWORD};"
    "Encrypt=yes;"
    "TrustServerCertificate=no;"
    "Connection Timeout=30;"
)
connection_url = f"mssql+pyodbc:///?odbc_connect={odbc_params}"
engine = create_engine(connection_url)

# 2. FOLDER PATHS (configurable via environment, relative fallback)
BASE_DIR = os.environ.get(
    'YPYW_BASE_DIR',
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "YourPaintingYourWay"),
)

WATCH_FOLDER = os.path.join(BASE_DIR, "DropZone")
PROCESSED_FOLDER = os.path.join(BASE_DIR, "Processed")

class IngestHandler(FileSystemEventHandler):
    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.csv'):
            print(f"\n--> New file detected: {event.src_path}")
            time.sleep(1) 
            process_data(event.src_path)

def process_data(filepath):
    try:
        print("Reading CSV...")
        # 1. READ
        df = pd.read_csv(filepath)
        
        # 2. CLEAN
        df.columns = df.columns.str.strip()
        
        # 3. UPLOAD TO SQL
        print(f"Uploading {len(df)} rows to SQL Server...")
        df.to_sql('RawEstimates', engine, if_exists='append', index=False)
        print("SUCCESS: Data saved to Database.")
        
        # 4. MOVE FILE
        filename = os.path.basename(filepath)
        destination = os.path.join(PROCESSED_FOLDER, filename)
        
        if os.path.exists(destination):
            timestamp = int(time.time())
            destination = os.path.join(PROCESSED_FOLDER, f"{timestamp}_{filename}")

        os.rename(filepath, destination)
        print(f"File moved to: {destination}")

    except Exception as e:
        print(f"ERROR: {e}")

if __name__ == "__main__":
    # Safety check: make sure folders exist
    if not os.path.exists(WATCH_FOLDER):
        os.makedirs(WATCH_FOLDER)
    if not os.path.exists(PROCESSED_FOLDER):
        os.makedirs(PROCESSED_FOLDER)

    print(f"System Online. Watching {WATCH_FOLDER}...")
    
    observer = Observer()
    observer.schedule(IngestHandler(), WATCH_FOLDER, recursive=False)
    observer.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        observer.join()