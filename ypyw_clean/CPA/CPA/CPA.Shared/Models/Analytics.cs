namespace CPA.Shared.Models
{
    // DTOs for the BI dashboard. Property names match the column aliases
    // returned by the dbo.vKpiSummary / vLeadSourceRoi / vSalesByPerson /
    // vMonthlyTrend views so Dapper can map them by name.

    public class KpiSummary
    {
        public int TotalEstimates { get; set; }
        public decimal TotalPipeline { get; set; }
        public decimal WonValue { get; set; }
        public decimal? WinRate { get; set; }   // Won / (Won + Lost); null if no closed deals
        public decimal? AvgDeal { get; set; }
    }

    public class LeadSourceRoi
    {
        public string? LeadSource { get; set; }
        public int Leads { get; set; }
        public decimal WonValue { get; set; }
        public decimal MarketingCost { get; set; }
        public decimal? WinRate { get; set; }
        public decimal? RoiMultiple { get; set; }   // WonValue / MarketingCost; null when organic ($0 spend)
    }

    public class SalesByPerson
    {
        public string? SalesPerson { get; set; }
        public int Deals { get; set; }
        public decimal WonValue { get; set; }
        public decimal? WinRate { get; set; }
    }

    public class MonthlyTrend
    {
        public string? Month { get; set; }
        public int Estimates { get; set; }
        public decimal Pipeline { get; set; }
        public decimal WonValue { get; set; }
    }
}
