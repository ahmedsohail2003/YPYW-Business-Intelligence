namespace CPA.Shared.Models
{
    public class Estimate
    {
        // These match the columns in your SQL Database
        public string? DocumentId { get; set; }
        public string? ClientName { get; set; }
        public string? Status { get; set; }
        public string? EstimateAmount { get; set; }
    }
}