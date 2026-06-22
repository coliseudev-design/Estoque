using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.EntityFrameworkCore;

namespace Coliseu.Identity.Infrastructure.Persistence.Repositories;

public sealed class CompanyRepository : ICompanyRepository
{
    private readonly IdentityDbContext _db;
    public CompanyRepository(IdentityDbContext db) => _db = db;

    public async Task<Company?> GetByKeyHashAsync(string companyKeyHash, CancellationToken ct = default)
        => await _db.Companies
            .Include(c => c.Devices.Where(d => d.Status == DeviceStatus.Active))
            .FirstOrDefaultAsync(c => c.CompanyKeyHash == companyKeyHash, ct);

    public async Task<Company?> GetByIdWithDevicesAsync(Guid id, CancellationToken ct = default)
        => await _db.Companies
            .Include(c => c.Devices)
            .FirstOrDefaultAsync(c => c.Id == id, ct);

    public async Task<Company?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.Companies.FindAsync([id], ct);

    public async Task<(List<Company> Items, int TotalCount)> GetAllAsync(
        int page, int pageSize, string? search = null, CancellationToken ct = default)
    {
        var query = _db.Companies.AsQueryable();
        if (!string.IsNullOrWhiteSpace(search))
            query = query.Where(c => c.Name.Contains(search));

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        return (items, total);
    }

    public async Task AddAsync(Company company, CancellationToken ct = default)
        => await _db.Companies.AddAsync(company, ct);

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);

    public async Task DeleteAsync(Guid id, CancellationToken ct = default)
    {
        var company = await _db.Companies.FindAsync([id], ct);
        if (company is not null) _db.Companies.Remove(company);
    }
}

public sealed class DeviceRepository : IDeviceRepository
{
    private readonly IdentityDbContext _db;
    public DeviceRepository(IdentityDbContext db) => _db = db;

    public async Task<Device?> GetByUuidAndCompanyAsync(
        string deviceUuid, Guid companyId, CancellationToken ct = default)
        => await _db.Devices
            .FirstOrDefaultAsync(d => d.DeviceUuid == deviceUuid && d.CompanyId == companyId, ct);

    public async Task<Device?> GetByActivationKeyAsync(string activationKey, CancellationToken ct = default)
        => await _db.Devices
            .FirstOrDefaultAsync(d => d.ActivationKey == activationKey, ct);

    public async Task<Device?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.Devices.FindAsync([id], ct);

    public async Task<int> CountActiveByCompanyAsync(Guid companyId, CancellationToken ct = default)
        => await _db.Devices
            .CountAsync(d => d.CompanyId == companyId && d.Status == DeviceStatus.Active, ct);

