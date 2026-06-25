/* =====================================================================
   YPYW Business Intelligence - Azure SQL Database schema
   Target : ypyw-bi-db on ypyw-sql-ahmedsohail.database.windows.net

   Azure SQL Database compatible:
     - No USE / CREATE DATABASE / filegroup / ON [PRIMARY] clauses
     - No cross-database references
     - Idempotent: every object guarded with IF NOT EXISTS
   Safe to run repeatedly.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. SalesPeople  (Sohail vs Ansr)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'SalesPeople')
BEGIN
    CREATE TABLE dbo.SalesPeople (
        Id   INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_SalesPeople PRIMARY KEY,
        Name NVARCHAR(50)  NOT NULL
    );
END;
GO

-- Seed the team (only if empty)
IF NOT EXISTS (SELECT 1 FROM dbo.SalesPeople)
BEGIN
    INSERT INTO dbo.SalesPeople (Name) VALUES (N'Sohail'), (N'Ansr');
END;
GO

/* ---------------------------------------------------------------------
   2. LeadSources  (Where did the job come from?)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'LeadSources')
BEGIN
    CREATE TABLE dbo.LeadSources (
        Id   INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_LeadSources PRIMARY KEY,
        Name NVARCHAR(50)  NOT NULL
    );
END;
GO

-- Seed common sources (only if empty)
IF NOT EXISTS (SELECT 1 FROM dbo.LeadSources)
BEGIN
    INSERT INTO dbo.LeadSources (Name)
    VALUES (N'Homestars'), (N'Bark'), (N'Facebook'), (N'Google Ads'), (N'Referral');
END;
GO

/* ---------------------------------------------------------------------
   3. MarketingCosts  (The monthly bills)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'MarketingCosts')
BEGIN
    CREATE TABLE dbo.MarketingCosts (
        Id           INT            NOT NULL IDENTITY(1,1) CONSTRAINT PK_MarketingCosts PRIMARY KEY,
        CostDate     DATE           NOT NULL,            -- e.g. 2025-08-01
        Amount       DECIMAL(18, 2) NOT NULL,            -- e.g. 500.00
        LeadSourceId INT            NULL
            CONSTRAINT FK_MarketingCosts_LeadSources
                FOREIGN KEY REFERENCES dbo.LeadSources(Id)
    );
END;
GO

/* ---------------------------------------------------------------------
   4. RawEstimates  (Main table - columns mirror the source CSV)
        CSV columns: Document Id, Client Name, Estimate Expires Date,
                     Status, Estimate Amount
        SalesPersonId / LeadSourceId are analytics "tags" added on top.
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'RawEstimates')
BEGIN
    CREATE TABLE dbo.RawEstimates (
        EstimateRowId           INT            IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_RawEstimates PRIMARY KEY,
        [Document Id]           INT            NOT NULL,
        [Client Name]           VARCHAR(500)   NULL,
        [Estimate Expires Date] NVARCHAR(50)   NULL,   -- raw text; parsed in vEstimatesClean
        [Status]                VARCHAR(50)    NULL,
        [Estimate Amount]       NVARCHAR(50)   NULL,   -- raw currency text e.g. '$24,399.00'; parsed in vEstimatesClean
        SalesPersonId           INT            NULL,
        LeadSourceId            INT            NULL
    );
END;
GO

/* 4c. Non-unique index on [Document Id] to keep lookups fast now that it is
       no longer the primary key (guarded so re-runs don't fail). */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_RawEstimates_DocumentId'
                 AND object_id = OBJECT_ID(N'dbo.RawEstimates'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_RawEstimates_DocumentId
        ON dbo.RawEstimates ([Document Id]);
END;
GO

/* 4a. Tag columns - added defensively in case RawEstimates pre-existed
       without them (mirrors the original ALTER TABLE statements). */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID(N'dbo.RawEstimates') AND name = N'SalesPersonId')
BEGIN
    ALTER TABLE dbo.RawEstimates ADD SalesPersonId INT NULL;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID(N'dbo.RawEstimates') AND name = N'LeadSourceId')
BEGIN
    ALTER TABLE dbo.RawEstimates ADD LeadSourceId INT NULL;
END;
GO

/* 4b. Foreign keys for the tag columns (guarded so re-runs don't fail). */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_RawEstimates_SalesPeople')
BEGIN
    ALTER TABLE dbo.RawEstimates
        ADD CONSTRAINT FK_RawEstimates_SalesPeople
            FOREIGN KEY (SalesPersonId) REFERENCES dbo.SalesPeople(Id);
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_RawEstimates_LeadSources')
BEGIN
    ALTER TABLE dbo.RawEstimates
        ADD CONSTRAINT FK_RawEstimates_LeadSources
            FOREIGN KEY (LeadSourceId) REFERENCES dbo.LeadSources(Id);
END;
GO

/* ---------------------------------------------------------------------
   5. vEstimatesClean  (typed/cleaned projection over the raw landing table)
        RawEstimates is a faithful raw archive of the source CSV (currency
        and date kept as text exactly as exported). This view parses them
        into proper analytics types:
          '$24,399.00'  ->  DECIMAL(12,2)
          date text     ->  DATE   (NULL-safe via TRY_CONVERT)
        Intended read path for reporting and the Blazor dashboard — queries
        should target this view rather than the raw-text table.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vEstimatesClean AS
SELECT
    EstimateRowId,
    [Document Id]                                               AS DocumentId,
    [Client Name]                                               AS ClientName,
    TRY_CONVERT(date, [Estimate Expires Date])                  AS EstimateExpiresDate,
    [Status]                                                    AS Status,
    TRY_CONVERT(decimal(12, 2),
        REPLACE(REPLACE([Estimate Amount], '$', ''), ',', ''))  AS EstimateAmount,
    SalesPersonId,
    LeadSourceId
FROM dbo.RawEstimates;
GO
