. "$PSScriptRoot\common.ps1"

# Only stop processes that this local stack started (tracked by deploy/local/run/*.pid).
# Existing system services on 3307/6379 are left untouched.
foreach ($name in @('ngrok', 'caddy', 'backend', 'redis', 'mysql')) {
    $pidFile = Join-Path $script:RunRoot "$name.pid"
    if (Test-Path -LiteralPath $pidFile) {
        $processId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "[stop] $name pid $processId"
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Local stack stopped. Data in deploy/local/data is preserved; existing MySQL/Redis services are untouched.'
