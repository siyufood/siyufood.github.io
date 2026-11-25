param()

. "$PSScriptRoot\common.ps1"

$envMap = Read-DotEnv
$dbHost = Get-EnvValue $envMap 'DB_HOST' '127.0.0.1'
$dbPort = [int](Get-EnvValue $envMap 'DB_PORT' '3307')
$dbUser = Get-EnvValue $envMap 'DB_USER' 'root'
$dbPassword = Get-EnvValue $envMap 'DB_PASSWORD'
if (-not $dbPassword) { throw 'DB_PASSWORD is empty in deploy/local/.env' }

$mysql = Find-Tool 'mariadb' 'mysql.exe'
$mysqld = Find-Tool 'mariadb' 'mysqld.exe'
$installer = Find-Tool 'mariadb' 'mysql_install_db.exe'
$mysqlAdmin = Find-Tool 'mariadb' 'mysqladmin.exe'
$mariaRoot = Split-Path -Parent (Split-Path -Parent $mysqld)

$dataDir = Join-Path $script:DataRoot 'mysql'
$runtimeDir = Join-Path $script:LocalRoot 'runtime'
$myIni = Join-Path $runtimeDir 'my.ini'
$mysqlLog = Join-Path $script:LogRoot 'mysql.log'
New-Item -ItemType Directory -Path $dataDir, $runtimeDir, $script:RunRoot, $script:LogRoot -Force | Out-Null

$myIniText = @"
[mysqld]
basedir=$mariaRoot
datadir=$dataDir
port=$dbPort
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_general_ci
max_connections=200
innodb_buffer_pool_size=256M
pid-file=$dataDir\mysqld.pid
tmpdir=$runtimeDir
log-error=$mysqlLog
[client]
port=$dbPort
default-character-set=utf8mb4
"@
if (-not (Test-Path -LiteralPath $myIni) -or ((Get-Content -LiteralPath $myIni -Raw) -notmatch "port=$dbPort")) {
    [IO.File]::WriteAllText($myIni, $myIniText, [Text.UTF8Encoding]::new($false))
    Write-Host "[created] $myIni"
}

if (-not (Test-Path -LiteralPath (Join-Path $dataDir 'mysql'))) {
    Write-Host '[init] MariaDB data directory (first run, about 10-30 seconds)'
    & $installer --datadir=$dataDir --password=$dbPassword
    if ($LASTEXITCODE -ne 0) { throw 'mysql_install_db failed.' }
} else {
    Write-Host '[skip] MariaDB data directory already initialized'
}

if (-not (Test-Port $dbPort)) {
    Write-Host "[start] MariaDB :$dbPort"
    $proc = Start-Process -FilePath $mysqld -ArgumentList @("--defaults-file=$myIni", '--console') -WorkingDirectory (Split-Path -Parent $mysqld) -RedirectStandardOutput (Join-Path $script:LogRoot 'mysql-stdout.log') -RedirectStandardError (Join-Path $script:LogRoot 'mysql-stderr.log') -WindowStyle Hidden -PassThru
    $proc.Id | Set-Content -LiteralPath (Join-Path $script:RunRoot 'mysql.pid') -Encoding ascii
    if (-not (Wait-Port $dbPort 60 'MariaDB')) {
        Get-Content -LiteralPath $mysqlLog -Tail 40 -ErrorAction SilentlyContinue
        throw 'MariaDB did not start. Check deploy/local/logs/mysql.log.'
    }
} else {
    Write-Host "[skip] MySQL/MariaDB already listening on $dbPort"
}

$baseArgs = @("--host=$dbHost", "--port=$dbPort", "--user=$dbUser", '--protocol=tcp', '--default-character-set=utf8mb4')
$authArgs = $baseArgs + "--password=$dbPassword"
$authWorks = $false
try {
    & $mysql @authArgs -e 'SELECT 1;' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $authWorks = $true }
} catch { }

if (-not $authWorks) {
    Write-Host '[auth] Setting MariaDB root password (first run)'
    $noPassArgs = $baseArgs
    $sql = "ALTER USER '$dbUser'@'localhost' IDENTIFIED BY '$dbPassword'; CREATE USER IF NOT EXISTS '$dbUser'@'127.0.0.1' IDENTIFIED BY '$dbPassword'; GRANT ALL PRIVILEGES ON *.* TO '$dbUser'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;"
    & $mysql @noPassArgs -e $sql
    if ($LASTEXITCODE -ne 0) { throw "Could not set database password for $dbUser. Check DB_USER/DB_PASSWORD in deploy/local/.env." }
} else {
    Write-Host '[auth] Database password already valid'
    & $mysql @authArgs -e "CREATE USER IF NOT EXISTS '$dbUser'@'127.0.0.1' IDENTIFIED BY '$dbPassword'; GRANT ALL PRIVILEGES ON *.* TO '$dbUser'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;" | Out-Null
}

& $mysql @authArgs -e "CREATE DATABASE IF NOT EXISTS jsh_erp DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" | Out-Null

$tableCount = & $mysql @authArgs -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='jsh_erp' AND table_name='jsh_user';" 2>$null
$fresh = ([int]$tableCount -eq 0)

function Import-Sql {
    param([string]$RelativePath)
    $path = (Join-Path $script:RepoRoot $RelativePath).Replace('\', '/')
    Write-Host "[import] $RelativePath"
    & $mysql @authArgs --database=jsh_erp -e "SOURCE $path;"
    if ($LASTEXITCODE -ne 0) { throw "Import failed: $RelativePath" }
}

if ($fresh) {
    Import-Sql 'sql\jsh_erp.sql'
    Import-Sql 'plugins\plugin-schema.sql'
    Import-Sql 'plugins\plugin-menu.sql'
    Import-Sql 'sql\siyu-brand-config.sql'
    Import-Sql 'plugins\plugin-role-grant.sql'
} else {
    Write-Host '[skip] jsh_erp schema already exists; applying idempotent brand/menu grant only'
    Import-Sql 'sql\siyu-brand-config.sql'
    Import-Sql 'plugins\plugin-role-grant.sql'
}

$users = & $mysql @authArgs --database=jsh_erp -N -B -e "SELECT login_name FROM jsh_user ORDER BY id LIMIT 12;" 2>$null
$pluginCount = & $mysql @authArgs --database=jsh_erp -N -B -e "SELECT COUNT(*) FROM jsh_function WHERE LEFT(number,2)='09' AND delete_flag<>'1';" 2>$null
$granted = & $mysql @authArgs --database=jsh_erp -N -B -e "SELECT COUNT(*) FROM jsh_user_business WHERE type='RoleFunctions' AND key_id IN ('4','10') AND value LIKE '%[262]%';" 2>$null

Write-Host ''
Write-Host 'Database ready:'
Write-Host ('  database : jsh_erp')
Write-Host ('  plugin menus : ' + $pluginCount)
Write-Host ('  roles 4/10 with plugin grant : ' + $granted)
Write-Host ('  users : ' + ($users -join ', '))
Write-Host '  local root password is in deploy/local/.env'
