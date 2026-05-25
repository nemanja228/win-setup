#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Post-install automation for Windows 11 on ASUS Zenbook S16 UM5606WA.
    Idempotent. Safe to run multiple times (e.g. after major Windows feature updates).

.DESCRIPTION
    Pipeline:
      1. Pre-flight checks (admin, OS build, network)
      2. System restore point
      3. Win11Debloat (Raphire) — apps + telemetry + UI tweaks
      4. O&O ShutUp10++ with saved config
      5. Registry tweaks (tweaks.reg)
      6. winget bulk install (apps.json)
      7. Power plan (restore High Performance, disable USB selective suspend)
      8. Defender exclusions for dev/audio folders
      9. Optional Windows features (Hyper-V, WSL, VirtualMachinePlatform, Sandbox)
     10. WSL2 + .wslconfig
     11. Manual TODO checklist on Desktop

    Every step logs to console (colour-coded) AND to a timestamped file under
    %USERPROFILE%\win-setup-logs\bootstrap-<timestamp>.log

.PARAMETER SkipApps
    Don't run winget import.

.PARAMETER SkipWSL
    Don't install WSL or write .wslconfig.

.PARAMETER DryRun
    Log what would happen without making changes.

.EXAMPLE
    .\bootstrap.ps1

.EXAMPLE
    .\bootstrap.ps1 -DryRun

.EXAMPLE
    .\bootstrap.ps1 -SkipApps -SkipWSL
#>

[CmdletBinding()]
param(
    [switch]$SkipApps,
    [switch]$SkipWSL,
    [switch]$DryRun
)

# =============================================================================
# Resolve script directory (works whether run via path or dot-sourced)
# =============================================================================

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

# =============================================================================
# Logging infrastructure
# =============================================================================

$LogDir = Join-Path $env:USERPROFILE 'win-setup-logs'
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Script:LogFile     = Join-Path $LogDir "bootstrap-$Stamp.log"
$Script:WingetLog   = Join-Path $LogDir "winget-$Stamp.log"
$Script:OosuLog     = Join-Path $LogDir "oosu-$Stamp.log"
$Script:DebloatLog  = Join-Path $LogDir "win11debloat-$Stamp.log"
$Script:Summary     = New-Object System.Collections.Generic.List[object]

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)][AllowEmptyString()][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','STEP','DEBUG','TRACE')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$($Level.PadRight(7))] $Message"
    $color = switch ($Level) {
        'INFO'    { 'Gray' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
        'STEP'    { 'Cyan' }
        'DEBUG'   { 'DarkGray' }
        'TRACE'   { 'DarkGray' }
        default   { 'White' }
    }
    Write-Host $line -ForegroundColor $color
    try {
        Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host "  [log write failed: $($_.Exception.Message)]" -ForegroundColor Red
    }
}

function Invoke-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [switch]$ContinueOnError,
        [switch]$SkipOnDryRun
    )
    Write-Log -Level STEP -Message ""
    Write-Log -Level STEP -Message "==> $Name"
    $start = Get-Date
    $result = [PSCustomObject]@{
        Name        = $Name
        Success     = $false
        DurationSec = 0.0
        Error       = $null
        Skipped     = $false
    }

    try {
        if ($DryRun -and $SkipOnDryRun) {
            Write-Log -Level WARN -Message "  [DRY-RUN] skipping execution"
            $result.Skipped = $true
            $result.Success = $true
        } else {
            # Capture all output streams and forward to log
            & $Action 2>&1 | ForEach-Object {
                if ($null -eq $_) { return }
                $text = $_.ToString().TrimEnd()
                if ([string]::IsNullOrWhiteSpace($text)) { return }
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    Write-Log -Level WARN -Message "  ! $text"
                }
                elseif ($_ -is [System.Management.Automation.WarningRecord]) {
                    Write-Log -Level WARN -Message "  ? $text"
                }
                else {
                    Write-Log -Level TRACE -Message "    $text"
                }
            }
            $result.Success = $true
        }
    } catch {
        $result.Error = $_.Exception.Message
        Write-Log -Level ERROR -Message "  Exception: $($_.Exception.Message)"
        if ($_.ScriptStackTrace) {
            foreach ($l in ($_.ScriptStackTrace -split "`n")) {
                Write-Log -Level ERROR -Message "    $l"
            }
        }
        if (-not $ContinueOnError) {
            $result.DurationSec = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
            $Script:Summary.Add($result)
            Show-Summary
            throw
        }
    }

    $result.DurationSec = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    if ($result.Skipped) {
        Write-Log -Level WARN -Message "  SKIPPED ($($result.DurationSec)s)"
    } elseif ($result.Success) {
        Write-Log -Level SUCCESS -Message "  OK ($($result.DurationSec)s)"
    } else {
        Write-Log -Level ERROR -Message "  FAILED ($($result.DurationSec)s)"
    }
    $Script:Summary.Add($result)
}

