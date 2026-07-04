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

/* ---------------------------------------------------------------------
   6. MarketingCosts seed  (monthly ad spend per PAID channel, 2025)
        The amounts below are illustrative placeholders for the synthetic
        demo, not real ad spend; ROI multiples computed from them by
        vLeadSourceRoi are demonstrative only. Referral is organic
        (no rows -> $0 cost), which is what makes it the highest-ROI
        channel in vLeadSourceRoi below. Seeded only if the table is
        empty so re-runs stay idempotent.
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.MarketingCosts)
BEGIN
    ;WITH Months AS (
        SELECT CAST('2025-01-01' AS date) AS m
        UNION ALL
        SELECT DATEADD(month, 1, m) FROM Months WHERE m < '2025-12-01'
    ),
    Channels AS (
        SELECT v.LeadSourceId, v.MonthlyCost
        FROM (VALUES
            ((SELECT Id FROM dbo.LeadSources WHERE Name = N'Homestars'),  300.00),
            ((SELECT Id FROM dbo.LeadSources WHERE Name = N'Bark'),       200.00),
            ((SELECT Id FROM dbo.LeadSources WHERE Name = N'Facebook'),   250.00),
            ((SELECT Id FROM dbo.LeadSources WHERE Name = N'Google Ads'), 600.00)
        ) v(LeadSourceId, MonthlyCost)
    )
    INSERT INTO dbo.MarketingCosts (CostDate, Amount, LeadSourceId)
    SELECT m, MonthlyCost, LeadSourceId
    FROM Months CROSS JOIN Channels
    OPTION (MAXRECURSION 12);
END;
GO

/* ---------------------------------------------------------------------
   7. Analytics views  (reporting layer the BI dashboard reads from)
        All read from vEstimatesClean so currency/date parsing is applied
        once. Status funnel values are 'Won' / 'Lost' / 'Pending';
        win rate = Won / (Won + Lost), ignoring still-open 'Pending'.
   --------------------------------------------------------------------- */

-- 7a. Single-row KPI summary for the dashboard cards.
CREATE OR ALTER VIEW dbo.vKpiSummary AS
SELECT
    COUNT(*)                                                        AS TotalEstimates,
    SUM(EstimateAmount)                                             AS TotalPipeline,
    SUM(CASE WHEN Status = 'Won' THEN EstimateAmount ELSE 0 END)    AS WonValue,
    CAST( SUM(CASE WHEN Status = 'Won' THEN 1.0 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN Status IN ('Won', 'Lost') THEN 1.0 ELSE 0 END), 0)
        AS decimal(5, 4))                                           AS WinRate,
    CAST(AVG(EstimateAmount) AS decimal(12, 2))                     AS AvgDeal
FROM dbo.vEstimatesClean;
GO

-- 7b. Lead-source ROI: won revenue vs. marketing spend per channel.
CREATE OR ALTER VIEW dbo.vLeadSourceRoi AS
SELECT
    ls.Name                                                        AS LeadSource,
    COUNT(*)                                                        AS Leads,
    SUM(CASE WHEN e.Status = 'Won' THEN e.EstimateAmount ELSE 0 END) AS WonValue,
    COALESCE(mc.Cost, 0)                                           AS MarketingCost,
    CAST( SUM(CASE WHEN e.Status = 'Won' THEN 1.0 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN e.Status IN ('Won', 'Lost') THEN 1.0 ELSE 0 END), 0)
        AS decimal(5, 4))                                          AS WinRate,
    CASE WHEN COALESCE(mc.Cost, 0) = 0 THEN NULL
         ELSE CAST(SUM(CASE WHEN e.Status = 'Won' THEN e.EstimateAmount ELSE 0 END)
                   / mc.Cost AS decimal(10, 2))
    END                                                            AS RoiMultiple
FROM dbo.vEstimatesClean e
JOIN dbo.LeadSources ls ON ls.Id = e.LeadSourceId
LEFT JOIN (
    SELECT LeadSourceId, SUM(Amount) AS Cost
    FROM dbo.MarketingCosts
    GROUP BY LeadSourceId
) mc ON mc.LeadSourceId = e.LeadSourceId
GROUP BY ls.Name, mc.Cost;
GO

-- 7c. Sales attribution by team member.
CREATE OR ALTER VIEW dbo.vSalesByPerson AS
SELECT
    sp.Name                                                        AS SalesPerson,
    COUNT(*)                                                        AS Deals,
    SUM(CASE WHEN e.Status = 'Won' THEN e.EstimateAmount ELSE 0 END) AS WonValue,
    CAST( SUM(CASE WHEN e.Status = 'Won' THEN 1.0 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN e.Status IN ('Won', 'Lost') THEN 1.0 ELSE 0 END), 0)
        AS decimal(5, 4))                                          AS WinRate
FROM dbo.vEstimatesClean e
JOIN dbo.SalesPeople sp ON sp.Id = e.SalesPersonId
GROUP BY sp.Name;
GO

-- 7d. Monthly pipeline trend.
CREATE OR ALTER VIEW dbo.vMonthlyTrend AS
SELECT
    FORMAT(EstimateExpiresDate, 'yyyy-MM')                         AS [Month],
    COUNT(*)                                                       AS Estimates,
    SUM(EstimateAmount)                                            AS Pipeline,
    SUM(CASE WHEN Status = 'Won' THEN EstimateAmount ELSE 0 END)   AS WonValue
FROM dbo.vEstimatesClean
WHERE EstimateExpiresDate IS NOT NULL
GROUP BY FORMAT(EstimateExpiresDate, 'yyyy-MM');
GO
