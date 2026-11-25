param(
    [switch]$NoTunnel,
    [switch]$NoPublish,
    [switch]$Status
)

# 思雨食品 ERP 一键启动：MariaDB -> Redis -> Spring Boot -> Caddy -> cpolar -> 发布 Pages 指向
# 设计原则：幂等（已运行的服务跳过）、自检（每一步都验证端口/接口）、失败即报错并给出日志位置。

$ErrorActionPreference = 'Stop'

$RepoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LocalRoot = $PSScriptRoot
$RunDir    = Join-Path $LocalRoot 'run'
$LogDir    = Join-Path $LocalRoot 'logs'
New-Item -ItemType Directory -Path $RunDir, $LogDir -Force | Out-Null
$StartLog  = Join-Path $LogDir ('startup-' + (Get-Date -Format 'yyyyMMdd') + '.log')

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = ('[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
    Add-Content -LiteralPath $StartLog -Value $line -Encoding UTF8
}

$EnvFile = Join-Path $LocalRoot '.env'
function Read-DotEnv {
    $map = @{}
    if (Test-Path -LiteralPath $EnvFile) {
        Get-Content -LiteralPath $EnvFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line -match '^([^=]+)=(.*)$') {
                $map[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
            }
        }
    }
    return $map
}
function Get-Setting {
    param($Map, [string]$Key, [string]$Default = '')
    if ($Map.ContainsKey($Key) -and $Map[$Key]) { return $Map[$Key] }
    return $Default
}

function Test-Port {
    param([int]$Port, [string]$HostName = '127.0.0.1')
    $client = New-Object Net.Sockets.TcpClient
    try { $client.Connect($HostName, $Port); return $true }
    catch { return $false }
    finally { $client.Close() }
}

function Wait-Port {
    param([int]$Port, [int]$TimeoutSeconds, [string]$Name)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (Test-Port -Port $Port) { return $true }
        Start-Sleep -Milliseconds 500
    }
    Write-Log ('{0} 在 {1}s 内未监听 {2}' -f $Name, $TimeoutSeconds, $Port) 'ERROR'
    return $false
}

