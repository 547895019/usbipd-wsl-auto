# Poll usbipd and attach allowlisted USB serial adapters into WSL.
# usbipd --auto-attach follows one device only. Adapters that share one VID:PID
# cannot all be claimed that way, so this script attaches every plugged match.
# Disconnected devices are retried after a grace period, including after WSL restarts.
# Use the PAUSE file or uninstall.ps1 to stop automatic attachment.
# Distro comes from config.json written by install.ps1. Empty means the default WSL distro.
#Requires -Version 5.1
param(
    [switch]$Once
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root 'allowlist.ps1')

$Distro = ''
$ConfigPath = Join-Path $Root 'config.json'
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.distro) { $Distro = [string]$cfg.distro }
}

$IntervalSec = 2
$FailBackoffSec = 20
$AttachGraceSec = 8
$SkipDescription = '(?i)大容量存储|Mass Storage|蓝牙|Bluetooth|Hub|键盘|鼠标|Keyboard|Mouse|Camera|摄像头'

$Usbipd = Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe'
if (-not (Test-Path -LiteralPath $Usbipd)) {
    throw "usbipd.exe not found: $Usbipd"
}

$LogDir = Join-Path $env:LOCALAPPDATA 'usbipd-wsl-auto'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'attach.log'
$StatePath = Join-Path $LogDir 'watch-state.json'
$PauseFile = Join-Path $Root 'PAUSE'

function Write-Log([string]$Message) {
    try {
        $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch {
    }
}

function Invoke-Usbipd {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Argv)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Usbipd
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $quoted = foreach ($a in $Argv) {
        if ($a -match '[\s"]') { '"{0}"' -f ($a -replace '"', '\"') } else { $a }
    }
    $psi.Arguments = $quoted -join ' '
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    return @{
        Code = $proc.ExitCode
        Out  = $outTask.Result.Trim()
        Err  = $errTask.Result.Trim()
    }
}