function Show-Summary {
    Write-Log -Level STEP -Message ""
    Write-Log -Level STEP -Message "=================== SUMMARY ==================="
    $ok      = ($Script:Summary | Where-Object { $_.Success -and -not $_.Skipped }).Count
    $skipped = ($Script:Summary | Where-Object { $_.Skipped }).Count
    $fail    = ($Script:Summary | Where-Object { -not $_.Success }).Count
    Write-Log -Level SUCCESS -Message "Succeeded: $ok"
    Write-Log -Level WARN    -Message "Skipped:   $skipped"
    Write-Log -Level $(if ($fail) { 'ERROR' } else { 'INFO' }) -Message "Failed:    $fail"
    Write-Log -Level INFO    -Message ""
    foreach ($s in $Script:Summary) {
        $marker  = if ($s.Skipped) { '~' } elseif ($s.Success) { 'OK' } else { 'X ' }
        $lvl     = if ($s.Skipped) { 'WARN' } elseif ($s.Success) { 'INFO' } else { 'ERROR' }
        $extra   = if ($s.Error) { "  -- $($s.Error)" } else { '' }
        $line    = ("  [{0,-2}] {1}  ({2}s){3}" -f $marker, $s.Name, $s.DurationSec, $extra)
        Write-Log -Level $lvl -Message $line
    }
    Write-Log -Level STEP -Message "==============================================="
    Write-Log -Level INFO -Message ""
    Write-Log -Level INFO -Message "Full log:        $Script:LogFile"
    Write-Log -Level INFO -Message "Winget log:      $Script:WingetLog"
    Write-Log -Level INFO -Message "OOSU10 log:      $Script:OosuLog"
    Write-Log -Level INFO -Message "Win11Debloat log: $Script:DebloatLog"
}

# =============================================================================
# Header
# =============================================================================

Write-Log -Level STEP -Message "==============================================="
Write-Log -Level STEP -Message " Windows 11 Post-Install Bootstrap"
Write-Log -Level STEP -Message "==============================================="
Write-Log -Level INFO -Message "Host:    $env:COMPUTERNAME"
Write-Log -Level INFO -Message "User:    $env:USERNAME"
Write-Log -Level INFO -Message "Start:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
Write-Log -Level INFO -Message "Script:  $ScriptDir"
Write-Log -Level INFO -Message "Log:     $Script:LogFile"
if ($DryRun)   { Write-Log -Level WARN -Message "MODE:    DRY-RUN — destructive steps will be skipped" }
if ($SkipApps) { Write-Log -Level WARN -Message "FLAG:    -SkipApps set" }
if ($SkipWSL)  { Write-Log -Level WARN -Message "FLAG:    -SkipWSL  set" }
Write-Log -Level STEP -Message "==============================================="

# =============================================================================
# Pre-flight
# =============================================================================

Invoke-Step -Name "Pre-flight: admin check" -Action {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Not running as Administrator."
    }
    Write-Log -Level DEBUG -Message "  Running as Administrator: OK"
}

Invoke-Step -Name "Pre-flight: Windows build" -ContinueOnError -Action {
    $build = [System.Environment]::OSVersion.Version.Build
    $caption = (Get-CimInstance Win32_OperatingSystem).Caption
    Write-Log -Level DEBUG -Message "  $caption (build $build)"
    if ($build -lt 26100) {
        Write-Log -Level WARN -Message "  Build is older than 24H2 (26100). Some features (Recall toggle, AI Hub removal) won't apply."
    }
}

