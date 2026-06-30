using Coliseu.Identity.Domain.Entities;
using Xunit;

namespace Coliseu.Identity.Tests.Domain;

public sealed class ModuleSlugsTests
{
    [Theory]
    [InlineData(ModuleSlugs.ColiseuSpeed)]
    [InlineData(ModuleSlugs.AutoCenter)]
    [InlineData(ModuleSlugs.ColiseuDash)]
    [InlineData(ModuleSlugs.ControleGarantias)]
    [InlineData(ModuleSlugs.Nexus)]
    [InlineData(ModuleSlugs.Vision)]
    public void IsValid_ShouldReturnTrue_ForRegisteredSlugs(string slug)
    {
        // Act
        var result = ModuleSlugs.IsValid(slug);

        // Assert
        Assert.True(result);
    }

    [Theory]
    [InlineData("invalid-slug")]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null!)]
    public void IsValid_ShouldReturnFalse_ForUnregisteredSlugs(string slug)
    {
        // Act
        var result = ModuleSlugs.IsValid(slug);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void All_ShouldContainAllRegisteredSlugs()
    {
        // Act & Assert
        Assert.Contains(ModuleSlugs.ColiseuSpeed, ModuleSlugs.All);
        Assert.Contains(ModuleSlugs.AutoCenter, ModuleSlugs.All);
        Assert.Contains(ModuleSlugs.ColiseuDash, ModuleSlugs.All);
        Assert.Contains(ModuleSlugs.ControleGarantias, ModuleSlugs.All);
        Assert.Contains(ModuleSlugs.Nexus, ModuleSlugs.All);
        Assert.Contains(ModuleSlugs.Vision, ModuleSlugs.All);
        Assert.Equal(6, ModuleSlugs.All.Count);
    }
}
