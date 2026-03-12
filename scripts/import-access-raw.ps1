param(
    [string]$DatabaseId = "northwind_1",
    [string]$DatabaseName = "Northwind 1",
    [string]$SchemaName = "db_northwind_1",
    [string]$AccessDatabasePath = "C:\Users\Ken\Desktop\cloneexamples\northwinddev.accdb",
    [string]$ThreehorseDatabase = "threehorse",
    [string]$PgUser = "postgres",
    [string]$PgPassword = "7297",
    [string]$PgHost = "localhost",
    [string]$PsqlPath = "",
    [string]$LegacyAccessScriptsDir = "",
    [ValidateSet('all','discovery','tables','queries','forms','reports','modules','macros')]
    [string]$Phase = 'all'
)

$ErrorActionPreference = "Stop"

function Should-RunPhase {
    param([string]$Name)

    return $Phase -eq 'all' -or $Phase -eq $Name
}

function Resolve-PsqlPath {
    param([string]$PreferredPath)

    if ($PreferredPath -and (Test-Path $PreferredPath)) {
        return $PreferredPath
    }

    $candidates = @(
        "C:\Program Files\PostgreSQL\18\bin\psql.exe",
        "C:\Program Files\PostgreSQL\17\bin\psql.exe",
        "C:\Program Files\PostgreSQL\16\bin\psql.exe",
        "C:\Program Files\PostgreSQL\15\bin\psql.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "psql.exe not found. Pass -PsqlPath explicitly."
}

function Resolve-LegacyScriptsDir {
    param([string]$PreferredPath)

    if ($PreferredPath -and (Test-Path $PreferredPath)) {
        return $PreferredPath
    }

    $repoRoot = Split-Path $PSScriptRoot
    $default = Join-Path $repoRoot "..\AccessClone\scripts\access"
    $resolved = [System.IO.Path]::GetFullPath($default)

    if (Test-Path $resolved) {
        return $resolved
    }

    throw "Legacy Access scripts directory not found. Pass -LegacyAccessScriptsDir explicitly."
}

function Invoke-PsqlScalar {
    param([string]$Sql)

    $result = & $script:psql -X -q -h $PgHost -U $PgUser -d $ThreehorseDatabase -tA -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql scalar query failed"
    }

    $text = ($result | Out-String).Trim()
    $lines = $text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $uuidLine = $lines | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | Select-Object -First 1
    if ($uuidLine) {
        return $uuidLine
    }

    return ($lines | Select-Object -First 1)
}

function Invoke-PsqlFile {
    param([string]$SqlText)

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + ".sql")
    try {
        $SqlText | Set-Content -Path $tempFile -Encoding UTF8
        & $script:psql -h $PgHost -U $PgUser -d $ThreehorseDatabase -f $tempFile | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "psql file execution failed"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Normalize-JsonArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [System.Collections.IDictionary])) {
        return @($Value)
    }
    return @($Value)
}

function Parse-JsonOutput {
    param([string]$Text)

    if (-not $Text) {
        return $null
    }

    $clean = $Text.Trim()
    $clean = $clean.TrimStart([char]0xFEFF)

    $starts = @(
        $clean.IndexOf('{'),
        $clean.IndexOf('['),
        $clean.IndexOf('"')
    ) | Where-Object { $_ -ge 0 }

    if (-not $starts -or $starts.Count -eq 0) {
        throw "No JSON found in output"
    }

    $start = ($starts | Measure-Object -Minimum).Minimum
    return ($clean.Substring($start) | ConvertFrom-Json)
}

