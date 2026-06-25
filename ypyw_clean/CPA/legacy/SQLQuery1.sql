-- 1. Create the Sales People table (Sohail vs Ansr)
CREATE TABLE SalesPeople (
    Id INT PRIMARY KEY IDENTITY(1,1),
    Name NVARCHAR(50) NOT NULL
);

-- Seed it with the team
INSERT INTO SalesPeople (Name) VALUES ('Sohail'), ('Ansr');

-- 2. Create the Lead Sources table (Where did the job come from?)
CREATE TABLE LeadSources (
    Id INT PRIMARY KEY IDENTITY(1,1),
    Name NVARCHAR(50) NOT NULL
);

-- Seed it with common sources
INSERT INTO LeadSources (Name) VALUES ('Homestars'), ('Bark'), ('Facebook'), ('Google Ads'), ('Referral');

-- 3. Create the Marketing Costs table (The Monthly Bills)
CREATE TABLE MarketingCosts (
    Id INT PRIMARY KEY IDENTITY(1,1),
    CostDate DATE NOT NULL,          -- e.g., 2025-08-01
    Amount DECIMAL(18, 2) NOT NULL,  -- e.g., 500.00
    LeadSourceId INT FOREIGN KEY REFERENCES LeadSources(Id)
);

-- 4. Upgrade the Main Table (Add the "Tags")
-- We add these as NULL because old jobs might not have this info yet.
ALTER TABLE RawEstimates ADD SalesPersonId INT NULL REFERENCES SalesPeople(Id);
ALTER TABLE RawEstimates ADD LeadSourceId INT NULL REFERENCES LeadSources(Id);

-- Check if it worked
SELECT * FROM SalesPeople;
SELECT * FROM LeadSources;