    public async Task<(List<Device> Items, int TotalCount)> GetByCompanyAsync(
        Guid companyId, int page, int pageSize, CancellationToken ct = default)
    {
        var query = _db.Devices.Where(d => d.CompanyId == companyId);
        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(d => d.LastAccess)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);
        return (items, total);
    }

    public async Task AddAsync(Device device, CancellationToken ct = default)
        => await _db.Devices.AddAsync(device, ct);

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class SessionRepository : ISessionRepository
{
    private readonly IdentityDbContext _db;
    public SessionRepository(IdentityDbContext db) => _db = db;

    public async Task<Session?> GetByRefreshTokenAsync(string refreshToken, CancellationToken ct = default)
        => await _db.Sessions
            .Include(s => s.Device)
            .FirstOrDefaultAsync(s => s.RefreshToken == refreshToken, ct);

    public async Task RevokeAllByDeviceAsync(Guid deviceId, CancellationToken ct = default)
    {
        var activeSessions = await _db.Sessions
            .Where(s => s.DeviceId == deviceId && !s.IsRevoked)
            .ToListAsync(ct);

        foreach (var session in activeSessions)
            session.Revoke();
    }

    public async Task AddAsync(Session session, CancellationToken ct = default)
        => await _db.Sessions.AddAsync(session, ct);

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class AdminUserRepository : IAdminUserRepository
{
    private readonly IdentityDbContext _db;
    public AdminUserRepository(IdentityDbContext db) => _db = db;

    public async Task<AdminUser?> GetByEmailAsync(string email, CancellationToken ct = default)
        => await _db.AdminUsers
            .Include(a => a.PermissionGroup)
            .FirstOrDefaultAsync(a => a.Email == email, ct);

    public async Task<AdminUser?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.AdminUsers
            .Include(a => a.PermissionGroup)
            .FirstOrDefaultAsync(a => a.Id == id, ct);

    public async Task<List<AdminUser>> GetAllAsync(CancellationToken ct = default)
        => await _db.AdminUsers
            .Include(a => a.PermissionGroup)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync(ct);

    public async Task AddAsync(AdminUser adminUser, CancellationToken ct = default)
        => await _db.AdminUsers.AddAsync(adminUser, ct);

    public void Remove(AdminUser adminUser)
        => _db.AdminUsers.Remove(adminUser);

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class PermissionGroupRepository : IPermissionGroupRepository
{
    private readonly IdentityDbContext _db;
    public PermissionGroupRepository(IdentityDbContext db) => _db = db;

    public async Task<List<PermissionGroup>> GetAllAsync(CancellationToken ct = default)
        => await _db.PermissionGroups
            .OrderBy(g => g.Name)
            .ToListAsync(ct);

    public async Task<PermissionGroup?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.PermissionGroups.FindAsync([id], ct);

    public async Task AddAsync(PermissionGroup group, CancellationToken ct = default)
        => await _db.PermissionGroups.AddAsync(group, ct);

    public void Remove(PermissionGroup group)
        => _db.PermissionGroups.Remove(group);

    public async Task<int> CountUsersByGroupAsync(Guid groupId, CancellationToken ct = default)
        => await _db.AdminUsers.CountAsync(a => a.PermissionGroupId == groupId, ct);

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class AuditLogRepository : IAuditLogRepository
{
    private readonly IdentityDbContext _db;
    public AuditLogRepository(IdentityDbContext db) => _db = db;

    public async Task AddAsync(AuditLog log, CancellationToken ct = default)
        => await _db.AuditLogs.AddAsync(log, ct);

    public async Task<(List<AuditLog> Items, int TotalCount)> GetAllAsync(
        int page, int pageSize, Guid? companyId = null, string? action = null,
        DateTime? from = null, DateTime? to = null, CancellationToken ct = default)
    {
        var query = _db.AuditLogs.AsQueryable();

        if (companyId.HasValue)
            query = query.Where(l => l.CompanyId == companyId);
        if (!string.IsNullOrWhiteSpace(action))
            query = query.Where(l => l.Action == action);
        if (from.HasValue)
            query = query.Where(l => l.CreatedAt >= from.Value);
        if (to.HasValue)
            query = query.Where(l => l.CreatedAt <= to.Value);

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(l => l.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        return (items, total);
    }

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class CompanyModuleRepository : ICompanyModuleRepository
{
    private readonly IdentityDbContext _db;
    public CompanyModuleRepository(IdentityDbContext db) => _db = db;

    public async Task<CompanyModule?> GetByApiKeyHashAsync(string apiKeyHash, CancellationToken ct = default)
        => await _db.CompanyModules
            .Include(m => m.Company)
            .FirstOrDefaultAsync(m => m.ApiKeyHash == apiKeyHash && m.IsActive, ct);

    public async Task<CompanyModule?> GetByCompanyAndSlugAsync(Guid companyId, string moduleSlug, CancellationToken ct = default)
        => await _db.CompanyModules
            .FirstOrDefaultAsync(m => m.CompanyId == companyId && m.ModuleSlug == moduleSlug, ct);

    public async Task<List<CompanyModule>> GetByCompanyAsync(Guid companyId, CancellationToken ct = default)
        => await _db.CompanyModules
            .Where(m => m.CompanyId == companyId)
            .OrderBy(m => m.ModuleSlug)
            .ToListAsync(ct);

    public async Task<bool> IsActiveAsync(Guid companyId, string moduleSlug, CancellationToken ct = default)
        => await _db.CompanyModules
            .AnyAsync(m => m.CompanyId == companyId && m.ModuleSlug == moduleSlug && m.IsActive, ct);

    public async Task AddAsync(CompanyModule module, CancellationToken ct = default)
        => await _db.CompanyModules.AddAsync(module, ct);

    public async Task RemoveAsync(Guid moduleId, CancellationToken ct = default)
    {
        var module = await _db.CompanyModules.FindAsync([moduleId], ct);
        if (module is not null) _db.CompanyModules.Remove(module);
    }

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class BranchRepository : IBranchRepository
{
    private readonly IdentityDbContext _db;
    public BranchRepository(IdentityDbContext db) => _db = db;

    public async Task<Branch?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.Branches.FindAsync([id], ct);

    public async Task<Branch?> GetByErpIdAsync(Guid companyId, int erpEmpresaId, CancellationToken ct = default)
        => await _db.Branches
            .FirstOrDefaultAsync(b => b.CompanyId == companyId && b.ErpEmpresaId == erpEmpresaId, ct);

    public async Task<List<Branch>> GetByCompanyAsync(Guid companyId, CancellationToken ct = default)
        => await _db.Branches
            .Where(b => b.CompanyId == companyId)
            .OrderByDescending(b => b.IsDefault)
            .ThenBy(b => b.Name)
            .ToListAsync(ct);

    public async Task AddAsync(Branch branch, CancellationToken ct = default)
        => await _db.Branches.AddAsync(branch, ct);

    public async Task DeleteAsync(Guid id, CancellationToken ct = default)
    {
        var branch = await _db.Branches.FindAsync([id], ct);
        if (branch is not null) _db.Branches.Remove(branch);
    }

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class PartnerRepository : IPartnerRepository
{
    private readonly IdentityDbContext _db;
    public PartnerRepository(IdentityDbContext db) => _db = db;

    public async Task<Partner?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.Partners.FindAsync([id], ct);

    public async Task<Partner?> GetByCnpjAsync(string cnpj, CancellationToken ct = default)
        => await _db.Partners.FirstOrDefaultAsync(p => p.Cnpj == cnpj, ct);

    public async Task<(List<Partner> Items, int TotalCount)> GetAllAsync(
        int page, int pageSize, string? search = null, CancellationToken ct = default)
    {
        var query = _db.Partners.AsQueryable();
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(p => p.Name.Contains(search) || p.Cnpj.Contains(search));
        }

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(p => p.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        return (items, total);
    }

    public async Task AddAsync(Partner partner, CancellationToken ct = default)
        => await _db.Partners.AddAsync(partner, ct);

    public async Task DeleteAsync(Guid id, CancellationToken ct = default)
    {
        var partner = await _db.Partners.FindAsync([id], ct);
        if (partner is not null) _db.Partners.Remove(partner);
    }

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}

public sealed class LicenseRequestRepository : ILicenseRequestRepository
{
    private readonly IdentityDbContext _db;
    public LicenseRequestRepository(IdentityDbContext db) => _db = db;

    public async Task<LicenseRequest?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.LicenseRequests
            .Include(r => r.Partner)
            .Include(r => r.Modules)
            .FirstOrDefaultAsync(r => r.Id == id, ct);

    public async Task<LicenseRequest?> GetByIdWithoutIncludesAsync(Guid id, CancellationToken ct = default)
        => await _db.LicenseRequests.FindAsync([id], ct);

    public async Task<(List<LicenseRequest> Items, int TotalCount)> GetAllAsync(
        int page, 
        int pageSize, 
        string? search = null, 
        RequestStatus? status = null, 
        Guid? partnerId = null, 
        CancellationToken ct = default)
    {
        var query = _db.LicenseRequests
            .Include(r => r.Partner)
            .Include(r => r.Modules)
            .AsQueryable();

        if (status.HasValue)
        {
            query = query.Where(r => r.Status == status.Value);
        }

        if (partnerId.HasValue)
        {
            query = query.Where(r => r.PartnerId == partnerId.Value);
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(r => r.ClientCnpj.Contains(search) || r.Partner.Name.Contains(search));
        }

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(r => r.RequestedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        return (items, total);
    }

    public async Task AddAsync(LicenseRequest request, CancellationToken ct = default)
        => await _db.LicenseRequests.AddAsync(request, ct);

    public async Task DeleteAsync(Guid id, CancellationToken ct = default)
    {
        var request = await _db.LicenseRequests.FindAsync([id], ct);
        if (request is not null) _db.LicenseRequests.Remove(request);
    }

    public async Task SaveChangesAsync(CancellationToken ct = default)
        => await _db.SaveChangesAsync(ct);
}
