using System;
using System.Collections.Generic;
using Coliseu.Identity.Domain.Entities;
using Xunit;

namespace Coliseu.Identity.Tests.Domain
{
    public class CompanyModuleTests
    {
        [Fact]
        public void Create_ShouldInitializeWithVersions()
        {
            // Arrange
            var companyId = Guid.NewGuid();
            var moduleSlug = "coliseu-dash";
            var apiKeyHash = "hash-123";
            var deviceLimit = 10;
            var versions = new List<string> { "Dash 1.0", "B.I 1.0" };

            // Act
            var module = CompanyModule.Create(
                companyId,
                moduleSlug,
                apiKeyHash,
                deviceLimit,
                versions: versions);

            // Assert
            Assert.NotNull(module);
            Assert.Equal(companyId, module.CompanyId);
            Assert.Equal(moduleSlug, module.ModuleSlug);
            Assert.Equal(deviceLimit, module.DeviceLimit);
            Assert.Equal(versions, module.Versions);
            Assert.Null(module.UpdatedAt);
        }

        [Fact]
        public void SetVersions_ShouldUpdateVersionsAndTimestamp()
        {
            // Arrange
            var companyId = Guid.NewGuid();
            var module = CompanyModule.Create(
                companyId,
                "coliseu-dash",
                "hash-123",
                10,
                versions: new List<string> { "Dash 1.0" });

            var newVersions = new List<string> { "Dash 1.0", "B.I 1.0", "B.I IA." };

            // Act
            module.SetVersions(newVersions);

            // Assert
            Assert.Equal(newVersions, module.Versions);
            Assert.NotNull(module.UpdatedAt);
            Assert.True(module.UpdatedAt > DateTime.MinValue);
        }
    }
}
