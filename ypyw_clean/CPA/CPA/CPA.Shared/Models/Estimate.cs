namespace CPA.Shared.Models
{
    public class Estimate
    {
        // These match the columns in your SQL Database
        public int? DocumentId { get; set; }
        public string? ClientName { get; set; }
        public string? Status { get; set; }
        public decimal? EstimateAmount { get; set; }
    }
}