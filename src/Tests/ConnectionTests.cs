using NUnit.Framework;
using Raven.Client.ServerWide;
using Raven.Client.ServerWide.Operations;

namespace Tests;

[TestFixture]
public class ConnectionTests
{
    [CancelAfter(5000)]
    [Test]
    public void Should_establish_connection_to_single_node(CancellationToken cancellationToken)
    {
        var connectionUrl = Environment.GetEnvironmentVariable("RavenDBSingleNodeUrl");
        if (connectionUrl == null)
        {
            // Setting the environment variable is assumed to be checked by the CI pipeline
            Assert.Inconclusive("No RavenDBSingleNodeUrl environment variable set");
        }

        const string databaseName = "SingleNodeConnectionTests";
        var documentStore = new Raven.Client.Documents.DocumentStore
        {
            Urls = [connectionUrl],
            Database = databaseName,
        }.Initialize();

        Assert.DoesNotThrowAsync(async () =>
        {
            await documentStore.Maintenance.Server.SendAsync(new CreateDatabaseOperation(new DatabaseRecord(databaseName)), cancellationToken);
        });
    }

    [CancelAfter(5000)]
    [Test]
    public void Should_establish_connection_to_cluster(CancellationToken cancellationToken)
    {
        var connectionUrl = Environment.GetEnvironmentVariable("CommaSeparatedRavenClusterUrls");
        if (connectionUrl == null)
        {
            // Setting the environment variable is assumed to be checked by the CI pipeline
            Assert.Inconclusive("No CommaSeparatedRavenClusterUrls environment variable set");
        }

        const string databaseName = "ClusterConnectionTests";
        var documentStore = new Raven.Client.Documents.DocumentStore
        {
            Urls = connectionUrl.Split(','),
            Database = databaseName,
        }.Initialize();

        Assert.DoesNotThrowAsync(async () =>
        {
            await documentStore.Maintenance.Server.SendAsync(new CreateDatabaseOperation(new DatabaseRecord(databaseName)), cancellationToken);
        });
    }
}