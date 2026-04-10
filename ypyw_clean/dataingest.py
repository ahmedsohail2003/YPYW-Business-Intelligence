import time
import os
import pandas as pd
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from sqlalchemy import create_engine

# --- CONFIGURATION ---

# 1. DATABASE CONNECTION
SERVER = r'(localdb)\MSSQLLocalDB' 
DATABASE = 'YourPaintingYourWay'
DRIVER = 'ODBC Driver 17 for SQL Server'

# Connection String
connection_url = f"mssql+pyodbc://@{SERVER}/{DATABASE}?driver={DRIVER}&trusted_connection=yes"
engine = create_engine(connection_url)

# 2. FOLDER PATHS
# I added your specific username 'sohai' here
BASE_DIR = r"C:\Users\sohai\Documents\YourPaintingYourWay"

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