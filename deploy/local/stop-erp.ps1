param(
    [switch]$IncludeDb
)

$ErrorActionPreference = 'SilentlyContinue'
$LocalRoot = $PSScriptRoot
$RunDir    = Join-Path $LocalRoot 'run'

function Stop-PidFile {
    param([string]$Name)
    $pidFile = Join-Path $RunDir ($Name + '.pid')
    if (-not (Test-Path -LiteralPath $pidFile)) { Write-Host ("[skip] {0}: 无 pid 文件" -f $Name); return }
    $procId = [int]((Get-Content -LiteralPath $pidFile -Raw).Trim())
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $proc) { Write-Host ("[skip] {0}: 进程 {1} 已不存在" -f $Name, $procId); Remove-Item -LiteralPath $pidFile -Force; return }
    Stop-Process -Id $procId -Force
    Remove-Item -LiteralPath $pidFile -Force
    Write-Host ("[stop] {0}: 已停止进程 {1}" -f $Name, $procId)
}

Stop-PidFile 'cpolar'
Stop-PidFile 'caddy'
Stop-PidFile 'backend'
Stop-PidFile 'redis'
if ($IncludeDb) { Stop-PidFile 'mysql' }

Write-Host ''
Write-Host '剩余端口占用:'
foreach ($p in 3307, 6379, 9998, 9999) {
    $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { Write-Host ("  :{0} 仍被 PID {1} 占用" -f $p, $c.OwningProcess) }
}
Write-Host '完成。数据保存在 deploy/local/data 与 E:\jshERP-dev\mysql-data，不会被删除。'
