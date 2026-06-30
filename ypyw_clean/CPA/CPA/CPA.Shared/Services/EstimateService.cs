using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using CPA.Shared.Models;

namespace CPA.Shared.Services
{
    public class EstimateService
    {
        // Connection string is sourced from configuration / environment (Azure SQL).
        // Configure via ConnectionStrings:YpywDatabase (e.g. env var ConnectionStrings__YpywDatabase).
        private readonly string _connectionString;

        public EstimateService(IConfiguration configuration)
        {
            _connectionString = configuration.GetConnectionString("YpywDatabase")
                ?? throw new InvalidOperationException(
                    "Connection string 'YpywDatabase' is not configured. " +
                    "Set ConnectionStrings__YpywDatabase in the environment.");
        }

        private SqlConnection Open() => new SqlConnection(_connectionString);

        // --- Detail list (the Estimates table page) -----------------------------
        public async Task<List<Estimate>> GetEstimatesAsync()
        {
            using var connection = Open();
            const string sql =
                "SELECT DocumentId, ClientName, Status, EstimateAmount FROM dbo.vEstimatesClean";
            var result = await connection.QueryAsync<Estimate>(sql);
            return result.ToList();
        }

        // --- Dashboard analytics (read from the reporting views) ----------------
        public async Task<KpiSummary> GetKpiSummaryAsync()
        {
            using var connection = Open();
            const string sql =
                "SELECT TotalEstimates, TotalPipeline, WonValue, WinRate, AvgDeal FROM dbo.vKpiSummary";
            return await connection.QuerySingleAsync<KpiSummary>(sql);
        }

        public async Task<List<LeadSourceRoi>> GetLeadSourceRoiAsync()
        {
            using var connection = Open();
            const string sql =
                "SELECT LeadSource, Leads, WonValue, MarketingCost, WinRate, RoiMultiple " +
                "FROM dbo.vLeadSourceRoi ORDER BY WonValue DESC";
            var result = await connection.QueryAsync<LeadSourceRoi>(sql);
            return result.ToList();
        }

        public async Task<List<SalesByPerson>> GetSalesByPersonAsync()
        {
            using var connection = Open();
            const string sql =
                "SELECT SalesPerson, Deals, WonValue, WinRate " +
                "FROM dbo.vSalesByPerson ORDER BY WonValue DESC";
            var result = await connection.QueryAsync<SalesByPerson>(sql);
            return result.ToList();
        }

        public async Task<List<MonthlyTrend>> GetMonthlyTrendAsync()
        {
            using var connection = Open();
            const string sql =
                "SELECT [Month], Estimates, Pipeline, WonValue " +
                "FROM dbo.vMonthlyTrend ORDER BY [Month]";
            var result = await connection.QueryAsync<MonthlyTrend>(sql);
            return result.ToList();
        }
    }
}