function Invoke-LegacyScriptJson {
    param(
        [string]$ScriptName,
        [string[]]$ArgumentList
    )

    $scriptPath = Join-Path $script:legacyScriptsDir $ScriptName
    if (-not (Test-Path $scriptPath)) {
        throw "Legacy script not found: $scriptPath"
    }

    $output = & powershell -ExecutionPolicy Bypass -File $scriptPath @ArgumentList 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Legacy script failed: $ScriptName`n$output"
    }

    return Parse-JsonOutput $output
}

function ConvertTo-JsonBase64 {
    param($Value)

    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
}

function New-ObjectInsertSql {
    param(
        [string]$Kind,
        [string]$Name,
        $Payload,
        $SourceRef,
        $Metadata,
        [string]$Description,
        [string]$DiscoveryId
    )

    $payload64 = ConvertTo-JsonBase64 $Payload
    $sourceRef64 = ConvertTo-JsonBase64 $SourceRef
    $metadata64 = ConvertTo-JsonBase64 $Metadata
    $escapedName = $Name.Replace("'", "''")
    $escapedDescription = $Description.Replace("'", "''")

    return @"
BEGIN;
UPDATE shared.objects
SET status = 'superseded'
WHERE database_id = '$DatabaseId'
  AND kind = '$Kind'
  AND name = '$escapedName'
  AND stage = 'raw'
  AND status = 'current';

INSERT INTO shared.objects (
    database_id,
    discovery_id,
    kind,
    name,
    origin,
    stage,
    status,
    description,
    source_ref,
    payload,
    metadata,
    created_by
)
VALUES (
    '$DatabaseId',
    '$DiscoveryId'::uuid,
    '$Kind',
    '$escapedName',
    'imported',
    'raw',
    'current',
    '$escapedDescription',
    convert_from(decode('$sourceRef64', 'base64'), 'UTF8')::jsonb,
    convert_from(decode('$payload64', 'base64'), 'UTF8')::jsonb,
    convert_from(decode('$metadata64', 'base64'), 'UTF8')::jsonb,
    'import-access-raw'
);
COMMIT;
"@
}

if (-not (Test-Path $AccessDatabasePath)) {
    throw "Access database not found at $AccessDatabasePath"
}

$script:psql = Resolve-PsqlPath -PreferredPath $PsqlPath
$script:legacyScriptsDir = Resolve-LegacyScriptsDir -PreferredPath $LegacyAccessScriptsDir
$env:PGPASSWORD = $PgPassword

Write-Host "Registering database container $DatabaseId..." -ForegroundColor Cyan
Invoke-PsqlFile @"
INSERT INTO shared.databases (
    database_id,
    name,
    schema_name,
    source_kind,
    description,
    metadata
)
VALUES (
    '$DatabaseId',
    '$($DatabaseName.Replace("'", "''"))',
    '$SchemaName',
    'imported',
    'Raw imported Access application container for $($DatabaseName.Replace("'", "''"))',
    jsonb_build_object('source_path', '$($AccessDatabasePath.Replace("'", "''"))', 'first_pass', true)
)
ON CONFLICT (database_id) DO UPDATE SET
    name = EXCLUDED.name,
    schema_name = EXCLUDED.schema_name,
    source_kind = EXCLUDED.source_kind,
    description = EXCLUDED.description,
    metadata = EXCLUDED.metadata;
"@

Write-Host "Scanning Access source inventory..." -ForegroundColor Cyan
$tables = Normalize-JsonArray (Invoke-LegacyScriptJson -ScriptName 'list_tables.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath))
$queries = Normalize-JsonArray (Invoke-LegacyScriptJson -ScriptName 'list_queries.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath))
$forms = Normalize-JsonArray (Invoke-LegacyScriptJson -ScriptName 'list_forms.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath))
$reports = Normalize-JsonArray (Invoke-LegacyScriptJson -ScriptName 'list_reports.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath))
$modules = Normalize-JsonArray (Invoke-LegacyScriptJson -ScriptName 'list_modules.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath))
$macros = Normalize-JsonArray (Invoke-LegacyScriptJson -ScriptName 'list_macros.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath))
$relationships = Normalize-JsonArray (Invoke-LegacyScriptJson -ScriptName 'list_relationships.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath))

$discovery = [ordered]@{
    source_path = $AccessDatabasePath
    tables = $tables
    queries = $queries
    forms = $forms
    reports = $reports
    modules = $modules
    macros = $macros
    relationships = $relationships
}

$discovery64 = ConvertTo-JsonBase64 $discovery
$sourcePathSql = $AccessDatabasePath.Replace("'", "''")
$discoveryId = Invoke-PsqlScalar @"
INSERT INTO shared.source_discovery (
    database_id,
    source_path,
    discovery,
    created_by
)
VALUES (
    '$DatabaseId',
    '$sourcePathSql',
    convert_from(decode('$discovery64', 'base64'), 'UTF8')::jsonb,
    'import-access-raw'
)
RETURNING discovery_id;
"@

if (-not $discoveryId) {
    throw "Failed to create source_discovery row"
}

Write-Host "Created source_discovery row $discoveryId" -ForegroundColor Green

if (Should-RunPhase 'discovery') {
    Write-Host "Discovery-only phase complete for $DatabaseId" -ForegroundColor Green
    return
}

$formNames = $forms | ForEach-Object {
    if ($_ -is [string]) { $_ } else { $_.name }
} | Where-Object { $_ }
$reportNames = $reports | ForEach-Object {
    if ($_ -is [string]) { $_ } else { $_.name }
} | Where-Object { $_ }
$moduleNames = $modules | ForEach-Object { $_.name } | Where-Object { $_ }
$macroNames = $macros | ForEach-Object { $_.name } | Where-Object { $_ }

$counts = [ordered]@{
    table = 0
    query = 0
    form = 0
    report = 0
    module = 0
    macro = 0
}

if (Should-RunPhase 'tables') {
    foreach ($tableInfo in $tables) {
        $name = $tableInfo.name
        Write-Host "Importing raw table definition: $name" -ForegroundColor DarkCyan
        $tableExport = Invoke-LegacyScriptJson -ScriptName 'export_table.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath, '-TableName', $name)
        $tablePayload = [ordered]@{
            tableName = $tableExport.tableName
            fields = $tableExport.fields
            indexes = $tableExport.indexes
            skippedColumns = $tableExport.skippedColumns
            rowCount = $tableExport.rowCount
            fieldCount = $tableExport.fieldCount
        }
        $sourceRef = [ordered]@{
            source_path = $AccessDatabasePath
            source_name = $name
            exporter = 'export_table.ps1'
            discovery_id = $discoveryId
        }
        $metadata = [ordered]@{
            first_pass = $true
            rows_imported = $false
            runtime_materialized = $false
            discovery = $tableInfo
        }
        Invoke-PsqlFile (New-ObjectInsertSql -Kind 'table' -Name $name -Payload $tablePayload -SourceRef $sourceRef -Metadata $metadata -Description "Raw Access table definition imported from source." -DiscoveryId $discoveryId)
        $counts.table++
    }
}

if (Should-RunPhase 'queries') {
    foreach ($queryInfo in $queries) {
        $name = $queryInfo.name
        Write-Host "Importing raw query definition: $name" -ForegroundColor DarkCyan
        $queryPayload = Invoke-LegacyScriptJson -ScriptName 'export_query.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath, '-QueryName', $name)
        $sourceRef = [ordered]@{
            source_path = $AccessDatabasePath
            source_name = $name
            exporter = 'export_query.ps1'
            discovery_id = $discoveryId
        }
        $metadata = [ordered]@{
            first_pass = $true
            runtime_materialized = $false
            discovery = $queryInfo
        }
        Invoke-PsqlFile (New-ObjectInsertSql -Kind 'query' -Name $name -Payload $queryPayload -SourceRef $sourceRef -Metadata $metadata -Description "Raw Access query definition imported from source." -DiscoveryId $discoveryId)
        $counts.query++
    }
}

if (Should-RunPhase 'forms') {
    Write-Host "Exporting forms in batch..." -ForegroundColor Cyan
    $formBatch = Invoke-LegacyScriptJson -ScriptName 'export_forms_batch.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath, '-FormNames', ($formNames -join ','))
    foreach ($prop in $formBatch.objects.PSObject.Properties) {
        $name = $prop.Name
        Write-Host "Importing raw form definition: $name" -ForegroundColor DarkCyan
        $sourceRef = [ordered]@{
            source_path = $AccessDatabasePath
            source_name = $name
            exporter = 'export_forms_batch.ps1'
            discovery_id = $discoveryId
        }
        $metadata = [ordered]@{
            first_pass = $true
            runtime_materialized = $false
        }
        Invoke-PsqlFile (New-ObjectInsertSql -Kind 'form' -Name $name -Payload $prop.Value -SourceRef $sourceRef -Metadata $metadata -Description "Raw Access form definition imported from source." -DiscoveryId $discoveryId)
        $counts.form++
    }
}

if (Should-RunPhase 'reports') {
    Write-Host "Exporting reports in batch..." -ForegroundColor Cyan
    $reportBatch = Invoke-LegacyScriptJson -ScriptName 'export_reports_batch.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath, '-ReportNames', ($reportNames -join ','))
    foreach ($prop in $reportBatch.objects.PSObject.Properties) {
        $name = $prop.Name
        Write-Host "Importing raw report definition: $name" -ForegroundColor DarkCyan
        $sourceRef = [ordered]@{
            source_path = $AccessDatabasePath
            source_name = $name
            exporter = 'export_reports_batch.ps1'
            discovery_id = $discoveryId
        }
        $metadata = [ordered]@{
            first_pass = $true
            runtime_materialized = $false
        }
        Invoke-PsqlFile (New-ObjectInsertSql -Kind 'report' -Name $name -Payload $prop.Value -SourceRef $sourceRef -Metadata $metadata -Description "Raw Access report definition imported from source." -DiscoveryId $discoveryId)
        $counts.report++
    }
}

if (Should-RunPhase 'modules') {
    Write-Host "Exporting modules in batch..." -ForegroundColor Cyan
    $moduleBatch = Invoke-LegacyScriptJson -ScriptName 'export_modules_batch.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath, '-ModuleNames', ($moduleNames -join ','))
    foreach ($prop in $moduleBatch.objects.PSObject.Properties) {
        $name = $prop.Name
        Write-Host "Importing raw module definition: $name" -ForegroundColor DarkCyan
        $sourceRef = [ordered]@{
            source_path = $AccessDatabasePath
            source_name = $name
            exporter = 'export_modules_batch.ps1'
            discovery_id = $discoveryId
        }
        $metadata = [ordered]@{
            first_pass = $true
            runtime_materialized = $false
        }
        Invoke-PsqlFile (New-ObjectInsertSql -Kind 'module' -Name $name -Payload $prop.Value -SourceRef $sourceRef -Metadata $metadata -Description "Raw Access VBA module definition imported from source." -DiscoveryId $discoveryId)
        $counts.module++
    }
}

if (Should-RunPhase 'macros') {
    Write-Host "Exporting macros individually..." -ForegroundColor Cyan
    foreach ($macroInfo in $macros) {
        $name = $macroInfo.name
        Write-Host "Importing raw macro definition: $name" -ForegroundColor DarkCyan
        $macroPayload = Invoke-LegacyScriptJson -ScriptName 'export_macro.ps1' -ArgumentList @('-DatabasePath', $AccessDatabasePath, '-MacroName', $name)
        $sourceRef = [ordered]@{
            source_path = $AccessDatabasePath
            source_name = $name
            exporter = 'export_macro.ps1'
            discovery_id = $discoveryId
        }
        $metadata = [ordered]@{
            first_pass = $true
            runtime_materialized = $false
            discovery = $macroInfo
        }
        Invoke-PsqlFile (New-ObjectInsertSql -Kind 'macro' -Name $name -Payload $macroPayload -SourceRef $sourceRef -Metadata $metadata -Description "Raw Access macro definition imported from source." -DiscoveryId $discoveryId)
        $counts.macro++
    }
}

Write-Host "Raw import complete for $DatabaseId (phase: $Phase)" -ForegroundColor Green
$counts | ConvertTo-Json -Compress | Write-Host

