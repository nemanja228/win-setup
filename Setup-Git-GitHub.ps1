<#
.SYNOPSIS
Automates Git installation, overwrites global configuration via Gist, generates SSH profiles, and sets global identity.

.EXAMPLE
.\Setup-DevEnvironment.ps1 -SshEmail "me@example.com" -KeyAlias "id_ed25519_personal" -HostAlias "github.com-personal" -GistUrl "https://gist.githubusercontent.com/..." -GitUserName "John Doe" -GitUserEmail "john@example.com"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, HelpMessage="Your SSH key email address")]
    [string]$SshEmail,

    [Parameter(Mandatory=$true, HelpMessage="Name of the SSH key file (e.g., id_ed25519_personal)")]
    [string]$KeyAlias,

    [Parameter(Mandatory=$true, HelpMessage="Host alias for SSH config (e.g., github.com-personal)")]
    [string]$HostAlias,

    [Parameter(Mandatory=$true, HelpMessage="The URL of your public Gist containing the Git config")]
    [string]$GistUrl,

    [Parameter(Mandatory=$true, HelpMessage="Your full name for Git commits")]
    [string]$GitUserName,

    [Parameter(Mandatory=$true, HelpMessage="Your primary email for Git commits")]
    [string]$GitUserEmail
)

# ==============================================================================
# 1. REUSABLE SSH FUNCTION
# ==============================================================================
function New-SshProfile {
    param (
        [string]$Email,
        [string]$KeyName,
        [string]$HostAlias,
        [string]$HostName = "github.com",
        [string]$User = "git"
    )

    $sshDir = Join-Path $HOME ".ssh"
    $configPath = Join-Path $sshDir "config"
    $keyPath = Join-Path $sshDir $KeyName
    $pubKeyPath = "$keyPath.pub"

    if (-not (Test-Path $sshDir)) {
        Write-Host "Creating .ssh directory at $sshDir..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    if (-not (Test-Path $configPath)) {
        Write-Host "Creating SSH config file at $configPath..." -ForegroundColor Cyan
        New-Item -ItemType File -Path $configPath -Force | Out-Null
    }

    if (-not (Test-Path $keyPath)) {
        Write-Host "Generating new ed25519 SSH key: $KeyName..." -ForegroundColor Cyan
        ssh-keygen -t ed25519 -C $Email -f $keyPath -N '""'
    } else {
        Write-Host "SSH key '$KeyName' already exists. Skipping generation." -ForegroundColor Yellow
    }

    $configContent = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
    if ($configContent -match "Host $HostAlias`b") {
        Write-Host "Host alias '$HostAlias' already exists in SSH config. Skipping." -ForegroundColor Yellow
    } else {
        Write-Host "Adding '$HostAlias' to SSH config..." -ForegroundColor Cyan
        $newConfigEntry = @"

Host $HostAlias
    HostName $HostName
    User $User
    IdentityFile $keyPath
    IdentitiesOnly yes
"@
        Add-Content -Path $configPath -Value $newConfigEntry
        Write-Host "Successfully added SSH profile for $HostAlias." -ForegroundColor Green
    }

    if (Test-Path $pubKeyPath) {
        Write-Host "`nCopying public key to clipboard..." -ForegroundColor Cyan
        Get-Content $pubKeyPath | Set-Clipboard
        Write-Host "SUCCESS! Your public key is in your clipboard." -ForegroundColor Green

        if ($HostName -match "github") {
            Write-Host "Opening GitHub SSH settings in your default browser..." -ForegroundColor Cyan
            Start-Process "https://github.com/settings/ssh/new"
            Write-Host "Please paste (Ctrl+V) the key into the 'Key' field and save." -ForegroundColor Yellow
        }
    }
}

# ==============================================================================
# 2. SELF-ELEVATION CHECK
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Script is not running as Administrator. Elevating and passing parameters..." -ForegroundColor Yellow
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -SshEmail `"$SshEmail`" -KeyAlias `"$KeyAlias`" -HostAlias `"$HostAlias`" -GistUrl `"$GistUrl`" -GitUserName `"$GitUserName`" -GitUserEmail `"$GitUserEmail`""
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    exit
}

# ==============================================================================
# 3. WINGET GIT INSTALL/UPDATE
# ==============================================================================
Write-Host "`n--- Checking Git Installation ---" -ForegroundColor Cyan
$gitInstalled = Get-Command git -ErrorAction SilentlyContinue

if (-not $gitInstalled) {
    Write-Host "Git is not installed. Installing via winget..."
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements --silent
} else {
    Write-Host "Git is already installed. Attempting update via winget..."
    winget upgrade --id Git.Git -e --accept-source-agreements --accept-package-agreements --silent
}

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# ==============================================================================
# 4. OVERWRITE GLOBAL GIT CONFIG VIA GIST
# ==============================================================================
Write-Host "`n--- Setting up Global Git Config via Gist ---" -ForegroundColor Cyan

if ($GistUrl -match "^https://gist\.github\.com/(.*)$") {
    if ($GistUrl -notmatch "/raw$") {
        $GistUrl = "$GistUrl/raw"
        Write-Host "Auto-corrected Gist URL to raw format." -ForegroundColor Cyan
    }
}

$globalGitConfigPath = Join-Path $HOME ".gitconfig"

if (Test-Path $globalGitConfigPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$globalGitConfigPath.bak_$timestamp"
    Write-Host "Existing .gitconfig found. Creating backup at: $backupPath" -ForegroundColor Yellow
    Copy-Item -Path $globalGitConfigPath -Destination $backupPath -Force
}

Write-Host "Downloading Git config from Gist and overwriting local config..."
try {
    Invoke-RestMethod -Uri $GistUrl -OutFile $globalGitConfigPath
    Write-Host "Successfully applied Gist to $globalGitConfigPath" -ForegroundColor Green
}
catch {
    Write-Host "Failed to download Gist. Check the URL and your internet connection." -ForegroundColor Red
}

# ==============================================================================
# 5. SET GLOBAL GIT IDENTITY
# ==============================================================================
Write-Host "`n--- Setting Global Git Identity ---" -ForegroundColor Cyan
git config --global user.name $GitUserName
git config --global user.email $GitUserEmail
Write-Host "Global identity set to: $GitUserName <$GitUserEmail>" -ForegroundColor Green

# ==============================================================================
# 6. EXECUTE SSH PROFILE GENERATION
# ==============================================================================
Write-Host "`n--- Setting up Initial SSH Profile ---" -ForegroundColor Cyan

New-SshProfile -Email $SshEmail -KeyName $KeyAlias -HostAlias $HostAlias

Write-Host "`nSetup complete!" -ForegroundColor Green
Pause