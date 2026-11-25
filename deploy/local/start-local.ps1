$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

$envMap = Read-DotEnv
$dbHost = Get-EnvValue $envMap 'DB_HOST' '127.0.0.1'
$dbPort = [int](Get-EnvValue $envMap 'DB_PORT' '3307')
$dbUser = Get-EnvValue $envMap 'DB_USER' 'root'
$dbPassword = Get-EnvValue $envMap 'DB_PASSWORD'
$redisHost = Get-EnvValue $envMap 'REDIS_HOST' '127.0.0.1'
$redisPort = [int](Get-EnvValue $envMap 'REDIS_PORT' '6379')
$redisPassword = Get-EnvValue $envMap 'REDIS_PASSWORD'
$ngrokToken = Get-EnvValue $envMap 'NGROK_AUTHTOKEN'
$ngrokDomain = Get-EnvValue $envMap 'NGROK_DOMAIN'

# 运行时目录必须使用纯 ASCII 路径：Java 8 的 properties 读取中文路径会乱码，
# 导致 PF4J 找不到插件根目录、插件接口整体 404。
$runtimeRoot = Get-EnvValue $envMap 'RUNTIME_ROOT'
if (-not $runtimeRoot) {
    $runtimeRoot = if (Test-Path -LiteralPath 'E:\') { 'E:\siyu-erp-runtime' } else { Join-Path $env:SystemDrive 'siyu-erp-runtime' }
}
$runtimeRoot = $runtimeRoot.TrimEnd('\', '/')
$pluginRuntime = Join-Path $runtimeRoot 'plugins'
$pluginConfigDir = Join-Path $runtimeRoot 'pluginConfig'
$runtimeUpload = Join-Path $runtimeRoot 'upload'
$runtimeTmp = Join-Path $runtimeRoot 'tmp'
$runtimeLogs = Join-Path $runtimeRoot 'logs'

if (-not $dbPassword -or -not $redisPassword) {
    throw 'DB_PASSWORD / REDIS_PASSWORD missing in deploy/local/.env'
}

$mysql = Find-Tool 'mariadb' 'mysql.exe'
$mysqld = Find-Tool 'mariadb' 'mysqld.exe'
$redisServer = Find-Tool 'redis' 'redis-server.exe'
$java = Find-Tool 'jre' 'java.exe'
$caddy = Find-Tool 'caddy' 'caddy.exe'
$ngrok = Find-Tool 'ngrok' 'ngrok.exe'

$runtime = Join-Path $script:LocalRoot 'runtime'
$redisData = Join-Path $script:DataRoot 'redis'
$redisConf = Join-Path $runtime 'redis.conf'
$backendConfig = Join-Path $script:LocalRoot 'config\application-local.properties'
$myIni = Join-Path $runtime 'my.ini'
$caddyfile = Join-Path $script:RepoRoot 'deploy\caddy\Caddyfile'
$backendLog = Join-Path $script:LogRoot 'backend.log'
$caddyLog = Join-Path $script:LogRoot 'caddy.log'
$ngrokLog = Join-Path $script:LogRoot 'ngrok.log'
New-Item -ItemType Directory -Path $runtime, $redisData, $script:RunRoot, $script:LogRoot, (Join-Path $runtime 'upload'), (Join-Path $runtime 'tmp'), (Join-Path $runtime 'pluginConfig'), $runtimeRoot, $pluginRuntime, $pluginConfigDir, $runtimeUpload, $runtimeTmp, $runtimeLogs, (Split-Path -Parent $backendConfig) -Force | Out-Null

$pluginSource = Join-Path $script:RepoRoot 'deploy\backend\plugins'
if (Test-Path -LiteralPath $pluginSource) {
    Get-ChildItem -LiteralPath $pluginSource -File -Filter '*.jar' | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $pluginRuntime -Force
    }
    Write-Host ("[plugin] copied JARs to " + $pluginRuntime)
}

if ((-not (Test-Path -LiteralPath (Join-Path $script:DataRoot 'mysql\mysql'))) -or (-not (Test-Path -LiteralPath $myIni))) {
    Write-Host '[init] Database is not initialized; running init-db.ps1'
    & (Join-Path $PSScriptRoot 'init-db.ps1')
}

if (-not (Test-Port $dbPort)) {
    $proc = Start-Process -FilePath $mysqld -ArgumentList @("--defaults-file=$myIni", '--console') -WorkingDirectory (Split-Path -Parent $mysqld) -RedirectStandardOutput (Join-Path $script:LogRoot 'mysql-stdout.log') -RedirectStandardError (Join-Path $script:LogRoot 'mysql-stderr.log') -WindowStyle Hidden -PassThru
    $proc.Id | Set-Content -LiteralPath (Join-Path $script:RunRoot 'mysql.pid') -Encoding ascii
    if (-not (Wait-Port $dbPort 60 'MariaDB')) { throw 'MariaDB failed to start. Check deploy/local/logs/mysql.log.' }
    Write-Host "[start] MariaDB :$dbPort"
} else {
    Write-Host "[skip] MySQL/MariaDB already listening on $dbPort (existing service, data preserved)"
}

if (-not (Test-Port $redisPort)) {
    $redisText = @"
bind $redisHost
port $redisPort
requirepass $redisPassword
dir $($redisData.Replace('\', '/'))
appendonly yes
appendfsync everysec
"@
    [IO.File]::WriteAllText($redisConf, $redisText, [Text.UTF8Encoding]::new($false))
    $proc = Start-Process -FilePath $redisServer -ArgumentList @($redisConf) -WorkingDirectory (Split-Path -Parent $redisServer) -RedirectStandardOutput (Join-Path $script:LogRoot 'redis-stdout.log') -RedirectStandardError (Join-Path $script:LogRoot 'redis-stderr.log') -WindowStyle Hidden -PassThru
    $proc.Id | Set-Content -LiteralPath (Join-Path $script:RunRoot 'redis.pid') -Encoding ascii
    if (-not (Wait-Port $redisPort 20 'Redis')) { throw 'Redis failed to start. Check deploy/local/logs/redis.log.' }
    Write-Host "[start] Redis :$redisPort"
} else {
    Write-Host "[skip] Redis already listening on $redisPort (existing service, data preserved)"
}

if (-not (Test-Port 9998)) {
    $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'application.properties.template') -Raw
    $runtimeForProps = $runtimeRoot.Replace('\', '/')
    $configText = $template.Replace('__RUNTIME_ROOT__', $runtimeForProps).Replace('__DB_HOST__', $dbHost).Replace('__DB_PORT__', "$dbPort").Replace('__DB_USER__', $dbUser).Replace('__DB_PASSWORD__', $dbPassword).Replace('__REDIS_HOST__', $redisHost).Replace('__REDIS_PORT__', "$redisPort").Replace('__REDIS_PASSWORD__', $redisPassword)
    [IO.File]::WriteAllText($backendConfig, $configText, [Text.UTF8Encoding]::new($false))
    $jar = Join-Path $script:RepoRoot 'deploy\backend\jshERP.jar'
    $proc = Start-Process -FilePath $java -ArgumentList @('-Xms256m', '-Xmx1024m', '-Dfile.encoding=UTF-8', '-jar', $jar, "--spring.config.location=file:$backendConfig") -WorkingDirectory $script:RepoRoot -RedirectStandardOutput (Join-Path $script:LogRoot 'backend-stdout.log') -RedirectStandardError $backendLog -WindowStyle Hidden -PassThru
    $proc.Id | Set-Content -LiteralPath (Join-Path $script:RunRoot 'backend.pid') -Encoding ascii
    Write-Host '[start] Spring Boot backend :9998 (waiting up to 90s)'
    if (-not (Wait-Port 9998 90 'backend')) {
        Get-Content -LiteralPath $backendLog -Tail 80 -ErrorAction SilentlyContinue
        throw 'Backend failed to start. Check deploy/local/logs/backend.log.'
    }
} else {
    Write-Host '[skip] Backend already listening on 9998'
}

if (Test-Port 9999) {
    $caddyPidFile = Join-Path $script:RunRoot 'caddy.pid'
    $caddyRunning = $false
    if (Test-Path -LiteralPath $caddyPidFile) {
        $caddyPid = [int](Get-Content -LiteralPath $caddyPidFile -Raw).Trim()
        $caddyRunning = [bool](Get-Process -Id $caddyPid -ErrorAction SilentlyContinue)
    }
    if ($caddyRunning) {
        Write-Host '[skip] Caddy API gateway already listening on 9999'
    } else {
        throw 'Port 9999 is occupied by another process. Stop the old ERP backend first, then rerun this script.'
    }
} else {
    $env:BACKEND_ADDR = '127.0.0.1:9998'
    $proc = Start-Process -FilePath $caddy -ArgumentList @('run', '--config', $caddyfile) -WorkingDirectory $script:RepoRoot -RedirectStandardOutput (Join-Path $script:LogRoot 'caddy-stdout.log') -RedirectStandardError $caddyLog -WindowStyle Hidden -PassThru
    $proc.Id | Set-Content -LiteralPath (Join-Path $script:RunRoot 'caddy.pid') -Encoding ascii
    if (-not (Wait-Port 9999 20 'Caddy')) {
        Get-Content -LiteralPath $caddyLog -Tail 40 -ErrorAction SilentlyContinue
        throw 'Caddy failed to start. Check deploy/local/logs/caddy.log.'
    }
    Write-Host '[start] Caddy API gateway :9999'
}

$localApi = 'http://127.0.0.1:9999/jshERP-boot/platformConfig/getPlatform/name'
try {
    $name = (Invoke-WebRequest -Uri $localApi -TimeoutSec 30 -UseBasicParsing).Content
    Write-Host ('[ok] local API name: ' + $name)
} catch {
    Write-Warning ('Local API check failed: ' + $_.Exception.Message)
}

$ngrokWebAddr = '127.0.0.1:4041'
$publicUrl = $null
if ($ngrokToken) {
    if (-not (Test-Port 4041)) {
        $ngrokArgs = @('http', '9999', "--authtoken=$ngrokToken", '--log=stdout')
        if ($ngrokDomain) { $ngrokArgs += "--domain=$ngrokDomain" }
        $proc = Start-Process -FilePath $ngrok -ArgumentList $ngrokArgs -WorkingDirectory $script:RepoRoot -RedirectStandardOutput (Join-Path $script:LogRoot 'ngrok-stdout.log') -RedirectStandardError $ngrokLog -WindowStyle Hidden -PassThru
        $proc.Id | Set-Content -LiteralPath (Join-Path $script:RunRoot 'ngrok.pid') -Encoding ascii
        Write-Host '[start] ngrok :9999'
        if (-not (Wait-Port 4041 30 'ngrok')) { throw 'ngrok failed to start. Check deploy/local/logs/ngrok.log.' }
    }
    try {
        $tunnels = Invoke-RestMethod -Uri "http://$ngrokWebAddr/api/tunnels" -TimeoutSec 15
        $publicUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq 'https' -and $_.public_url } | Select-Object -First 1).public_url
    } catch {
        if ($ngrokDomain) { $publicUrl = "https://$ngrokDomain" }
    }
    if (-not $publicUrl) {
        $ngrokLogText = Get-Content -LiteralPath (Join-Path $script:LogRoot 'ngrok-stdout.log') -Raw -ErrorAction SilentlyContinue
        $m = [regex]::Match($ngrokLogText, 'https://[a-zA-Z0-9\.\-]+')
        if ($m.Success) { $publicUrl = $m.Value }
    }
} else {
    Write-Warning 'NGROK_AUTHTOKEN is empty; local API is running but not exposed publicly.'
}

if ($publicUrl) {
    $apiBase = $publicUrl.TrimEnd('/') + '/jshERP-boot'
    Write-Host ''
    Write-Host ('Public API: ' + $apiBase)
    try {
        & (Join-Path $PSScriptRoot 'set-api-base.ps1') -ApiBase $apiBase -Push
    } catch {
        Write-Warning ('Could not update Pages config: ' + $_.Exception.Message)
        Write-Host 'Run .\deploy\local\set-api-base.ps1 -FromNgrok -Push after GitHub authentication is available.'
    }
} else {
    Write-Host ''
    Write-Host 'Local API: http://127.0.0.1:9999/jshERP-boot'
    Write-Host 'Set NGROK_AUTHTOKEN in deploy/local/.env, then run: .\deploy\local\start-local.ps1'
}

Write-Host ''
Write-Host 'Pages frontend: https://siyufood.github.io'
Write-Host 'Local backend:  http://127.0.0.1:9998/jshERP-boot'
Write-Host 'Local gateway:  http://127.0.0.1:9999/jshERP-boot'
