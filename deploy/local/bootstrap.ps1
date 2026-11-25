param(
    [switch]$Force
)

. "$PSScriptRoot\common.ps1"

$ProgressPreference = 'SilentlyContinue'
$Downloads = Join-Path $script:ToolsRoot '_downloads'
New-Item -ItemType Directory -Path $script:ToolsRoot, $Downloads -Force | Out-Null

function Get-Download {
    param([string]$Url, [string]$OutFile, [string]$Label)
    if ((Test-Path -LiteralPath $OutFile) -and -not $Force) {
        Write-Host "[skip] $Label (already downloaded)"
        return
    }
    Write-Host "[download] $Label"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600
}

function Expand-Component {
    param([string]$Zip, [string]$Destination, [string]$Label)
    if (-not (Test-Path -LiteralPath $Zip)) { throw "Missing archive for $Label" }
    if ($Force -and (Test-Path -LiteralPath $Destination)) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Write-Host "[extract] $Label"
    Expand-Archive -LiteralPath $Zip -DestinationPath $Destination -Force
}

function Test-Component {
    param([string]$Component, [string]$ExeName)
    $dir = Join-Path $script:ToolsRoot $Component
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    return [bool](Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $ExeName -ErrorAction SilentlyContinue | Select-Object -First 1)
}

# MariaDB 10.11 LTS (MySQL-compatible, Windows x64 portable)
if (-not (Test-Component 'mariadb' 'mysqld.exe') -or $Force) {
    $zip = Join-Path $Downloads 'mariadb-10.11.10-winx64.zip'
    Get-Download 'https://archive.mariadb.org/mariadb-10.11.10/winx64-packages/mariadb-10.11.10-winx64.zip' $zip 'MariaDB 10.11.10'
    Expand-Component $zip (Join-Path $script:ToolsRoot 'mariadb') 'MariaDB'
} else {
    Write-Host '[skip] MariaDB'
}

# Eclipse Temurin JRE 8
if (-not (Test-Component 'jre' 'java.exe') -or $Force) {
    $zip = Join-Path $Downloads 'temurin-jre8-windows-x64.zip'
    Get-Download 'https://api.adoptium.net/v3/binary/latest/8/ga/windows/x64/jre/hotspot/normal/eclipse' $zip 'Temurin JRE 8'
    Expand-Component $zip (Join-Path $script:ToolsRoot 'jre') 'Temurin JRE 8'
} else {
    Write-Host '[skip] Temurin JRE 8'
}

# Redis 5.0.14.1 for Windows (tporadowski build)
if (-not (Test-Component 'redis' 'redis-server.exe') -or $Force) {
    $zip = Join-Path $Downloads 'Redis-x64-5.0.14.1.zip'
    Get-Download 'https://github.com/tporadowski/redis/releases/download/v5.0.14.1/Redis-x64-5.0.14.1.zip' $zip 'Redis 5.0.14.1'
    Expand-Component $zip (Join-Path $script:ToolsRoot 'redis') 'Redis'
} else {
    Write-Host '[skip] Redis'
}

# Caddy 2 (HTTPS/CORS gateway)
if (-not (Test-Component 'caddy' 'caddy.exe') -or $Force) {
    $zip = Join-Path $Downloads 'caddy-windows-amd64.zip'
    Get-Download 'https://github.com/caddyserver/caddy/releases/download/v2.11.9/caddy_2.11.9_windows_amd64.zip' $zip 'Caddy 2.11.9'
    Expand-Component $zip (Join-Path $script:ToolsRoot 'caddy') 'Caddy'
} else {
    Write-Host '[skip] Caddy'
}

# ngrok v3
if (-not (Test-Component 'ngrok' 'ngrok.exe') -or $Force) {
    $zip = Join-Path $Downloads 'ngrok-v3-windows-amd64.zip'
    Get-Download 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip' $zip 'ngrok v3'
    Expand-Component $zip (Join-Path $script:ToolsRoot 'ngrok') 'ngrok'
} else {
    Write-Host '[skip] ngrok'
}

if (-not (Test-Path -LiteralPath $script:EnvFile)) {
    $dbPassword = 'siyu_' + ([guid]::NewGuid().ToString('N').Substring(0, 16))
    $redisPassword = 'redis_' + ([guid]::NewGuid().ToString('N').Substring(0, 16))
    $envText = @"
# Local-only secrets. This file is gitignored.
DB_PASSWORD=$dbPassword
REDIS_PASSWORD=$redisPassword
NGROK_AUTHTOKEN=
NGROK_DOMAIN=
"@
    [IO.File]::WriteAllText($script:EnvFile, $envText, [Text.UTF8Encoding]::new($false))
    Write-Host "[created] $script:EnvFile"
    Write-Host 'Edit it and set NGROK_AUTHTOKEN / optional NGROK_DOMAIN before starting ngrok.'
} else {
    Write-Host "[keep] $script:EnvFile"
}

Write-Host ''
Write-Host 'Tools ready:'
Write-Host ('  MariaDB : ' + (Find-Tool 'mariadb' 'mysqld.exe'))
Write-Host ('  Java    : ' + (Find-Tool 'jre' 'java.exe'))
Write-Host ('  Redis   : ' + (Find-Tool 'redis' 'redis-server.exe'))
Write-Host ('  Caddy   : ' + (Find-Tool 'caddy' 'caddy.exe'))
Write-Host ('  ngrok   : ' + (Find-Tool 'ngrok' 'ngrok.exe'))