function Resolve-Exe {
    param([string]$Preferred, [string[]]$Fallbacks, [string[]]$GlobRoots)
    if ($Preferred -and (Test-Path -LiteralPath $Preferred)) { return (Resolve-Path -LiteralPath $Preferred).Path }
    foreach ($f in $Fallbacks) { if ($f -and (Test-Path -LiteralPath $f)) { return (Resolve-Path -LiteralPath $f).Path } }
    foreach ($root in $GlobRoots) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            $hit = Get-ChildItem -LiteralPath $root -Recurse -File -Filter ([IO.Path]::GetFileName($Preferred)) -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

$envMap       = Read-DotEnv
$dbHost       = Get-Setting $envMap 'DB_HOST' '127.0.0.1'
$dbPort       = [int](Get-Setting $envMap 'DB_PORT' '3307')
$dbUser       = Get-Setting $envMap 'DB_USER' 'root'
$dbPassword   = Get-Setting $envMap 'DB_PASSWORD'
$redisHost    = Get-Setting $envMap 'REDIS_HOST' '127.0.0.1'
$redisPort    = [int](Get-Setting $envMap 'REDIS_PORT' '6379')
$redisPassword = Get-Setting $envMap 'REDIS_PASSWORD'
$backendPort  = [int](Get-Setting $envMap 'BACKEND_PORT' '9998')
$gatewayPort  = [int](Get-Setting $envMap 'GATEWAY_PORT' '9999')
$publicRepo   = Get-Setting $envMap 'PAGES_REPO' 'siyufood/siyufood.github.io'
$pagesUrl     = Get-Setting $envMap 'PAGES_URL' 'https://siyufood.github.io'
$ngrokToken   = Get-Setting $envMap 'NGROK_AUTHTOKEN'
$ngrokDomain  = Get-Setting $envMap 'NGROK_DOMAIN'
$tunnelMode   = (Get-Setting $envMap 'ERP_TUNNEL' 'auto').ToLowerInvariant()
$runtimeRoot  = Get-Setting $envMap 'RUNTIME_ROOT'
if (-not $runtimeRoot) {
    $runtimeRoot = if (Test-Path -LiteralPath 'E:\') { 'E:\siyu-erp-runtime' } else { Join-Path $env:SystemDrive 'siyu-erp-runtime' }
}
$runtimeRoot = $runtimeRoot.TrimEnd('\', '/')

# ---- 工具定位 ----------------------------------------------------------------
# my.ini 必须先确定：mysqld 必须与 ini 的 basedir 同版本，否则数据目录会被写坏。
$mariaIni = Get-Setting $envMap 'ERP_MYSQL_INI'
if (-not $mariaIni) {
    $mariaIni = if (Test-Path -LiteralPath 'E:\jshERP-dev\my.ini') { 'E:\jshERP-dev\my.ini' } else { Join-Path $LocalRoot 'runtime\my.ini' }
}
$iniBasedir = $null
if (Test-Path -LiteralPath $mariaIni) {
    $line = (Get-Content -LiteralPath $mariaIni | Where-Object { $_ -match '(?i)^\s*basedir\s*=' } | Select-Object -First 1)
    if ($line) { $iniBasedir = ($line -replace '(?i)^\s*basedir\s*=\s*', '').Trim().Trim('"').Replace('/', '\') }
}
$mariaExe = Get-Setting $envMap 'ERP_MYSQLD'
if ($mariaExe -and (Test-Path -LiteralPath $mariaExe)) {
    $mariaExe = (Resolve-Path -LiteralPath $mariaExe).Path
} elseif ($iniBasedir -and (Test-Path -LiteralPath (Join-Path $iniBasedir 'bin\mysqld.exe'))) {
    $mariaExe = Join-Path $iniBasedir 'bin\mysqld.exe'
} else {
    $mariaExe = Resolve-Exe -Preferred '' -Fallbacks @((Join-Path $LocalRoot '.tools\mariadb\mariadb-10.11.10-winx64\bin\mysqld.exe')) -GlobRoots @((Join-Path $LocalRoot '.tools\mariadb'))
}
$mysqlCli = if ($mariaExe) { Join-Path (Split-Path -Parent $mariaExe) 'mysql.exe' } else { $null }
$javaExe  = Resolve-Exe -Preferred (Get-Setting $envMap 'ERP_JAVA') -Fallbacks @((Join-Path $LocalRoot '.tools\jre\jdk8u512-b09-jre\bin\java.exe')) -GlobRoots @((Join-Path $LocalRoot '.tools\jre'))
if (-not $javaExe) {
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source) -and (Get-Item -LiteralPath $cmd.Source).Length -gt 0) { $javaExe = $cmd.Source }
}
if (-not $javaExe -or -not (Test-Path -LiteralPath $javaExe) -or (Get-Item -LiteralPath $javaExe).Length -eq 0) {
    Write-Log '[backend] 未找到可用的 JDK 8（Windows 商店的 java.exe 占位程序不可用），请运行 deploy/local/bootstrap.ps1' 'ERROR'
    exit 1
}
$caddyExe = Resolve-Exe -Preferred (Join-Path $LocalRoot '.tools\caddy\caddy.exe') -Fallbacks @()
$cpolarExe = Resolve-Exe -Preferred (Join-Path $LocalRoot '.tools\cpolar\cpolar.exe') -Fallbacks @()
$ngrokExe  = Resolve-Exe -Preferred (Join-Path $LocalRoot '.tools\ngrok\ngrok.exe') -Fallbacks @()
$redisExe  = Resolve-Exe -Preferred (Join-Path $LocalRoot '.tools\redis\redis-server.exe') -Fallbacks @()
$redisCli  = Resolve-Exe -Preferred (Join-Path $LocalRoot '.tools\redis\redis-cli.exe') -Fallbacks @()
$backendJar = Join-Path $RepoRoot 'deploy\backend\jshERP.jar'
$backendCfg = Join-Path $LocalRoot 'config\application-local.properties'

function Get-GitExe {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = 'C:\Program Files\Git\cmd\git.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return $null
}

function Show-Status {
    Write-Host ''
    Write-Host '服务状态:'
    $rows = @(
        @{ Name = "MariaDB   :$dbPort";      Up = (Test-Port -Port $dbPort) },
        @{ Name = "Redis     :$redisPort";   Up = (Test-Port -Port $redisPort) },
        @{ Name = "Backend   :$backendPort"; Up = (Test-Port -Port $backendPort) },
        @{ Name = "Gateway   :$gatewayPort"; Up = (Test-Port -Port $gatewayPort) }
    )
    foreach ($r in $rows) {
        $mark = if ($r.Up) { '[UP]  ' } else { '[DOWN]' }
        Write-Host ("  {0} {1}" -f $mark, $r.Name)
    }
    $urlFile = Join-Path $RunDir 'public-url.txt'
    if (Test-Path -LiteralPath $urlFile) { Write-Host ("  公网后端 : " + (Get-Content -LiteralPath $urlFile -Raw).Trim()) }
    $cfg = Join-Path $RepoRoot 'jshERP-web\public\config.js'
    if (Test-Path -LiteralPath $cfg) {
        $m = [regex]::Match((Get-Content -LiteralPath $cfg -Raw), "apiBase:\s*'([^']+)'")
        if ($m.Success) { Write-Host ("  Pages 指向: " + $m.Groups[1].Value) }
    }
    Write-Host ("  Pages 入口: $pagesUrl/user/login")
    Write-Host ''
}

Write-Log '---- start-erp ----'
Write-Log ('repo: {0}' -f $RepoRoot)

if ($Status) { Show-Status; exit 0 }

# 预检
$missing = @()
foreach ($p in @($mariaExe, $mysqlCli, $javaExe, $caddyExe, $backendJar)) { if (-not $p -or -not (Test-Path -LiteralPath $p)) { $missing += $p } }
if (-not $dbPassword) { $missing += 'DB_PASSWORD(空)' }
if ($missing.Count -gt 0) {
    Write-Log ('缺少必要组件: ' + ($missing -join ', ')) 'ERROR'
    Write-Log '请先运行 deploy/local/bootstrap.ps1 准备便携工具链，或在 .env 中指定 ERP_MYSQLD / ERP_JAVA。' 'ERROR'
    exit 1
}

# ---- 1. MariaDB --------------------------------------------------------------
function Repair-MyIniEncoding {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = Get-Content -LiteralPath $Path
    $changed = $false
    $keys = 'basedir|datadir|pid-file|log-error|tmpdir|plugin-dir|socket'
    $new = @()
    foreach ($line in $lines) {
        if ($line -match "(?i)^(\s*($keys)\s*=\s*)(.+\\)$") {
            $new += ($matches[1] + ($matches[3].TrimEnd() -replace '\', '/'))
            $changed = $true
        } else { $new += $line }
    }
    if ($changed) {
        Copy-Item -LiteralPath $Path -Destination ($Path + '.bak') -Force
        [IO.File]::WriteAllText($Path, (($new -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))
        Write-Log ("[db] 已修复 my.ini 中的反斜杠路径（MySQL 会把 \s 当转义空格）: $Path") 'WARN'
    }
}

function Test-DbAuth {
    if (-not $mysqlCli) { return $false }
    $env:MYSQL_PWD = $dbPassword
    try {
        $out = & $mysqlCli '--protocol=TCP' "-h$dbHost" "--port=$dbPort" "-u$dbUser" '-N' '-e' 'SELECT 1;' 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
    finally { Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue }
}

if (Test-Port -Port $dbPort -HostName $dbHost) {
    if (Test-DbAuth) {
        Write-Log ("[db] 复用已运行的 MariaDB :$dbPort") 'OK'
    } else {
        Write-Log ("[db] :$dbPort 已被占用，但 root 认证失败。请确认 .env 的 DB_PASSWORD 与该实例一致。") 'ERROR'
        exit 1
    }
} else {
    Repair-MyIniEncoding -Path $mariaIni
    if (-not (Test-Path -LiteralPath $mariaIni)) { Write-Log ("[db] 找不到 my.ini: $mariaIni") 'ERROR'; exit 1 }
    Write-Log ("[db] 启动 MariaDB :$dbPort (ini=$mariaIni)")
    $p = Start-Process -FilePath $mariaExe -ArgumentList @("--defaults-file=$mariaIni") -WorkingDirectory (Split-Path -Parent $mariaExe) `
        -RedirectStandardOutput (Join-Path $LogDir 'mysql-stdout.log') -RedirectStandardError (Join-Path $LogDir 'mysql-stderr.log') -WindowStyle Hidden -PassThru
    $p.Id | Set-Content -LiteralPath (Join-Path $RunDir 'mysql.pid') -Encoding ascii
    if (-not (Wait-Port -Port $dbPort -TimeoutSeconds 90 -Name 'MariaDB')) {
        Get-Content -LiteralPath (Join-Path $LogDir 'mysql-stderr.log') -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        exit 1
    }
    if (-not (Test-DbAuth)) {
        Write-Log '[db] 端口已开但认证失败：DB_PASSWORD 与数据目录中的 root 密码不一致。' 'ERROR'
        Write-Log '     可用 --skip-grant-tables 重置 root 密码（见 README「数据库密码重置」）。' 'ERROR'
        exit 1
    }
    if (-not (Test-Port -Port $dbPort)) { exit 1 }
    $env:MYSQL_PWD = $dbPassword
    $tables = & $mysqlCli '--protocol=TCP' "-h$dbHost" "--port=$dbPort" "-u$dbUser" '-N' '-e' "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='jsh_erp';" 2>$null
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    Write-Log ("[db] 就绪，jsh_erp 表数: " + ($tables -join '').Trim()) 'OK'
}

# ---- 2. Redis ----------------------------------------------------------------
function Test-Redis {
    if (-not $redisCli) { return $true }
    $oldPwd = $env:REDISCLI_AUTH
    $env:REDISCLI_AUTH = $redisPassword
    try {
        & $redisCli '-h' $redisHost '-p' "$redisPort" 'ping' 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
    finally { if ($null -eq $oldPwd) { Remove-Item Env:\REDISCLI_AUTH -ErrorAction SilentlyContinue } else { $env:REDISCLI_AUTH = $oldPwd } }
}

if (Test-Port -Port $redisPort -HostName $redisHost) {
    if (Test-Redis) { Write-Log ("[redis] 复用已运行的 Redis :$redisPort") 'OK' }
    else { Write-Log ("[redis] :$redisPort 已占用但认证失败，跳过（后端若报认证错误请修正 REDIS_PASSWORD）") 'WARN' }
} elseif ($redisExe) {
    $redisData = Join-Path $LocalRoot 'data\redis'
    New-Item -ItemType Directory -Path $redisData -Force | Out-Null
    $redisConf = Join-Path $LocalRoot 'runtime\redis.conf'
    $confText = "bind $redisHost`nport $redisPort`nrequirepass $redisPassword`ndir $($redisData.Replace('\','/'))`nappendonly yes`nappendfsync everysec`n"
    [IO.File]::WriteAllText($redisConf, $confText, [Text.UTF8Encoding]::new($false))
    $p = Start-Process -FilePath $redisExe -ArgumentList @("`"$redisConf`"") -WorkingDirectory (Split-Path -Parent $redisExe) `
        -RedirectStandardOutput (Join-Path $LogDir 'redis-stdout.log') -RedirectStandardError (Join-Path $LogDir 'redis-stderr.log') -WindowStyle Hidden -PassThru
    $p.Id | Set-Content -LiteralPath (Join-Path $RunDir 'redis.pid') -Encoding ascii
    if (-not (Wait-Port -Port $redisPort -TimeoutSeconds 20 -Name 'Redis')) { exit 1 }
    Write-Log ("[redis] 启动完成 :$redisPort") 'OK'
} else {
    Write-Log '[redis] 未找到 redis-server.exe，且端口未监听；后端会因缓存不可用而健康检查失败。' 'WARN'
}

# ---- 3. Spring Boot 后端 -----------------------------------------------------
function Test-Backend {
    try {
        $r = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/jshERP-boot/platformConfig/getPlatform/name" -f $backendPort) -UseBasicParsing -TimeoutSec 15
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

if (-not (Test-Port -Port $backendPort)) {
    $template = Join-Path $LocalRoot 'application.properties.template'
    if (Test-Path -LiteralPath $template) {
        $props = (Get-Content -LiteralPath $template -Raw).
            Replace('__RUNTIME_ROOT__', $runtimeRoot.Replace('\', '/')).
            Replace('__DB_HOST__', $dbHost).
            Replace('__DB_PORT__', "$dbPort").
            Replace('__DB_USER__', $dbUser).
            Replace('__DB_PASSWORD__', $dbPassword).
            Replace('__REDIS_HOST__', $redisHost).
            Replace('__REDIS_PORT__', "$redisPort").
            Replace('__REDIS_PASSWORD__', $redisPassword)
        New-Item -ItemType Directory -Path (Split-Path -Parent $backendCfg) -Force | Out-Null
        [IO.File]::WriteAllText($backendCfg, $props, [Text.UTF8Encoding]::new($false))
    }
    $pluginSrc = Join-Path $RepoRoot 'deploy\backend\plugins'
    $pluginDst = Join-Path $runtimeRoot 'plugins'
    New-Item -ItemType Directory -Path $pluginDst, (Join-Path $runtimeRoot 'pluginConfig'), (Join-Path $runtimeRoot 'upload'), (Join-Path $runtimeRoot 'tmp'), (Join-Path $runtimeRoot 'logs') -Force | Out-Null
    if (Test-Path -LiteralPath $pluginSrc) {
        Get-ChildItem -LiteralPath $pluginSrc -Filter '*.jar' -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $pluginDst -Force
        }
    }
    Write-Log ("[backend] 启动 Spring Boot :$backendPort")
    $p = Start-Process -FilePath $javaExe -ArgumentList @('-Xms256m', '-Xmx1024m', '-Dfile.encoding=UTF-8', '-jar', $backendJar, "--spring.config.location=file:$backendCfg") `
        -WorkingDirectory $RepoRoot -RedirectStandardOutput (Join-Path $LogDir 'backend-stdout.log') -RedirectStandardError (Join-Path $LogDir 'backend.log') -WindowStyle Hidden -PassThru
    $p.Id | Set-Content -LiteralPath (Join-Path $RunDir 'backend.pid') -Encoding ascii
    if (-not (Wait-Port -Port $backendPort -TimeoutSeconds 120 -Name 'backend')) {
        Get-Content -LiteralPath (Join-Path $LogDir 'backend.log') -Tail 25 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        exit 1
    }
    Write-Log '[backend] 端口已就绪' 'OK'
} else {
    Write-Log ("[backend] 复用已运行的后端 :$backendPort") 'OK'
}
if (-not (Test-Backend)) {
    Write-Log '[backend] 健康检查失败：/jshERP-boot/platformConfig/getPlatform/name 非 200' 'ERROR'
    exit 1
}

# ---- 4. Caddy 网关 -----------------------------------------------------------
function Get-LocalBrand {
    param([int]$Port)
    try {
        return (Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/jshERP-boot/platformConfig/getPlatform/name" -f $Port) -UseBasicParsing -TimeoutSec 20).Content
    } catch { return $null }
}

if (Test-Port -Port $gatewayPort) {
    if (Get-LocalBrand -Port $gatewayPort) { Write-Log ("[gateway] 复用已运行的 Caddy :$gatewayPort") 'OK' }
    else { Write-Log ("[gateway] :$gatewayPort 被占用但不是本 ERP 网关，请先释放该端口") 'ERROR'; exit 1 }
} else {
    $caddyfile = Join-Path $RepoRoot 'deploy\caddy\Caddyfile'
    $env:BACKEND_ADDR = "127.0.0.1:$backendPort"
    Write-Log ("[gateway] 启动 Caddy :$gatewayPort -> $($env:BACKEND_ADDR)")
    $p = Start-Process -FilePath $caddyExe -ArgumentList @('run', '--config', $caddyfile) -WorkingDirectory $RepoRoot `
        -RedirectStandardOutput (Join-Path $LogDir 'caddy-stdout.log') -RedirectStandardError (Join-Path $LogDir 'caddy.log') -WindowStyle Hidden -PassThru
    $p.Id | Set-Content -LiteralPath (Join-Path $RunDir 'caddy.pid') -Encoding ascii
    if (-not (Wait-Port -Port $gatewayPort -TimeoutSeconds 20 -Name 'Caddy')) { exit 1 }
    if (-not (Get-LocalBrand -Port $gatewayPort)) { Write-Log '[gateway] 网关健康检查失败' 'ERROR'; exit 1 }
    Write-Log '[gateway] 网关就绪' 'OK'
}

# ---- 5. 公网隧道（ngrok 优先，cpolar 兜底） ----------------------------------
$publicBase = $null
$urlFile = Join-Path $RunDir 'public-url.txt'
# ngrok 免费版会给浏览器 UA 的请求插警告页（返回 HTML 而非 JSON），带此头才拿到真实响应
$ngrokSkipHeaders = @{ 'ngrok-skip-browser-warning' = 'true' }
function Test-PublicApi {
    param([string]$BaseUrl)
    try {
        $resp = Invoke-WebRequest -Uri ($BaseUrl + '/platformConfig/getPlatform/name') -UseBasicParsing -TimeoutSec 20 -Headers $ngrokSkipHeaders
        if ([int]$resp.StatusCode -ne 200) { return $false }
        $body = [string]$resp.Content
        if ($body -match '<html' -or $body -match 'ERR_NGROK') { return $false }
        return $true
    } catch { return $false }
}
$useNgrok = ($tunnelMode -ne 'cpolar') -and [bool]$ngrokToken -and [bool]$ngrokExe
if ($NoTunnel) {
    Write-Log '[tunnel] 已按参数跳过隧道' 'WARN'
    if (Test-Path -LiteralPath $urlFile) { $publicBase = ((Get-Content -LiteralPath $urlFile -Raw).Trim() + '/jshERP-boot') }
} else {
    if ($tunnelMode -eq 'ngrok' -and (-not $ngrokToken -or -not $ngrokExe)) {
        Write-Log '[tunnel] 指定了 ngrok，但 NGROK_AUTHTOKEN 为空或缺少 ngrok.exe' 'ERROR'
        exit 1
    }
    if (-not $ngrokToken) {
        Write-Log '[tunnel] NGROK_AUTHTOKEN 未配置，先用 cpolar 兜底；填入 token 后重跑本脚本即自动切换 ngrok' 'WARN'
    }

    if ($useNgrok) {
        $ngrokOut = Join-Path $LogDir 'ngrok-erp.out.log'
        $ngrokErr = Join-Path $LogDir 'ngrok-erp.err.log'
        $ngrokStarted = $false
        # 复用上一个仍然存活的 ngrok 隧道
        if (Test-Path -LiteralPath $ngrokOut) {
            $prev = [regex]::Match((Get-Content -LiteralPath $ngrokOut -Raw -ErrorAction SilentlyContinue), 'https://[A-Za-z0-9\.\-]+\.ngrok(?:-free)?\.(?:app|dev|io)')
            if ($prev.Success) {
                if (Test-PublicApi -BaseUrl ($prev.Value + '/jshERP-boot')) {
                    $publicBase = $prev.Value + '/jshERP-boot'
                    Write-Log ("[tunnel] 复用已有 ngrok 隧道 " + $prev.Value) 'OK'
                }
            }
        }
        if (-not $publicBase) {
            Remove-Item -LiteralPath $ngrokOut, $ngrokErr -Force -ErrorAction SilentlyContinue
            Write-Log ("[tunnel] 启动 ngrok http $gatewayPort")
            $ngrokArgs = @('http', "$gatewayPort", "--authtoken=$ngrokToken", '--log=stdout', '--log-format=json')
            if ($ngrokDomain) { $ngrokArgs += "--domain=$ngrokDomain" }
            $p = Start-Process -FilePath $ngrokExe -ArgumentList $ngrokArgs -WorkingDirectory (Split-Path -Parent $ngrokExe) `
                -RedirectStandardOutput $ngrokOut -RedirectStandardError $ngrokErr -WindowStyle Hidden -PassThru
            $p.Id | Set-Content -LiteralPath (Join-Path $RunDir 'ngrok.pid') -Encoding ascii
            $ngrokStarted = $true
            $watch = [Diagnostics.Stopwatch]::StartNew()
            while ($watch.Elapsed.TotalSeconds -lt 45 -and -not $publicBase) {
                Start-Sleep -Seconds 2
                $m = [regex]::Match((Get-Content -LiteralPath $ngrokOut -Raw -ErrorAction SilentlyContinue), 'https://[A-Za-z0-9\.\-]+\.ngrok(?:-free)?\.(?:app|dev|io)')
                if ($m.Success) { $publicBase = $m.Value + '/jshERP-boot' }
            }
            if (-not $publicBase -and $ngrokDomain) {
                $candidate = "https://$($ngrokDomain.TrimEnd('/'))"
                $publicBase = $candidate + '/jshERP-boot'
            }
        }
        if ($publicBase) {
            try {
                if (-not (Test-PublicApi -BaseUrl $publicBase)) { throw '公网接口校验失败（可能被 ngrok 拦截页挡住或后端未就绪）' }
                Write-Log ("[tunnel] 公网后端 " + $publicBase) 'OK'
                # ngrok 已接管：停掉可能残留的 cpolar，避免双隧道
                $cpolarPidFile = Join-Path $RunDir 'cpolar.pid'
                if (Test-Path -LiteralPath $cpolarPidFile) {
                    $oldPid = [int]((Get-Content -LiteralPath $cpolarPidFile -Raw).Trim())
                    if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
                    Remove-Item -LiteralPath $cpolarPidFile -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Log ('[tunnel] ngrok 公网探测失败: ' + $_.Exception.Message) 'WARN'
                $publicBase = $null
            }
        }
        if (-not $publicBase) {
            Write-Log '[tunnel] ngrok 未建立可用隧道，回退 cpolar（检查 token 是否有效、域名是否被占用）' 'WARN'
            if ($ngrokStarted -and $p) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not $publicBase) {
        if (-not $cpolarExe) {
            Write-Log '[tunnel] 未找到 cpolar.exe（期望 deploy/local/.tools/cpolar/cpolar.exe）' 'ERROR'
            exit 1
        }
        $cpOut = Join-Path $LogDir 'cpolar-erp.out.log'
        $cpErr = Join-Path $LogDir 'cpolar-erp.err.log'
        # 已有同端口隧道则复用
        if (Test-Path -LiteralPath $cpOut) {
            $prev = [regex]::Match((Get-Content -LiteralPath $cpOut -Raw -ErrorAction SilentlyContinue), 'https://[A-Za-z0-9\.\-]+\.cpolar\.(?:top|cn|io)')
            if ($prev.Success) {
                $probe = $prev.Value + '/jshERP-boot/platformConfig/getPlatform/name'
                try {
                    if ((Invoke-WebRequest -Uri $probe -UseBasicParsing -TimeoutSec 20).StatusCode -eq 200) {
                        $publicBase = $prev.Value + '/jshERP-boot'
                        Write-Log ("[tunnel] 复用已有隧道 " + $prev.Value) 'OK'
                    }
                } catch { }
            }
        }
        if (-not $publicBase) {
            Remove-Item -LiteralPath $cpOut, $cpErr -Force -ErrorAction SilentlyContinue
            Write-Log ("[tunnel] 启动 cpolar http $gatewayPort")
            $p = Start-Process -FilePath $cpolarExe -ArgumentList @('http', "$gatewayPort", '--log=stdout') -WorkingDirectory (Split-Path -Parent $cpolarExe) `
                -RedirectStandardOutput $cpOut -RedirectStandardError $cpErr -WindowStyle Hidden -PassThru
            $p.Id | Set-Content -LiteralPath (Join-Path $RunDir 'cpolar.pid') -Encoding ascii
            $watch = [Diagnostics.Stopwatch]::StartNew()
            while ($watch.Elapsed.TotalSeconds -lt 60 -and -not $publicBase) {
                Start-Sleep -Seconds 2
                $m = [regex]::Match((Get-Content -LiteralPath $cpOut -Raw -ErrorAction SilentlyContinue), 'https://[A-Za-z0-9\.\-]+\.cpolar\.(?:top|cn|io)')
                if ($m.Success) { $publicBase = $m.Value + '/jshERP-boot' }
            }
            if (-not $publicBase) { Write-Log '[tunnel] 60s 内未拿到公网地址，检查 cpolar 是否已登录' 'ERROR'; exit 1 }
        }
        Write-Log ("[tunnel] 公网后端 " + $publicBase) 'OK'
        try {
            $null = Invoke-WebRequest -Uri ($publicBase + '/platformConfig/getPlatform/name') -UseBasicParsing -TimeoutSec 30
        } catch {
            Write-Log ('[tunnel] 公网探测失败: ' + $_.Exception.Message) 'WARN'
        }
    }
    ($publicBase -replace '/jshERP-boot$','') | Set-Content -LiteralPath $urlFile -Encoding ascii
}

# ---- 6. 发布 Pages 指向 -----------------------------------------------------
function Publish-PagesConfigViaApi {
    param([string]$ApiBase)
    $gitCmd = Get-GitExe
    if (-not $gitCmd) { Write-Log '[pages] 未找到 git.exe，无法读取 GitHub 凭据' 'ERROR'; return $false }
    $token = $null
    try {
        $credText = ("protocol=https`nhost=github.com`n`n" | & $gitCmd credential fill 2>$null)
        $passLine = $credText | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
        if (-not $passLine) { throw 'GitHub token not found in credential manager' }
        $token = $passLine.Substring(9)
        $headers = @{
            'Authorization' = 'Bearer ' + $token
            'Accept' = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent' = 'siyu-erp-startup'
        }
        $path = 'jshERP-web/public/config.js'
        $uri = 'https://api.github.com/repos/' + $publicRepo + '/contents/' + $path
        $remote = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30
        $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $RepoRoot 'jshERP-web\public\config.js')))
        $payload = @{
            message = "chore: point Pages at $ApiBase"
            content = $content
            branch = 'main'
            sha = $remote.sha
        } | ConvertTo-Json -Compress
        $res = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 60
        Write-Log ('[pages] GitHub API 已提交 ' + $res.commit.sha.Substring(0,7)) 'OK'
        return $true
    } catch {
        Write-Log ('[pages] GitHub API 发布失败: ' + $_.Exception.Message) 'ERROR'
        return $false
    } finally {
        Remove-Variable token -ErrorAction SilentlyContinue
    }
}

function Set-PagesConfig {
    param([string]$ApiBase, [switch]$Push)
    $configPath = Join-Path $RepoRoot 'jshERP-web\public\config.js'
    $configText = @"
/*
 * 思雨食品 ERP 运行时配置
 * 由 deploy/local/start-erp.ps1 自动生成；也可由 GitHub Actions workflow_dispatch(api_base) 注入
 */
window.ERP_CONFIG = {
  apiBase: '$ApiBase'
};
"@
    [IO.File]::WriteAllText($configPath, $configText, [Text.UTF8Encoding]::new($false))
    Write-Log ("[pages] 写入 config.js -> $ApiBase") 'OK'

    if (-not $Push) {
        Write-Log '[pages] 已跳过推送（-NoPublish）。'
        return
    }
    $git = Get-GitExe
    if (-not $git) { Write-Log '[pages] 未找到 git.exe，无法推送。' 'WARN'; return }
    # 计划任务/无桌面环境里 Git Credential Manager 会弹窗卡死，必须强制非交互
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'never'
    $status = & $git -C $RepoRoot status --porcelain -- jshERP-web/public/config.js
    if (-not $status) {
        Write-Log '[pages] config.js 无变化，无需推送（Pages 已一致）。'
        return
    }
    & $git -C $RepoRoot add jshERP-web/public/config.js | Out-Null
    & $git -C $RepoRoot commit -m "chore: point Pages at $ApiBase" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log '[pages] git commit 失败' 'ERROR'; return }

    # 远端可能领先（Actions/其他机器推过）→ 先 rebase 再推，避免 non-fast-forward
    & $git -C $RepoRoot fetch origin main --quiet 2>&1 | Out-Null
    $behind = [int]((& $git -C $RepoRoot rev-list --count 'HEAD..origin/main' 2>$null) -join '').Trim()
    if ($behind -gt 0) {
        Write-Log ("[pages] 远端领先 {0} 个提交，先 rebase" -f $behind)
        & $git -C $RepoRoot pull --rebase --autostash origin main 2>&1 | ForEach-Object { Write-Log ("[git] " + $_) }
        if ($LASTEXITCODE -ne 0) {
            & $git -C $RepoRoot rebase --abort 2>&1 | Out-Null
            Write-Log '[pages] rebase 失败（可能存在冲突），已回滚本地提交之外的改动' 'ERROR'
            Write-Log ("        手动处理：cd $RepoRoot; git pull --rebase; git push；或在 Actions 页面用 api_base 手动发布") 'WARN'
            return
        }
    }
    $pushed = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        & $git -C $RepoRoot push origin main 2>&1 | ForEach-Object { Write-Log ("[git] " + $_) }
        if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
        Write-Log ("[pages] push 第 {0} 次失败，拉取远端后重试" -f $attempt) 'WARN'
        & $git -C $RepoRoot fetch origin main --quiet 2>&1 | Out-Null
        & $git -C $RepoRoot pull --rebase --autostash origin main 2>&1 | ForEach-Object { Write-Log ("[git] " + $_) }
        if ($LASTEXITCODE -ne 0) { & $git -C $RepoRoot rebase --abort 2>&1 | Out-Null; break }
    }
    if ($pushed) {
        Write-Log '[pages] 已推送，GitHub Actions 正在重建 Pages' 'OK'
    } else {
        Write-Log '[pages] git push 失败，改用 GitHub Contents API' 'WARN'
        if (Publish-PagesConfigViaApi -ApiBase $ApiBase) {
            Write-Log '[pages] GitHub API 发布成功，Actions 将重建 Pages' 'OK'
        } else {
            Write-Log '[pages] 自动发布失败，需要手动发布' 'ERROR'
            Write-Log ("        手动方式：GitHub -> Actions -> 'Build Pages and Publish Images' -> Run workflow，api_base 填 $ApiBase") 'WARN'
        }
    }
    Write-Log ("[actions] https://github.com/$publicRepo/actions")
}

if ($publicBase) {
    # cpolar 免费版每次地址都会变，只有地址变化时才写文件/推送
    $apiBase = if ($publicBase -match '/jshERP-boot$') { $publicBase } else { $publicBase + '/jshERP-boot' }
    $existing = $null
    $cfgPath = Join-Path $RepoRoot 'jshERP-web\public\config.js'
    if (Test-Path -LiteralPath $cfgPath) {
        $m = [regex]::Match((Get-Content -LiteralPath $cfgPath -Raw), "apiBase:\s*'([^']+)'")
        if ($m.Success) { $existing = $m.Groups[1].Value }
    }
    if ($existing -eq $apiBase) {
        Write-Log '[pages] config.js 已指向当前地址，跳过发布' 'OK'
    } else {
        Set-PagesConfig -ApiBase $apiBase -Push:(-not $NoPublish)
    }
}

# ---- 7. 汇总 ----------------------------------------------------------------
Write-Host ''
Write-Host '======================== 启动完成 ========================'
Write-Host ("  MariaDB     : 127.0.0.1:{0}" -f $dbPort)
Write-Host ("  Redis       : 127.0.0.1:{0}" -f $redisPort)
Write-Host ("  后端直连    : http://127.0.0.1:{0}/jshERP-boot" -f $backendPort)
Write-Host ("  网关(Caddy) : http://127.0.0.1:{0}/jshERP-boot" -f $gatewayPort)
if ($publicBase) { Write-Host ("  公网后端    : $publicBase") }
Write-Host ("  Pages 入口  : {0}/user/login" -f $pagesUrl)
Write-Host ("  Actions     : https://github.com/{0}/actions" -f $publicRepo)
Write-Host '=========================================================='
Write-Host ''
Write-Log '---- done ----'
