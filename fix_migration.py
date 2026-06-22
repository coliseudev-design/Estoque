import re

file_path = r'c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\Coliseu.Identity\src\Coliseu.Identity.Infrastructure\Persistence\Migrations\20260420194917_AddBranchesTable.cs'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

def get_sql(table, column, type_, default=None):
    constraint = 'NOT NULL'
    if default is not None:
        constraint += f" DEFAULT {default}"
    else:
        if type_ != 'uuid' and column not in ['Name', 'PermissionGroupId']:
            constraint = 'NULL'
    
    if column == 'Name': constraint = 'NULL'
    if column == 'PermissionGroupId': constraint = 'NULL'
    if column == 'AdminEmail': constraint = "NOT NULL DEFAULT ''"
    
    return f'''
            migrationBuilder.Sql(@"
            DO $$$$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = '{table}' AND column_name = '{column}'
                ) THEN
                    ALTER TABLE {table} ADD COLUMN ""{column}"" {type_} {constraint};
                END IF;
            END $$$$;");
'''

replacements = [
    (
        '''            migrationBuilder.AddColumn<string>(
                name: "ModuleSlug",
                table: "devices",
                type: "character varying(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "coliseu-sales");''',
        get_sql('devices', 'ModuleSlug', 'character varying(50)', "'coliseu-sales'")
    ),
    (
        '''            migrationBuilder.AddColumn<bool>(
                name: "AllowNegativeStock",
                table: "companies",
                type: "boolean",
                nullable: false,
                defaultValue: false);''',
        get_sql('companies', 'AllowNegativeStock', 'boolean', 'false')
    ),
    (
        '''            migrationBuilder.AddColumn<string>(
                name: "PriceTableMode",
                table: "companies",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "markup");''',
        get_sql('companies', 'PriceTableMode', 'character varying(20)', "'markup'")
    ),
    (
        '''            migrationBuilder.AddColumn<string>(
                name: "AdminEmail",
                table: "audit_logs",
                type: "character varying(150)",
                maxLength: 150,
                nullable: false,
                defaultValue: "");''',
        get_sql('audit_logs', 'AdminEmail', 'character varying(150)', "''")
    ),
    (
        '''            migrationBuilder.AddColumn<string>(
                name: "Name",
                table: "admin_users",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);''',
        get_sql('admin_users', 'Name', 'character varying(200)', None)
    ),
    (
        '''            migrationBuilder.AddColumn<Guid>(
                name: "PermissionGroupId",
                table: "admin_users",
                type: "uuid",
                nullable: true);''',
        get_sql('admin_users', 'PermissionGroupId', 'uuid', None)
    )
]

for old, new in replacements:
    text = text.replace(old, new)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Done")
