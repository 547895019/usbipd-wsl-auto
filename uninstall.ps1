# Undo install.ps1. Devices already attached to WSL stay attached.
# Run from an elevated PowerShell, from this folder:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Not elevated. Re-launching and waiting for approval...'
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Watcher = Join-Path $Root 'usbipd-wsl-auto.ps1'
$ConfigPath = Join-Path $Root 'config.json'
$taskName = 'usbipd-wsl-auto'
$Usbipd = Join-Path ${env:ProgramFiles} 'usbipd-win\usbipd.exe'

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed scheduled task $taskName"
} else {
    Write-Host "Scheduled task $taskName is not installed"
}

$stopped = 0
foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'")) {
    $cmd = [string]$proc.CommandLine
    if ($cmd -and ($cmd -like "*$Watcher*") -and ($proc.ProcessId -ne $PID)) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped++
        Write-Host "Stopped watcher pid $($proc.ProcessId)"
    }
}
if ($stopped -eq 0) {
    Write-Host 'No watcher process was running'
}

$owned = @{}
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($g in @($cfg.policyGuids)) {
        if ($g) { $owned[[string]$g.ToLowerInvariant()] = $true }
    }
}

if (-not (Test-Path -LiteralPath $Usbipd)) {
    Write-Warning "usbipd.exe not found: $Usbipd"
} elseif ($owned.Count -eq 0) {
    Write-Host 'No policy GUIDs recorded in config.json; nothing removed'
} else {
    $removed = 0
    foreach ($guid in @($owned.Keys)) {
        $output = & $Usbipd policy remove --guid $guid 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $output -match '(?i)not found|does not exist|找不到|不存在') {
            $removed++
            Write-Host "Removed policy $guid (or it was already absent)"
        } else {
            Write-Warning "policy remove $guid exited ${LASTEXITCODE}: $output"
        }
    }
    Write-Host "Processed $removed recorded policy rule(s); unrelated policies were not changed"
}

$statePath = Join-Path $env:LOCALAPPDATA 'usbipd-wsl-auto\watch-state.json'
if (Test-Path -LiteralPath $statePath) {
    Remove-Item -LiteralPath $statePath -Force
}
if (Test-Path -LiteralPath $ConfigPath) {
    Remove-Item -LiteralPath $ConfigPath -Force
    Write-Host "Removed $ConfigPath"
}

Write-Host 'Uninstall done. Devices already attached to WSL were left attached.'
if (Test-Path -LiteralPath $Usbipd) {
    Write-Host 'usbipd policy list:'
    & $Usbipd policy list
}
