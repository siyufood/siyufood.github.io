param(
    [string]$ApiBase,
    [switch]$FromNgrok,
    [switch]$Push
)

. "$PSScriptRoot\common.ps1"

if ($FromNgrok) {
    try {
        $tunnels = Invoke-RestMethod -Uri 'http://127.0.0.1:4041/api/tunnels' -TimeoutSec 15
        $ApiBase = ($tunnels.tunnels | Where-Object { $_.proto -eq 'https' -and $_.public_url } | Select-Object -First 1).public_url
    } catch {
        throw 'Could not read ngrok on http://127.0.0.1:4041. Is ngrok running?'
    }
}

if (-not $ApiBase) { throw 'Pass -ApiBase https://xxxx.ngrok.app/jshERP-boot or -FromNgrok.' }

$ApiBase = $ApiBase.Trim().TrimEnd('/')
if ($ApiBase -notmatch '/jshERP-boot$') {
    $ApiBase = $ApiBase + '/jshERP-boot'
}

$configPath = Join-Path $script:RepoRoot 'jshERP-web\public\config.js'
$configText = @"
/*
 * 思雨食品 ERP 运行时配置
 * 由 deploy/local/set-api-base.ps1 自动生成；GitHub Actions 会随代码重建 Pages。
 */
window.ERP_CONFIG = {
  apiBase: '$ApiBase'
};
"@
[IO.File]::WriteAllText($configPath, $configText, [Text.UTF8Encoding]::new($false))
Write-Host "[write] $configPath"
Write-Host "[api]   $ApiBase"

if ($Push) {
    $git = Get-GitExe
    $remote = & $git -C $script:RepoRoot remote get-url origin 2>$null
    if (-not $remote) {
        Write-Warning 'No git origin; skip push.'
        return
    }
    & $git -C $script:RepoRoot add jshERP-web/public/config.js | Out-Null
    $status = & $git -C $script:RepoRoot status --porcelain -- jshERP-web/public/config.js
    if ($status) {
        & $git -C $script:RepoRoot commit -m "chore: point Pages at $ApiBase" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
        Write-Host '[git] committed config.js'
        & $git -C $script:RepoRoot push origin main
        if ($LASTEXITCODE -ne 0) { throw 'git push failed. Authenticate Git Credential Manager for GitHub, then retry.' }
        Write-Host '[git] pushed; GitHub Actions will rebuild Pages.'
    } else {
        Write-Host '[git] config.js unchanged; no commit needed.'
    }
}