function Get-VidPid($Device) {
    $src = [string]$Device.InstanceId
    if ($src -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
        return ('{0}:{1}' -f $Matches[1], $Matches[2]).ToLowerInvariant()
    }
    return $null
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\usbipd-wsl-auto')
$locked = $false
try {
    try {
        $locked = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $locked = $true
    }
    if (-not $locked) {
        Write-Log 'already running, exit'
        exit 0
    }

    try {
        $Boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
    } catch {
        $Boot = 'unknown'
    }

    $held = @{}
    if (Test-Path -LiteralPath $StatePath) {
        try {
            $saved = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$saved.boot -eq $Boot -and $saved.held) {
                foreach ($p in $saved.held.PSObject.Properties) {
                    $held[$p.Name] = [string]$p.Value
                }
            }
        } catch {
            Write-Log ("ignore bad state file: {0}" -f $_.Exception.Message)
        }
    }

    function Save-WatchState {
        $map = @{}
        foreach ($k in @($held.Keys)) { $map[$k] = [string]$held[$k] }
        $payload = @{ boot = $Boot; held = $map } | ConvertTo-Json -Depth 5 -Compress
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($StatePath, $payload, $utf8)
    }

    $live = @{}
    $grace = @{}
    $failUntil = @{}
    $pausedLogged = $false

    Write-Log ("watcher start distro={0} allow={1}" -f $Distro, ($Allow -join ','))

    while ($true) {
        try {
            if (Test-Path -LiteralPath $PauseFile) {
                if (-not $pausedLogged) {
                    Write-Log 'PAUSE file present, not attaching'
                    $pausedLogged = $true
                }
            } else {
                if ($pausedLogged) {
                    Write-Log 'PAUSE cleared'
                    $pausedLogged = $false
                }

                $raw = Invoke-Usbipd state
                if ($raw.Code -ne 0) { throw "usbipd state exit $($raw.Code): $($raw.Err)" }
                $state = $raw.Out | ConvertFrom-Json
                $devices = @($state.Devices)
                $plugged = @{}
                $dirty = $false
                $now = Get-Date

                foreach ($dev in $devices) {
                    $bus = [string]$dev.BusId
                    if (-not $bus) { continue }
                    $id = [string]$dev.InstanceId
                    if (-not $id) { continue }
                    $vidpid = Get-VidPid $dev
                    if (-not $vidpid -or ($Allow -notcontains $vidpid)) { continue }
                    $desc = [string]$dev.Description
                    if ($desc -and ($desc -match $SkipDescription)) { continue }

                    $plugged[$id] = $bus
                    $client = [string]$dev.ClientIPAddress

                    if ($client) {
                        $grace.Remove($id)
                        $failUntil.Remove($id)
                        if ($held.ContainsKey($id)) {
                            $held.Remove($id)
                            $dirty = $true
                        }
                        if (-not $live.ContainsKey($id)) {
                            $live[$id] = $true
                            Write-Log ("in wsl {0} {1} {2}" -f $bus, $vidpid, $desc)
                        }
                        continue
                    }

                    if ($held.ContainsKey($id)) {
                        if ($held[$id] -eq $bus) { continue }
                        $held.Remove($id)
                        $dirty = $true
                        Write-Log ("bus changed, clear pause {0} {1}" -f $bus, $vidpid)
                    }

                    if ($grace.ContainsKey($id) -and $grace[$id] -gt $now) { continue }

                    if ($live.ContainsKey($id)) {
                        # A missed client IP can also mean a WSL/network reconnect.
                        # Retry during this grace window rather than treating every
                        # transient disappearance as an intentional manual detach.
                        $grace[$id] = $now.AddSeconds($AttachGraceSec)
                        $live.Remove($id)
                        Write-Log ("not connected, retry after grace {0} {1}" -f $bus, $vidpid)
                        continue
                    }

                    if ($failUntil.ContainsKey($id) -and $failUntil[$id] -gt $now) { continue }

                    $attachArgs = @('attach', '--wsl')
                    if ($Distro) { $attachArgs += $Distro }
                    $attachArgs += @('--busid', $bus)
                    $attached = Invoke-Usbipd @attachArgs
                    $attachText = (('{0} {1}' -f $attached.Out, $attached.Err) -replace '\s+', ' ').Trim()
                    if ($attached.Code -eq 0 -or $attachText -match '(?i)already attached') {
                        $grace[$id] = $now.AddSeconds($AttachGraceSec)
                        $failUntil.Remove($id)
                        Write-Log ("attached {0} {1} {2}" -f $bus, $vidpid, $desc)
                        continue
                    }

                    $needsBind = $attachText -match '(?i)not shared|not bound'
                    $errorState = $attachText -match '(?i)error state'
                    if (-not $needsBind -and -not $errorState) {
                        $failUntil[$id] = $now.AddSeconds($FailBackoffSec)
                        Write-Log ("attach failed {0} {1}: {2}" -f $bus, $vidpid, $attachText)
                        continue
                    }

                    if ($errorState) {
                        Invoke-Usbipd unbind '--busid' $bus | Out-Null
                        $bound = Invoke-Usbipd bind '--force' '--busid' $bus
                    } else {
                        $bound = Invoke-Usbipd bind '--busid' $bus
                    }
                    $bindText = (('{0} {1}' -f $bound.Out, $bound.Err) -replace '\s+', ' ').Trim()
                    if ($bound.Code -ne 0) {
                        $failUntil[$id] = $now.AddSeconds($FailBackoffSec)
                        Write-Log ("bind failed {0} {1}: {2}" -f $bus, $vidpid, $bindText)
                        continue
                    }

                    $attached = Invoke-Usbipd @attachArgs
                    $attachText = (('{0} {1}' -f $attached.Out, $attached.Err) -replace '\s+', ' ').Trim()
                    if ($attached.Code -eq 0) {
                        $grace[$id] = $now.AddSeconds($AttachGraceSec)
                        $failUntil.Remove($id)
                        Write-Log ("bound+attached {0} {1} {2}" -f $bus, $vidpid, $desc)
                    } else {
                        $failUntil[$id] = $now.AddSeconds($FailBackoffSec)
                        Write-Log ("attach after bind failed {0} {1}: {2}" -f $bus, $vidpid, $attachText)
                    }
                }

                foreach ($id in @($held.Keys)) {
                    if (-not $plugged.ContainsKey($id)) {
                        $held.Remove($id)
                        $dirty = $true
                        Write-Log ("unplugged, will attach on next plug {0}" -f $id)
                    }
                }

                if ($dirty) { Save-WatchState }
            }
        } catch {
            Write-Log ("loop error: {0}" -f $_.Exception.Message)
        }

        if ($Once) { break }
        Start-Sleep -Seconds $IntervalSec
    }
} finally {
    if ($locked) {
        try { $mutex.ReleaseMutex() } catch {}
        $mutex.Dispose()
    }
}
