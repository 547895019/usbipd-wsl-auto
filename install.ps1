# One-time setup. Optionally pass -Distro to override the default WSL distro:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Distro Ubuntu-24.04
#Requires -Version 5.1
param(
    [string]$Distro,
    [int]$RepeatMinutes = 1
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Not elevated. Re-launching and waiting for approval...'
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path
    if ($Distro) { $arg += ' -Distro "{0}"' -f ($Distro -replace '"', '\"') }
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root 'allowlist.ps1')
$Watcher = Join-Path $Root 'usbipd-wsl-auto.ps1'
$ConfigPath = Join-Path $Root 'config.json'
$Usbipd = Join-Path ${env:ProgramFiles} 'usbipd-win\usbipd.exe'
if (-not (Test-Path -LiteralPath $Usbipd)) { throw "usbipd.exe not found: $Usbipd" }
if (-not (Test-Path -LiteralPath $Watcher)) { throw "watcher not found: $Watcher" }

$distros = @(& wsl.exe --list --quiet) | ForEach-Object {
    ([string]$_) -replace "`0", ''
} | ForEach-Object {
    $_.Trim()
} | Where-Object {
    $_
}
if ($distros.Count -eq 0) {
    throw 'No WSL distribution is registered. Install one and start it once before installing.'
}
if (-not $Distro) {
    $Distro = ''
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (Test-Path -LiteralPath $lxss) {
        $defaultGuid = [string](Get-ItemProperty -LiteralPath $lxss).DefaultDistribution
        foreach ($entry in @(Get-ChildItem -LiteralPath $lxss)) {
            if ($entry.PSChildName -eq $defaultGuid) {
                $Distro = [string]$entry.GetValue('DistributionName')
                break
            }
        }
    }
    if (-not $Distro) { $Distro = [string]$distros[0] }
}
if ($distros -notcontains $Distro) {
    throw "WSL distribution '$Distro' is not registered. Available: $($distros -join ', ')"
}
Write-Host "Target WSL distribution: $Distro"

$oldGuids = @{}
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $oldCfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($g in @($oldCfg.policyGuids)) {
            if ($g) { $oldGuids[[string]$g] = $true }
        }
    } catch {
        Write-Warning "Ignoring unreadable previous config: $($_.Exception.Message)"
    }
}

$policyText = & $Usbipd policy list 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "usbipd policy list exited ${LASTEXITCODE}: $policyText" }
$seen = @{}
$policyGuids = New-Object System.Collections.Generic.List[string]
foreach ($line in ($policyText -split "`r?`n")) {
    if ($line -notmatch '^([0-9a-fA-F-]{36})\s+Allow\s+AutoBind\s+(\S*)\s+([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s*$') { continue }
    $guid = $Matches[1]
    $busid = $Matches[2]
    $id = $Matches[3].ToLowerInvariant()
    if ($oldGuids.ContainsKey($guid)) {
        if ($Allow -contains $id -and -not $seen.ContainsKey($id)) {
            # Keep the previously recorded rule and its GUID so uninstall still
            # owns exactly the same rules after a repeated installation.
            $seen[$id] = $true
            [void]$policyGuids.Add($guid)
        } else {
            Write-Host "Removing policy $guid no longer in the allowlist"
            & $Usbipd policy remove --guid $guid
            if ($LASTEXITCODE -ne 0) { throw "Could not remove previous policy $guid" }
        }
        continue
    }
    if (-not $busid -and ($Allow -contains $id) -and -not $seen.ContainsKey($id)) {
        $seen[$id] = $true
        [void]$policyGuids.Add($guid)
    }
}
foreach ($id in $Allow) {
    if ($seen.ContainsKey($id)) {
        Write-Host "AutoBind $id (already present)"
        continue
    }
    $before = @($policyGuids)
    & $Usbipd policy add --effect Allow --operation AutoBind --hardware-id $id
    if ($LASTEXITCODE -ne 0) { throw "policy add $id exited $LASTEXITCODE" }
    $newText = & $Usbipd policy list 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "usbipd policy list exited $LASTEXITCODE" }
    $found = $false
    foreach ($line in ($newText -split "`r?`n")) {
        if ($line -notmatch '^([0-9a-fA-F-]{36})\s+Allow\s+AutoBind\s+(\S*)\s+([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s*$') { continue }
        if ($Matches[2] -or $Matches[3].ToLowerInvariant() -ne $id -or $before -contains $Matches[1]) { continue }
        [void]$policyGuids.Add($Matches[1])
        $found = $true
        break
    }
    if (-not $found) { throw "Could not identify the new AutoBind policy for $id" }
    Write-Host "AutoBind $id"
}

$utf8 = New-Object System.Text.UTF8Encoding $false
$payload = @{
    distro = $Distro
    policyGuids = @($policyGuids)
} | ConvertTo-Json -Depth 4
$tempConfig = "$ConfigPath.tmp"
[System.IO.File]::WriteAllText($tempConfig, $payload, $utf8)
Move-Item -LiteralPath $tempConfig -Destination $ConfigPath -Force
Write-Host "Wrote $ConfigPath with $($policyGuids.Count) recorded policy rule(s)"

$taskName = 'usbipd-wsl-auto'
$arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $Watcher
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $Root
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# A killed watcher (console close, session changes, crashes) is only restarted
# at the next logon by the AtLogOn trigger. The repeating trigger is the
# keepalive: it re-runs the task every $RepeatMinutes, and a running mutex-owner
# makes each extra run exit immediately.
$repeatTrigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(15)) `
    -RepetitionInterval (New-TimeSpan -Minutes $RepeatMinutes)
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -RestartCount 10 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logonTrigger, $repeatTrigger) -Settings $settings -Principal $taskPrincipal -Force | Out-Null
$task = Get-ScheduledTask -TaskName $taskName
if ($task.State -eq 'Running') { Stop-ScheduledTask -TaskName $taskName }
# Stop-ScheduledTask does not reliably stop the PowerShell child it launched.
# End only watchers whose command line names this exact script, then start fresh.
foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'")) {
    $cmd = [string]$proc.CommandLine
    if ($cmd -and ($cmd -like "*$Watcher*") -and ($proc.ProcessId -ne $PID)) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3
$info = Get-ScheduledTaskInfo -TaskName $taskName
$task = Get-ScheduledTask -TaskName $taskName
Write-Host "Task $taskName state=$($task.State) lastResult=$($info.LastTaskResult) user=$env:USERNAME"
if ($info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267009) {
    throw "Watcher did not start successfully; scheduled task result $($info.LastTaskResult)"
}
Write-Host "Log: $env:LOCALAPPDATA\usbipd-wsl-auto\attach.log"
Write-Host 'Devices already attached to WSL were left attached.'
