using NUnit.Framework;
using Raven.Client.ServerWide;
using Raven.Client.ServerWide.Operations;

namespace Tests;

[TestFixture]
public class ConnectionTests
{
    [CancelAfter(5000)]
    [Test]
    public void Should_establish_connection(CancellationToken cancellationToken)
    {
        var connectionUrl = Environment.GetEnvironmentVariable("RavenDBSingleNodeUrl");
        if (connectionUrl == null)
        {
            // Setting the environment variable is assumed to be checked by the CI pipeline
            Assert.Inconclusive("No RavenDBSingleNodeUrl environment variable set");
        }

        var documentStore = new Raven.Client.Documents.DocumentStore
        {
            Urls = [connectionUrl],
            Database = "ConnectionTests",
        }.Initialize();

        Assert.DoesNotThrowAsync(async () =>
        {
            await documentStore.Maintenance.Server.SendAsync(new CreateDatabaseOperation(new DatabaseRecord("ConnectionTests")), cancellationToken);
        });
    }
}