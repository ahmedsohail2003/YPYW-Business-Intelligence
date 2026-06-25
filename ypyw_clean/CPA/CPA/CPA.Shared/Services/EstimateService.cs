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

        public async Task<List<Estimate>> GetEstimatesAsync()
        {
            using (var connection = new SqlConnection(_connectionString))
            {
                var sql = "SELECT [Document Id] as DocumentId, [Client Name] as ClientName, [Status], [Estimate Amount] as EstimateAmount FROM RawEstimates";

                var result = await connection.QueryAsync<Estimate>(sql);
                return result.ToList();
            }
        }
    }
}