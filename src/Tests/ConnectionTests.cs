using NUnit.Framework;
using Raven.Client.ServerWide;
using Raven.Client.ServerWide.Operations;

namespace Tests;

[TestFixture]
public class ConnectionTests
{
    [CancelAfter(5000)]
    [TestCaseSource(nameof(ValidUrls))]
    public void Should_establish_connection(string? connectionUrl, string environmentVariable)
    {
        if (connectionUrl is null)
        {
            // Setting the environment variable is assumed to be checked by the CI pipeline
            Assert.Ignore($"No '{environmentVariable}' environment variable set");
        }

        var databaseName = $"{environmentVariable}ConnectionTests";
        var documentStore = new Raven.Client.Documents.DocumentStore
        {
            Urls = connectionUrl.Split(','),
            Database = databaseName,
        }.Initialize();

        Assert.DoesNotThrowAsync(async () =>
        {
            await documentStore.Maintenance.Server.SendAsync(new CreateDatabaseOperation(new DatabaseRecord(databaseName)), TestContext.CurrentContext.CancellationToken);
        });
    }

    public static IEnumerable<string?[]> ValidUrls()
    {
        yield return [Environment.GetEnvironmentVariable("RavenDBSingleNodeUrl"), "RavenDBSingleNodeUrl"];
        yield return [Environment.GetEnvironmentVariable("CommaSeparatedRavenClusterUrls"), "CommaSeparatedRavenClusterUrls"];
    }
}