using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Admin.Handlers;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Interfaces;
using Coliseu.Identity.Infrastructure.Persistence;
using Coliseu.Identity.Infrastructure.Persistence.Repositories;
using Coliseu.Identity.Infrastructure.Security;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Coliseu.Identity.Tests.Domain;

public sealed class CreateCompanyHandlerTests
{
    private readonly IdentityDbContext _db;
    private readonly CompanyRepository _companyRepo;
    private readonly BranchRepository _branchRepo;
    private readonly AuditLogRepository _auditRepo;
    private readonly ICompanyKeyGenerator _keyGen;
    private readonly IEncryptionService _encryption;
    private readonly CreateCompanyHandler _handler;

    public CreateCompanyHandlerTests()
    {
        var options = new DbContextOptionsBuilder<IdentityDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        _db = new IdentityDbContext(options);
        _companyRepo = new CompanyRepository(_db);
        _branchRepo = new BranchRepository(_db);
        _auditRepo = new AuditLogRepository(_db);
        _keyGen = new CompanyKeyGenerator();
        var encOptions = Microsoft.Extensions.Options.Options.Create(new EncryptionOptions { Key = "dGVzdC1lbmNyeXB0aW9uLWtleS0zMmJ5dGVzLW9rISE=" });
        _encryption = new EncryptionService(encOptions);

        _handler = new CreateCompanyHandler(_companyRepo, _auditRepo, _keyGen, _encryption, _branchRepo);
    }

    [Fact(DisplayName = "CreateCompany: cadastrar sem filiais deve retornar falha")]
    public async Task HandleAsync_WithoutBranches_ShouldReturnFailure()
    {
        // Arrange
        var request = new CreateCompanyRequest
        {
            Name = "Empresa Sem Filial",
            Branches = new List<CreateCompanyBranchRequest>() // Vazio
        };

        // Act
        var result = await _handler.HandleAsync(request, Guid.NewGuid());

        // Assert
        Assert.False(result.IsSuccess);
        Assert.Equal("A criação de pelo menos uma filial é obrigatória.", result.Error);
    }

    [Fact(DisplayName = "CreateCompany: cadastrar com filiais válidas deve persistir empresa e filiais")]
    public async Task HandleAsync_WithBranches_ShouldCreateCompanyAndBranches()
    {
        // Arrange
        var request = new CreateCompanyRequest
        {
            Name = "Empresa Com Filiais",
            Branches = new List<CreateCompanyBranchRequest>
            {
                new CreateCompanyBranchRequest
                {
                    Name = "Filial Matriz",
                    ErpEmpresaId = 1,
                    ErpDeptoPadrao = 5,
                    ErpCentroPadrao = 2,
                    IsDefault = true
                },
                new CreateCompanyBranchRequest
                {
                    Name = "Filial Segunda",
                    ErpEmpresaId = 2,
                    ErpDeptoPadrao = 6,
                    ErpCentroPadrao = 3,
                    IsDefault = false
                }
            }
        };

        // Act
        var result = await _handler.HandleAsync(request, Guid.NewGuid());

        // Assert
        Assert.True(result.IsSuccess);
        Assert.NotNull(result.Value);

        // Verificar no banco de dados se a empresa e filiais existem
        var company = await _db.Companies.FirstOrDefaultAsync(c => c.Id == result.Value.CompanyId);
        Assert.NotNull(company);
        Assert.Equal("Empresa Com Filiais", company.Name);

        var branches = await _db.Branches.Where(b => b.CompanyId == company.Id).ToListAsync();
        Assert.Equal(2, branches.Count);

        var matrix = branches.FirstOrDefault(b => b.ErpEmpresaId == 1);
        Assert.NotNull(matrix);
        Assert.Equal("Filial Matriz", matrix.Name);
        Assert.True(matrix.IsDefault);

        var second = branches.FirstOrDefault(b => b.ErpEmpresaId == 2);
        Assert.NotNull(second);
        Assert.Equal("Filial Segunda", second.Name);
        Assert.False(second.IsDefault);
    }

    [Fact(DisplayName = "CreateCompany: cadastrar com Empresa ERP duplicada deve retornar falha")]
    public async Task HandleAsync_WithDuplicateErpEmpresaIds_ShouldReturnFailure()
    {
        // Arrange
        var request = new CreateCompanyRequest
        {
            Name = "Empresa Duplicada",
            Branches = new List<CreateCompanyBranchRequest>
            {
                new CreateCompanyBranchRequest { Name = "Matriz", ErpEmpresaId = 1, IsDefault = true },
                new CreateCompanyBranchRequest { Name = "Matriz Clone", ErpEmpresaId = 1 } // Duplicado
            }
        };

        // Act
        var result = await _handler.HandleAsync(request, Guid.NewGuid());

        // Assert
        Assert.False(result.IsSuccess);
        Assert.Contains("Não é permitido cadastrar filiais duplicadas", result.Error);
    }
}
