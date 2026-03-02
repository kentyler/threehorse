# Start all three servers
$env:PGPASSWORD = "7297"
$desktop = Split-Path $PSScriptRoot

$servers = @(
    @{ Name = "AccessClone";   Port = 3001; Dir = "$desktop\AccessClone\server" },
    @{ Name = "corpus";        Port = 3002; Dir = "$desktop\corpus\server" },
    @{ Name = "claude-corpus"; Port = 3003; Dir = "$desktop\claude-corpus\server" }
)

foreach ($s in $servers) {
    # Kill anything already on the port
    $pids = (Get-NetTCPConnection -LocalPort $s.Port -ErrorAction SilentlyContinue).OwningProcess | Select-Object -Unique
    if ($pids) { $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } }

    Start-Process -NoNewWindow -FilePath "node" -ArgumentList "index.js" -WorkingDirectory $s.Dir
    Write-Host "$($s.Name) started on http://localhost:$($s.Port)" -ForegroundColor Green
}

Write-Host "`nAll servers running. Use stop-all.ps1 to shut down." -ForegroundColor Cyan
