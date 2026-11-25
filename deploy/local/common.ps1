# Shared helpers for the portable Windows stack.
$ErrorActionPreference = 'Stop'
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:LocalRoot = $PSScriptRoot
$script:ToolsRoot = Join-Path $LocalRoot '.tools'
$script:RunRoot = Join-Path $LocalRoot 'run'
$script:LogRoot = Join-Path $LocalRoot 'logs'
$script:DataRoot = Join-Path $LocalRoot 'data'
$script:EnvFile = Join-Path $LocalRoot '.env'

function Read-DotEnv {
    param([string]$Path = $script:EnvFile)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing $Path. Run deploy/local/bootstrap.ps1 first."
    }
    $map = @{}
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"').Trim("'")
            $map[$key] = $value
        }
    }
    return $map
}

function Get-EnvValue {
    param($Map, [string]$Key, [string]$Default = '')
    if ($Map.ContainsKey($Key) -and $Map[$Key]) { return $Map[$Key] }
    return $Default
}

function Find-Tool {
    param([string]$Component, [string]$ExeName)
    $dir = Join-Path $script:ToolsRoot $Component
    if (-not (Test-Path -LiteralPath $dir)) {
        throw "Tool '$Component' is missing. Run deploy/local/bootstrap.ps1 first."
    }
    $file = Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $ExeName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $file) {
        throw "Cannot find $ExeName under $dir. Re-run deploy/local/bootstrap.ps1."
    }
    return $file.FullName
}

function Wait-Port {
    param([int]$Port, [int]$TimeoutSeconds = 60, [string]$Name = 'service')
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $client.Connect('127.0.0.1', $Port)
            return $true
        } catch {
        } finally {
            $client.Close()
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Warning "$Name did not open port $Port within $TimeoutSeconds seconds."
    return $false
}

function Test-Port {
    param([int]$Port)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', $Port)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-GitExe {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = 'C:\Program Files\Git\cmd\git.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw 'git.exe not found.'
}
