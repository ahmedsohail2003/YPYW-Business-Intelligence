using Dapper;
using Microsoft.Data.SqlClient;
using CPA.Shared.Models;

namespace CPA.Shared.Services
{
    public class EstimateService
    {
        // Connection String for LocalDB
        private readonly string _connectionString = @"Server=(localdb)\MSSQLLocalDB;Database=YourPaintingYourWay;Trusted_Connection=True;";

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