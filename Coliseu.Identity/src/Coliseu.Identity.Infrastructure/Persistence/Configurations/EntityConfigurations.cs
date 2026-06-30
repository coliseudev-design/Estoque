using Coliseu.Identity.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Coliseu.Identity.Infrastructure.Persistence.Configurations;

public sealed class CompanyConfiguration : IEntityTypeConfiguration<Company>
{
    public void Configure(EntityTypeBuilder<Company> builder)
    {
        builder.ToTable("companies");

        builder.HasKey(c => c.Id);
        builder.Property(c => c.Id).ValueGeneratedNever();

        builder.Property(c => c.Name).HasMaxLength(200).IsRequired();
        builder.Property(c => c.CompanyKeyHash).HasMaxLength(64).IsRequired();
        builder.Property(c => c.FirebirdHost).HasMaxLength(255).IsRequired();
        builder.Property(c => c.FirebirdDatabasePath).HasMaxLength(500).IsRequired();
        builder.Property(c => c.FirebirdUser).HasMaxLength(100).IsRequired();
        builder.Property(c => c.FirebirdPasswordEncrypted).HasMaxLength(500).IsRequired();
        builder.Property(c => c.DeviceLimit).IsRequired();
        builder.Property(c => c.Status).HasConversion<int>().IsRequired();
        builder.Property(c => c.CreatedAt).IsRequired();

        builder.HasIndex(c => c.CompanyKeyHash).IsUnique();
        builder.HasIndex(c => c.Name);

        builder.HasMany(c => c.Devices)
            .WithOne(d => d.Company)
            .HasForeignKey(d => d.CompanyId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasMany<CompanyModule>()
            .WithOne(m => m.Company)
            .HasForeignKey(m => m.CompanyId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasMany(c => c.Branches)
            .WithOne(b => b.Company)
            .HasForeignKey(b => b.CompanyId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public sealed class DeviceConfiguration : IEntityTypeConfiguration<Device>
{
    public void Configure(EntityTypeBuilder<Device> builder)
    {
        builder.ToTable("devices");

        builder.HasKey(d => d.Id);
        builder.Property(d => d.Id).ValueGeneratedNever();

        builder.Property(d => d.CompanyId).IsRequired();
        builder.Property(d => d.ActivationKey).HasMaxLength(10).IsRequired();
        builder.Property(d => d.DeviceUuid).HasMaxLength(255);
        builder.Property(d => d.Name).HasMaxLength(150);
        builder.Property(d => d.Model).HasMaxLength(200);
        builder.Property(d => d.OS).HasMaxLength(100);
        builder.Property(d => d.AppVersion).HasMaxLength(50);
        builder.Property(d => d.Status).HasConversion<int>().IsRequired();
        builder.Property(d => d.ModuleSlug)
            .HasMaxLength(50)
            .IsRequired()
            .HasDefaultValue("coliseu-speed");
        builder.Property(d => d.FirstActivation).IsRequired();
        builder.Property(d => d.LastAccess).IsRequired();

        // One pending device per activation key
        builder.HasIndex(d => d.ActivationKey).IsUnique();

        // One device per UUID per company per module (backward: existing rows keep module='coliseu-speed')
        builder.HasIndex(d => new { d.DeviceUuid, d.CompanyId, d.ModuleSlug })
            .HasFilter("\"DeviceUuid\" IS NOT NULL")
            .HasDatabaseName("IX_devices_DeviceUuid_CompanyId_Module");

        builder.HasIndex(d => d.CompanyId);
        builder.HasIndex(d => d.ModuleSlug);

        builder.HasMany(d => d.Sessions)
            .WithOne(s => s.Device)
            .HasForeignKey(s => s.DeviceId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public sealed class CompanyModuleConfiguration : IEntityTypeConfiguration<CompanyModule>
{
    public void Configure(EntityTypeBuilder<CompanyModule> builder)
    {
        builder.ToTable("company_modules");

        builder.HasKey(m => m.Id);
        builder.Property(m => m.Id).ValueGeneratedNever();

        builder.Property(m => m.CompanyId).IsRequired();
        builder.Property(m => m.ModuleSlug).HasMaxLength(50).IsRequired();
        builder.Property(m => m.ApiKeyHash).HasMaxLength(64).IsRequired();
        builder.Property(m => m.DeviceLimit).IsRequired();
        builder.Property(m => m.IsActive).IsRequired().HasDefaultValue(true);
        builder.Property(m => m.MiddlewareBaseUrl).HasMaxLength(500);
        
        // Versions armazenadas como JSONB no PostgreSQL e SQLite
        builder.Property(m => m.Versions)
            .HasColumnType("jsonb")
            .HasConversion(
                v => System.Text.Json.JsonSerializer.Serialize(v, (System.Text.Json.JsonSerializerOptions?)null),
                v => System.Text.Json.JsonSerializer.Deserialize<List<string>>(v, (System.Text.Json.JsonSerializerOptions?)null) ?? new List<string>()
            )
            .IsRequired();

        builder.Property(m => m.CreatedAt).IsRequired();

        // One module slug per company
        builder.HasIndex(m => new { m.CompanyId, m.ModuleSlug })
            .IsUnique()
            .HasDatabaseName("IX_company_modules_CompanyId_ModuleSlug");

        // Fast API Key lookup
        builder.HasIndex(m => m.ApiKeyHash)
            .HasDatabaseName("IX_company_modules_ApiKeyHash");
    }
}

public sealed class SessionConfiguration : IEntityTypeConfiguration<Session>
{
    public void Configure(EntityTypeBuilder<Session> builder)
    {
        builder.ToTable("sessions");

        builder.HasKey(s => s.Id);
        builder.Property(s => s.Id).ValueGeneratedNever();

        builder.Property(s => s.DeviceId).IsRequired();
        builder.Property(s => s.RefreshToken).HasMaxLength(500).IsRequired();
        builder.Property(s => s.ExpiresAt).IsRequired();
        builder.Property(s => s.CreatedAt).IsRequired();
        builder.Property(s => s.IsRevoked).IsRequired().HasDefaultValue(false);

        builder.HasIndex(s => s.RefreshToken).IsUnique();
        builder.HasIndex(s => s.DeviceId);
    }
}

public sealed class PermissionGroupConfiguration : IEntityTypeConfiguration<PermissionGroup>
{
    public void Configure(EntityTypeBuilder<PermissionGroup> builder)
    {
        builder.ToTable("permission_groups");

        builder.HasKey(g => g.Id);
        builder.Property(g => g.Id).ValueGeneratedNever();

        builder.Property(g => g.Name).HasMaxLength(200).IsRequired();
        builder.Property(g => g.Description).HasMaxLength(500);

        // Permissions armazenadas como JSONB no PostgreSQL
        builder.Property(g => g.Permissions)
            .HasColumnType("jsonb")
            .HasConversion(
                v => System.Text.Json.JsonSerializer.Serialize(v, (System.Text.Json.JsonSerializerOptions?)null),
                v => System.Text.Json.JsonSerializer.Deserialize<List<string>>(v, (System.Text.Json.JsonSerializerOptions?)null) ?? new List<string>()
            )
            .IsRequired();

        builder.Property(g => g.CreatedAt).IsRequired();

        builder.HasMany(g => g.Users)
            .WithOne(u => u.PermissionGroup)
            .HasForeignKey(u => u.PermissionGroupId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

public sealed class AdminUserConfiguration : IEntityTypeConfiguration<AdminUser>
{
    public void Configure(EntityTypeBuilder<AdminUser> builder)
    {
        builder.ToTable("admin_users");

        builder.HasKey(a => a.Id);
        builder.Property(a => a.Id).ValueGeneratedNever();

        builder.Property(a => a.Email).HasMaxLength(255).IsRequired();
        builder.Property(a => a.Name).HasMaxLength(200);
        builder.Property(a => a.PasswordHash).HasMaxLength(255).IsRequired();
        builder.Property(a => a.Role).HasConversion<int>().IsRequired();
        builder.Property(a => a.IsActive).IsRequired().HasDefaultValue(true);
        builder.Property(a => a.CreatedAt).IsRequired();

        builder.HasIndex(a => a.Email).IsUnique();
    }
}

public sealed class AuditLogConfiguration : IEntityTypeConfiguration<AuditLog>
{
    public void Configure(EntityTypeBuilder<AuditLog> builder)
    {
        builder.ToTable("audit_logs");

        builder.HasKey(l => l.Id);
        builder.Property(l => l.Id).ValueGeneratedNever();

        builder.Property(l => l.Action).HasMaxLength(100).IsRequired();
        builder.Property(l => l.IpAddress).HasMaxLength(45);
        builder.Property(l => l.UserAgent).HasMaxLength(500);
        builder.Property(l => l.Details).HasMaxLength(2000);
        builder.Property(l => l.AdminEmail).HasMaxLength(200);
        builder.Property(l => l.CreatedAt).IsRequired();

        builder.HasIndex(l => l.CreatedAt);
        builder.HasIndex(l => l.Action);
        builder.HasIndex(l => l.CompanyId);
        builder.HasIndex(l => l.AdminEmail);
    }
}

public sealed class BranchConfiguration : IEntityTypeConfiguration<Branch>
{
    public void Configure(EntityTypeBuilder<Branch> builder)
    {
        builder.ToTable("branches");

        builder.HasKey(b => b.Id);
        builder.Property(b => b.Id).ValueGeneratedNever();

        builder.Property(b => b.CompanyId).IsRequired();
        builder.Property(b => b.Name).HasMaxLength(100).IsRequired();
        builder.Property(b => b.Cnpj).HasMaxLength(20);
        builder.Property(b => b.ErpEmpresaId).IsRequired();
        builder.Property(b => b.ErpDeptoPadrao).IsRequired().HasDefaultValue(0);
        builder.Property(b => b.ErpCentroPadrao).IsRequired().HasDefaultValue(0);
        builder.Property(b => b.IsDefault).IsRequired().HasDefaultValue(false);
        builder.Property(b => b.Status).HasConversion<int>().IsRequired();
        builder.Property(b => b.CreatedAt).IsRequired();
        builder.Property(b => b.UpdatedAt);

        builder.HasIndex(b => b.CompanyId);

        builder.HasIndex(b => new { b.CompanyId, b.ErpEmpresaId })
            .IsUnique()
            .HasDatabaseName("IX_branches_CompanyId_ErpEmpresaId");

        // Apenas uma filial pode ser IsDefault por Company
        builder.HasIndex(b => b.CompanyId)
            .IsUnique()
            .HasFilter("\"IsDefault\" = true")
            .HasDatabaseName("IX_branches_DefaultBranch");
    }
}

public sealed class PartnerConfiguration : IEntityTypeConfiguration<Partner>
{
    public void Configure(EntityTypeBuilder<Partner> builder)
    {
        builder.ToTable("partners");

        builder.HasKey(p => p.Id);
        builder.Property(p => p.Id).ValueGeneratedNever();

        builder.Property(p => p.Name).HasMaxLength(200).IsRequired();
        builder.Property(p => p.Cnpj).HasMaxLength(20).IsRequired();
        builder.Property(p => p.ContactName).HasMaxLength(150).IsRequired();
        builder.Property(p => p.Email).HasMaxLength(255).IsRequired();
        builder.Property(p => p.Phone).HasMaxLength(50).IsRequired();
        builder.Property(p => p.CreatedAt).IsRequired();

        builder.HasIndex(p => p.Cnpj).IsUnique();
        builder.HasIndex(p => p.Name);
    }
}

public sealed class LicenseRequestConfiguration : IEntityTypeConfiguration<LicenseRequest>
{
    public void Configure(EntityTypeBuilder<LicenseRequest> builder)
    {
        builder.ToTable("license_requests");

        builder.HasKey(r => r.Id);
        builder.Property(r => r.Id).ValueGeneratedNever();

        builder.Property(r => r.PartnerId).IsRequired();
        builder.Property(r => r.CompanyName).HasMaxLength(200).IsRequired();
        builder.Property(r => r.ClientCnpj).HasMaxLength(20).IsRequired();
        builder.Property(r => r.ClientCompanyType).HasMaxLength(50).IsRequired();
        builder.Property(r => r.CostCenterCode).HasMaxLength(50);
        builder.Property(r => r.DeptCode).HasMaxLength(50);
        builder.Property(r => r.PriceTableMode).HasMaxLength(50).IsRequired().HasDefaultValue("none");
        builder.Property(r => r.AllowNegativeStock).IsRequired().HasDefaultValue(false);
        builder.Property(r => r.FirebirdHost).HasMaxLength(255).IsRequired();
        builder.Property(r => r.FirebirdDatabasePath).HasMaxLength(500).IsRequired();
        builder.Property(r => r.FirebirdUser).HasMaxLength(100).IsRequired();
        builder.Property(r => r.FirebirdPasswordEncrypted).HasMaxLength(500).IsRequired();
        builder.Property(r => r.Notes).HasMaxLength(2000);
        builder.Property(r => r.Status).HasConversion<int>().IsRequired();
        builder.Property(r => r.RequestedAt).IsRequired();
        builder.Property(r => r.RejectReason).HasMaxLength(2000);
        builder.Property(r => r.BranchesJson);

        builder.HasIndex(r => r.PartnerId);
        builder.HasIndex(r => r.ClientCnpj);
        builder.HasIndex(r => r.Status);

        builder.HasOne(r => r.Partner)
            .WithMany(p => p.Requests)
            .HasForeignKey(r => r.PartnerId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(r => r.Company)
            .WithMany()
            .HasForeignKey(r => r.CompanyId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasMany(r => r.Modules)
            .WithOne()
            .HasForeignKey(m => m.LicenseRequestId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public sealed class LicenseRequestModuleConfiguration : IEntityTypeConfiguration<LicenseRequestModule>
{
    public void Configure(EntityTypeBuilder<LicenseRequestModule> builder)
    {
        builder.ToTable("license_request_modules");

        builder.HasKey(m => m.Id);
        builder.Property(m => m.Id).ValueGeneratedNever();

        builder.Property(m => m.LicenseRequestId).IsRequired();
        builder.Property(m => m.ModuleSlug).HasMaxLength(50).IsRequired();
        builder.Property(m => m.DeviceLimit).IsRequired();

        builder.HasIndex(m => m.LicenseRequestId);
        builder.HasIndex(m => new { m.LicenseRequestId, m.ModuleSlug }).IsUnique();
    }
}
