# Stop all three servers
$ports = @(3001, 3002, 3003)

foreach ($port in $ports) {
    $pids = (Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue).OwningProcess | Select-Object -Unique
    if ($pids) {
        $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
        Write-Host "Stopped process on port $port" -ForegroundColor Yellow
    } else {
        Write-Host "Nothing running on port $port" -ForegroundColor DarkGray
    }
}

Write-Host "`nAll servers stopped." -ForegroundColor Cyan
