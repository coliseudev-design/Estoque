using System.Reflection;
using FluentAssertions;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;
using ColiseuSpeed.Worker.Config;
using ColiseuSpeed.Worker.Services;

namespace ColiseuSpeed.Worker.Tests;

public class SQLiteIsolationTests
{
    [Fact]
    public void DeltaCacheService_ComSufixo_DeveCriarPastaComSufixo()
    {
        // Arrange
        var workerOpts = new WorkerOptions
        {
            ServiceSuffix = "PIVETA"
        };
        var optionsMock = new Mock<IOptions<WorkerOptions>>();
        optionsMock.Setup(o => o.Value).Returns(workerOpts);

        // Act
        var deltaCache = new DeltaCacheService(optionsMock.Object);

        // Assert using reflection to read the private field _dbPath
        var dbPathField = typeof(DeltaCacheService).GetField("_dbPath", BindingFlags.NonPublic | BindingFlags.Instance);
        dbPathField.Should().NotBeNull();
        var dbPath = dbPathField!.GetValue(deltaCache) as string;
        dbPath.Should().NotBeNull();
        dbPath.Should().Contain("Worker_PIVETA");
        dbPath.Should().Contain("sync_cache.sqlite");
    }

    [Fact]
    public void DeltaCacheService_SemSufixo_DeveUsarPastaPadraoWorker()
    {
        // Arrange
        var workerOpts = new WorkerOptions
        {
            ServiceSuffix = ""
        };
        var optionsMock = new Mock<IOptions<WorkerOptions>>();
        optionsMock.Setup(o => o.Value).Returns(workerOpts);

        // Act
        var deltaCache = new DeltaCacheService(optionsMock.Object);

        // Assert
        var dbPathField = typeof(DeltaCacheService).GetField("_dbPath", BindingFlags.NonPublic | BindingFlags.Instance);
        dbPathField.Should().NotBeNull();
        var dbPath = dbPathField!.GetValue(deltaCache) as string;
        dbPath.Should().NotBeNull();
        dbPath.Should().Contain("Worker");
        dbPath.Should().NotContain("Worker_");
        dbPath.Should().Contain("sync_cache.sqlite");
    }

    [Fact]
    public void DeltaCacheService_ComCaracteresEspeciaisNoSufixo_DeveSanitizarPasta()
    {
        // Arrange
        var workerOpts = new WorkerOptions
        {
            ServiceSuffix = "Piveta & Filial/2"
        };
        var optionsMock = new Mock<IOptions<WorkerOptions>>();
        optionsMock.Setup(o => o.Value).Returns(workerOpts);

        // Act
        var deltaCache = new DeltaCacheService(optionsMock.Object);

        // Assert
        var dbPathField = typeof(DeltaCacheService).GetField("_dbPath", BindingFlags.NonPublic | BindingFlags.Instance);
        dbPathField.Should().NotBeNull();
        var dbPath = dbPathField!.GetValue(deltaCache) as string;
        dbPath.Should().NotBeNull();
        // A sanitização deve remover " & " e "/" resultando em "PivetaFilial2"
        dbPath.Should().Contain("Worker_PivetaFilial2");
        dbPath.Should().Contain("sync_cache.sqlite");
    }
}
