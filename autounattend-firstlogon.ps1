<#
.SYNOPSIS
    First-logon bootstrap. Embed this in Schneegans' autounattend.xml as a
    "PowerShell script that runs on first logon (user context)".

.DESCRIPTION
    Runs once, after Windows Setup completes and the first user logs in.
    Responsibilities:
      1. Wait for network
      2. Download the win-setup repo files (bootstrap.ps1, apps.json, etc.)
      3. Launch the main bootstrap.ps1 elevated

    Logs to %USERPROFILE%\Desktop\firstlogon.log so you can see what happened
    even if the subsequent bootstrap fails or you close the window.

.NOTES
    Replace $RepoRawBase with your own (private GitHub repo + Personal Access
    Token in URL, gist raw, internal share, whatever).
    If you don't want a remote dependency, put the files on the install USB
    and copy them out via a SetupComplete.cmd step instead.
#>

# ---- CONFIG -----------------------------------------------------------------

$RepoRawBase = 'https://raw.githubusercontent.com/YOUR-USER/win-setup/main'
$Files = @(
    'bootstrap.ps1',
    'apps.json',
    'tweaks.reg',
    'ooshutup10.cfg',
    'CustomAppsList.txt'
)
$WorkDir = Join-Path $env:USERPROFILE 'win-setup'
$LogFile = Join-Path ([Environment]::GetFolderPath('Desktop')) 'firstlogon.log'
$NetworkTimeoutMin = 5

# ---- LOGGING ----------------------------------------------------------------

function Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

Log "================ FirstLogon bootstrap starting ================"
Log "Host: $env:COMPUTERNAME  User: $env:USERNAME"
Log "Log:  $LogFile"

# ---- NETWORK WAIT -----------------------------------------------------------

Log "Waiting for network (timeout ${NetworkTimeoutMin}min)..."
$deadline = (Get-Date).AddMinutes($NetworkTimeoutMin)
$online = $false
while ((Get-Date) -lt $deadline) {
    if (Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        $online = $true
        break
    }
    Start-Sleep -Seconds 3
}
if (-not $online) {
    Log "Network never came up. Aborting." 'ERROR'
    exit 1
}
Log "Network up."

# ---- WORK DIR ---------------------------------------------------------------

if (-not (Test-Path $WorkDir)) {
    New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
}
Log "Work dir: $WorkDir"

# ---- DOWNLOAD ---------------------------------------------------------------

foreach ($f in $Files) {
    $url = "$RepoRawBase/$f"
    $dest = Join-Path $WorkDir $f
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Log "  + $f"
    } catch {
        Log "  ! $f  ($($_.Exception.Message))" 'WARN'
    }
}

# ---- LAUNCH MAIN BOOTSTRAP --------------------------------------------------

$bootstrap = Join-Path $WorkDir 'bootstrap.ps1'
if (-not (Test-Path $bootstrap)) {
    Log "bootstrap.ps1 missing — cannot continue. Look at $WorkDir." 'ERROR'
    exit 1
}

Log "Launching bootstrap.ps1 (elevated window will open)..."
Start-Process powershell -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', "`"$bootstrap`""
) -Verb RunAs

Log "================ FirstLogon bootstrap done ================"
