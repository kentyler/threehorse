param(
    [string]$DatabaseName = "threehorse",
    [string]$User = "postgres",
    [string]$Password = "7297",
    [string]$PgHost = "localhost",
    [string]$AdminDatabase = "postgres",
    [string]$PsqlPath = ""
)

$ErrorActionPreference = "Stop"

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

$psql = Resolve-PsqlPath -PreferredPath $PsqlPath
$root = $PSScriptRoot
$sqlDir = Join-Path $root "sql"

if (-not (Test-Path $sqlDir)) {
    throw "SQL directory not found at $sqlDir"
}

$env:PGPASSWORD = $Password

$dbExists = & $psql -h $PgHost -U $User -d $AdminDatabase -tAc "select 1 from pg_database where datname = '$DatabaseName'"

if (-not $dbExists) {
    Write-Host "Creating database $DatabaseName..." -ForegroundColor Cyan
    & $psql -h $PgHost -U $User -d $AdminDatabase -c "create database $DatabaseName"
} else {
    Write-Host "Database $DatabaseName already exists." -ForegroundColor DarkGray
}

$sqlFiles = Get-ChildItem $sqlDir -Filter *.sql | Sort-Object Name

if (-not $sqlFiles) {
    throw "No SQL files found in $sqlDir"
}

foreach ($sqlFile in $sqlFiles) {
    Write-Host "Applying schema from $($sqlFile.FullName)..." -ForegroundColor Cyan
    & $psql -h $PgHost -U $User -d $DatabaseName -f $sqlFile.FullName
}

Write-Host "Install complete." -ForegroundColor Green