Invoke-Step -Name "Pre-flight: network connectivity" -ContinueOnError -Action {
    $reachable = Test-Connection -ComputerName 'github.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $reachable) {
        $reachable = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue
    }
    if (-not $reachable) {
        throw "No network connectivity to github.com or 1.1.1.1"
    }
    Write-Log -Level DEBUG -Message "  Network OK"
}

Invoke-Step -Name "Pre-flight: set execution policy (process scope)" -Action {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-Log -Level DEBUG -Message "  Policy: Bypass (process)"
}

# =============================================================================
# Restore point
# =============================================================================

Invoke-Step -Name "Create system restore point" -ContinueOnError -SkipOnDryRun -Action {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    # Override the 1440-minute throttle so repeated runs each get a point
    $srKey = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    if (-not (Test-Path $srKey)) { New-Item -Path $srKey -Force | Out-Null }
    New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
    Checkpoint-Computer -Description "win-setup bootstrap $Stamp" -RestorePointType 'MODIFY_SETTINGS'
    Write-Log -Level DEBUG -Message "  Restore point created"
}

# =============================================================================
# Debloat layer 1: Win11Debloat
# =============================================================================

Invoke-Step -Name "Win11Debloat (apps + telemetry + UI tweaks)" -ContinueOnError -SkipOnDryRun -Action {
    $customList = Join-Path $ScriptDir 'CustomAppsList.txt'
    if (Test-Path $customList) {
        Write-Log -Level INFO -Message "  Found custom apps list: $customList"
        $cfgDir = Join-Path $env:TEMP 'Win11Debloat\Config'
        if (-not (Test-Path $cfgDir)) { New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null }
        Copy-Item $customList (Join-Path $cfgDir 'CustomAppsList.txt') -Force
        Write-Log -Level DEBUG -Message "  Copied to $cfgDir\CustomAppsList.txt"
    }

    # Tee output to dedicated log
    $transcript = $Script:DebloatLog
    Start-Transcript -Path $transcript -Append -ErrorAction SilentlyContinue | Out-Null
    try {
        & ([scriptblock]::Create((Invoke-RestMethod -Uri "https://debloat.raphi.re/"))) -RunDefaults -Silent
    } finally {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Log -Level DEBUG -Message "  Win11Debloat transcript: $transcript"
}

# =============================================================================
# Debloat layer 2: O&O ShutUp10++
# =============================================================================

Invoke-Step -Name "O&O ShutUp10++ (apply saved privacy config)" -ContinueOnError -SkipOnDryRun -Action {
    $cfgPath = Join-Path $ScriptDir 'ooshutup10.cfg'
    if (-not (Test-Path $cfgPath)) {
        Write-Log -Level WARN -Message "  ooshutup10.cfg not found in $ScriptDir — skipping."
        Write-Log -Level WARN -Message "  Generate one: download OOSU10.exe interactively, configure, File > Export."
        return
    }
    $oosuExe = Join-Path $env:TEMP 'OOSU10.exe'
    Write-Log -Level DEBUG -Message "  Downloading OOSU10.exe"
    Invoke-WebRequest -Uri 'https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe' -OutFile $oosuExe -UseBasicParsing

    Write-Log -Level DEBUG -Message "  Applying config: $cfgPath"
    $args = @("`"$cfgPath`"", '/quiet')
    $p = Start-Process -FilePath $oosuExe -ArgumentList $args -Wait -PassThru -RedirectStandardOutput $Script:OosuLog -RedirectStandardError "$Script:OosuLog.err" -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "OOSU10 exited with code $($p.ExitCode). See $Script:OosuLog"
    }
    Write-Log -Level DEBUG -Message "  OOSU10 exit code: 0"
}

# =============================================================================
# Registry tweaks
# =============================================================================

Invoke-Step -Name "Apply registry tweaks (tweaks.reg)" -ContinueOnError -SkipOnDryRun -Action {
    $reg = Join-Path $ScriptDir 'tweaks.reg'
    if (-not (Test-Path $reg)) {
        Write-Log -Level WARN -Message "  tweaks.reg not found in $ScriptDir — skipping."
        return
    }
    $regLog = Join-Path $LogDir "reg-import-$Stamp.log"
    $p = Start-Process -FilePath reg.exe -ArgumentList @('import', "`"$reg`"") -Wait -PassThru -NoNewWindow -RedirectStandardOutput $regLog -RedirectStandardError "$regLog.err"
    if ($p.ExitCode -ne 0) {
        throw "reg import exited with code $($p.ExitCode). See $regLog"
    }
    Write-Log -Level DEBUG -Message "  reg import OK ($reg)"
}

# =============================================================================
# Apps via winget
# =============================================================================

if (-not $SkipApps) {
    Invoke-Step -Name "winget: update sources" -ContinueOnError -SkipOnDryRun -Action {
        winget source update
    }

    Invoke-Step -Name "winget: import apps.json" -ContinueOnError -SkipOnDryRun -Action {
        $apps = Join-Path $ScriptDir 'apps.json'
        if (-not (Test-Path $apps)) {
            throw "apps.json not found in $ScriptDir"
        }
        Write-Log -Level DEBUG -Message "  Importing $apps  (output -> $Script:WingetLog)"
        # We want both logging AND visibility — Tee handles both
        & winget import --import-file $apps `
            --accept-package-agreements --accept-source-agreements `
            --ignore-unavailable 2>&1 | Tee-Object -FilePath $Script:WingetLog
    }
} else {
    Write-Log -Level WARN -Message "-SkipApps flag set; winget import skipped"
}

# =============================================================================
# Power plan
# =============================================================================

Invoke-Step -Name "Power: restore High Performance plan" -ContinueOnError -SkipOnDryRun -Action {
    $list = powercfg /list
    if ($list -match 'High performance' -or $list -match 'Ultimate Performance') {
        Write-Log -Level DEBUG -Message "  High Performance plan already present"
    } else {
        powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        Write-Log -Level DEBUG -Message "  High Performance plan duplicated"
    }
}

Invoke-Step -Name "Power: disable USB selective suspend (AC+DC)" -ContinueOnError -SkipOnDryRun -Action {
    # Subgroup 2a737441... = USB settings;  Setting 48e6b7a6... = USB selective suspend
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setactive SCHEME_CURRENT
    Write-Log -Level DEBUG -Message "  USB selective suspend disabled on active plan"
}

# =============================================================================
# Defender exclusions
# =============================================================================

Invoke-Step -Name "Defender: add exclusions for dev/audio folders" -ContinueOnError -SkipOnDryRun -Action {
    $paths = @(
        (Join-Path $env:USERPROFILE 'source'),
        (Join-Path $env:USERPROFILE 'projects'),
        (Join-Path $env:USERPROFILE '.vscode'),
        (Join-Path $env:USERPROFILE '.nuget'),
        (Join-Path $env:USERPROFILE 'Documents\Reaper Media'),
        (Join-Path $env:USERPROFILE 'Documents\REAPER Media'),
        'C:\ProgramData\Audient'
    )
    foreach ($p in $paths) {
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            Write-Log -Level DEBUG -Message "  + $p"
        } catch {
            Write-Log -Level WARN -Message "  ! could not add ${p}: $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# Optional Windows features
# =============================================================================

Invoke-Step -Name "Windows features: Hyper-V, WSL, VMP, Sandbox" -ContinueOnError -SkipOnDryRun -Action {
    $features = @(
        'Microsoft-Hyper-V-All',
        'VirtualMachinePlatform',
        'Microsoft-Windows-Subsystem-Linux',
        'Containers-DisposableClientVM'
    )
    foreach ($f in $features) {
        try {
            $state = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State
            if ($state -eq 'Enabled') {
                Write-Log -Level DEBUG -Message "  = $f (already enabled)"
            } else {
                Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop | Out-Null
                Write-Log -Level DEBUG -Message "  + $f (enabled)"
            }
        } catch {
            Write-Log -Level WARN -Message "  ! $f failed: $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# WSL2
# =============================================================================

if (-not $SkipWSL) {
    Invoke-Step -Name "WSL: update kernel" -ContinueOnError -SkipOnDryRun -Action {
        wsl --update
    }

    Invoke-Step -Name "WSL: install Ubuntu (if missing)" -ContinueOnError -SkipOnDryRun -Action {
        $listed = (wsl --list --quiet 2>$null) -join "`n"
        # WSL outputs UTF-16; normalise null bytes
        $listed = $listed -replace "`0", ''
        if ($listed -match 'Ubuntu') {
            Write-Log -Level DEBUG -Message "  Ubuntu distro already registered"
        } else {
            wsl --install -d Ubuntu --no-launch
            Write-Log -Level DEBUG -Message "  Ubuntu install initiated (will finish on first launch)"
        }
    }

    Invoke-Step -Name "WSL: write .wslconfig" -SkipOnDryRun -Action {
        $wslConfig = @'
# Managed by win-setup bootstrap.ps1
[wsl2]
memory=16GB
processors=8
swap=4GB
localhostForwarding=true
nestedVirtualization=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
'@
        $path = Join-Path $env:USERPROFILE '.wslconfig'
        # Back up existing if different
        if (Test-Path $path) {
            $existing = Get-Content $path -Raw -ErrorAction SilentlyContinue
            if ($existing -ne $wslConfig) {
                $backup = "$path.bak-$Stamp"
                Copy-Item $path $backup -Force
                Write-Log -Level DEBUG -Message "  Existing .wslconfig backed up to $backup"
            } else {
                Write-Log -Level DEBUG -Message "  .wslconfig already up to date"
                return
            }
        }
        Set-Content -Path $path -Value $wslConfig -Encoding ASCII -Force
        Write-Log -Level DEBUG -Message "  Wrote $path"
    }
} else {
    Write-Log -Level WARN -Message "-SkipWSL flag set; WSL steps skipped"
}

# =============================================================================
# Manual checklist
# =============================================================================

Invoke-Step -Name "Generate post-install TODO checklist on Desktop" -Action {
    $todo = @"
================================================================
MANUAL POST-INSTALL CHECKLIST  ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))
================================================================

REBOOT first — Windows features (Hyper-V, WSL, Sandbox) need it.

[ ] Reboot
[ ] Launch Ubuntu once:  wsl -d Ubuntu     # set username + password
[ ] Change local Windows account password (was set to a placeholder by autounattend)
[ ] Sign into MyASUS
       -> Battery Care = Balanced (80%)
       -> Fan Mode = Standard
       -> Function Key Lock = F1-F12 default
[ ] Audient EVO 4:
       -> Download driver: https://audient.com/products/audio-interfaces/evo-4/downloads/
       -> Plug interface DIRECTLY into the laptop, not through the HP G4 dock
       -> Set as default Windows audio device when connected
       -> In DAW: choose 'Audient EVO ASIO', not WASAPI / ASIO4ALL
[ ] BIOS:
       -> Check current vs latest:  https://www.asus.com/laptops/for-home/zenbook/asus-zenbook-s-16-um5606/helpdesk_bios?model2Name=UM5606WA
       -> Confirm SVM (virtualisation) = Enabled
       -> Confirm Secure Boot = Enabled
       -> Confirm fTPM = Enabled
[ ] Office: activate via your MS account in Word > File > Account
[ ] Obsidian: sign into Sync (or set up Syncthing for your vault)
[ ] Git:  git config --global user.name "Your Name"
          git config --global user.email "you@example.com"
[ ] Visual Studio: install workloads (.NET desktop, ASP.NET, Azure dev)
[ ] LatencyMon: run 15 min idle, audit any DPC outliers
[ ] OLED preservation:
       -> Settings > Personalization > Colors = Dark
       -> Taskbar settings > Automatically hide
       -> MyASUS > Device settings > enable Pixel Refresh / Pixel Shift
       -> Wallpaper slideshow every 30 min

================================================================
Bootstrap log:  $Script:LogFile
Full log dir:   $LogDir
================================================================
"@
    $todoPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TODO-post-install.txt'
    Set-Content -Path $todoPath -Value $todo -Encoding UTF8 -Force
    Write-Log -Level INFO -Message "  Wrote $todoPath"
}

# =============================================================================
# Wrap up
# =============================================================================

Show-Summary

$failed = ($Script:Summary | Where-Object { -not $_.Success }).Count
Write-Log -Level INFO -Message ""
if ($failed -eq 0) {
    Write-Log -Level SUCCESS -Message "All steps OK. Reboot recommended."
    exit 0
} else {
    Write-Log -Level WARN -Message "$failed step(s) failed. Review the logs above."
    exit 1
}
