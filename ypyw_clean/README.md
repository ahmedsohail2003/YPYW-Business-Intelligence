# YPYW Business Intelligence Platform

A full-stack business intelligence platform built for **YourPaintingYourWay**, a high-volume residential painting company in the GTA. The system automates data ingestion from client estimate exports and surfaces business metrics through a web dashboard.

> **Note on Data:** The included `sample_estimates.csv` is a **synthetic dataset** with randomly generated names and amounts. It mirrors the schema of the real production data (500+ client estimates) used during development but contains no actual client information.

## Architecture

```
CSV Export (DropZone/)
        │
        ▼
┌─────────────────────┐
│  dataingest.py       │  Python ETL Pipeline
│  watchdog + pandas   │  Watch → Read → Clean → Load → Archive
│  + SQLAlchemy        │
└────────┬────────────┘
         ▼
┌─────────────────────┐
│  SQL Server (LocalDB)│  Relational schema: Estimates, SalesPeople,
│                      │  LeadSources, MarketingCosts
└────────┬────────────┘
         ▼
┌─────────────────────┐
│  .NET Blazor App     │  Web dashboard with Dapper ORM
│  (CPA/)              │  Targets Web, Desktop, Mobile (MAUI)
└─────────────────────┘
```

## Components

### 1. Automated ETL Pipeline (`dataingest.py`)
- **Watch:** Uses `watchdog` to monitor a DropZone folder for new CSV files in real time
- **Read:** Loads CSVs with pandas
- **Clean:** Strips and normalizes column headers
- **Load:** Uploads to SQL Server via SQLAlchemy (`RawEstimates` table)
- **Archive:** Moves processed files to a `Processed/` folder with timestamp-based collision handling

### 2. SQL Database Schema (`CPA/SQLQuery1.sql`)
- `RawEstimates` — Client estimates ingested from CSV
- `SalesPeople` — Sales team members for attribution tracking
- `LeadSources` — Marketing channels (Homestars, Google Ads, Referral, etc.)
- `MarketingCosts` — Monthly advertising spend per channel for ROI analysis

### 3. .NET Blazor Frontend (`CPA/`)
- Blazor Hybrid app targeting web, Android, iOS, Mac, and Windows
- `Estimate.cs` — Data model mapping to SQL columns
- `EstimateService.cs` — Service layer using Dapper ORM for async database queries
- `Estimates.razor` — Dashboard page displaying real-time estimate data

## Tech Stack
- **Backend:** Python 3, watchdog, pandas, SQLAlchemy
- **Database:** SQL Server (LocalDB), T-SQL
- **Frontend:** C# / .NET 8, Blazor Hybrid, MAUI, Dapper
- **Platforms:** Web, Windows, macOS, Android, iOS

## Setup

### Prerequisites
- Python 3.x with `watchdog`, `pandas`, `sqlalchemy`, `pyodbc`
- SQL Server LocalDB
- .NET 8 SDK

### Running the ETL Pipeline
```bash
pip install watchdog pandas sqlalchemy pyodbc
python dataingest.py
```
The script will monitor the `DropZone/` folder. Drop a CSV matching the estimate schema and it will be automatically ingested into SQL Server.

### Running the Blazor App
```bash
cd CPA/CPA/CPA.Web
dotnet run
```

## Status
This project is in active development (~60% complete). Current work focuses on expanding the Blazor dashboard with CRUD operations, adding data cleaning/currency parsing to the pipeline, and wiring up lead source attribution for marketing ROI analysis.
