<#
.SYNOPSIS
    Install Claude Code on Windows. Default method is Anthropic's official PowerShell installer.

.DESCRIPTION
    Two install methods supported:

      Native (default) — `irm https://claude.ai/install.ps1 | iex`. Auto-updates
                          in the background, latest version, no admin needed.
                          This is what Anthropic's docs recommend.

      Winget          — `winget install --id Anthropic.ClaudeCode`. Doesn't
                          auto-update (you upgrade via winget upgrade). Useful
                          if you manage everything via winget.

    After install, the script:
      1. Locates the `claude` binary.
      2. Ensures its directory is on the user PATH (via snippets/Add-ToPath.ps1).
      3. Smoke-tests `claude --version` from a no-profile shell.

    No admin elevation required — Claude Code installs to user-level
    (%LocalAppData%\Programs\claude or similar).

.PARAMETER Method
    'Native' (default) or 'Winget'.

.PARAMETER Force
    Reinstall even if `claude` is already on PATH.

.EXAMPLE
    .\Install-ClaudeCode.ps1
    # Native installer, skips if claude already on PATH

.EXAMPLE
    .\Install-ClaudeCode.ps1 -Method Winget

.EXAMPLE
    .\Install-ClaudeCode.ps1 -Force
    # Reinstall via native installer regardless
#>
[CmdletBinding()]
param(
    [ValidateSet('Native','Winget')]
    [string]$Method = 'Native',

    [switch]$Force
)

# =============================================================================
# Module + snippet imports
# =============================================================================

$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path -Parent $scriptDir
$modulePath = Join-Path $repoRoot 'lib\WinSetup'

if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    $initLog = Initialize-Logging -LogPrefix 'install-claude'
    $useModuleLog = $true
} else {
    Write-Warning "WinSetup module not found at $modulePath; falling back to plain Write-Host output."
    $useModuleLog = $false
}

function Say {
    param([string]$Level, [string]$Message)
    if ($useModuleLog) {
        Write-Log -Level $Level -Message $Message
    } else {
        $color = switch ($Level) {
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            'SUCCESS' { 'Green' }
            'STEP'    { 'Cyan' }
            default   { 'Gray' }
        }
        Write-Host $Message -ForegroundColor $color
    }
}

# =============================================================================
# Detect existing install
# =============================================================================

Say -Level STEP -Message "==> Install Claude Code (method: $Method)"

$existing = Get-Command claude -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
    $version = (& claude --version 2>$null) -join ' '
    Say -Level SUCCESS -Message "  claude already on PATH at: $($existing.Source)"
    Say -Level INFO    -Message "  Version: $version"
    Say -Level INFO    -Message "  Use -Force to reinstall."
    return
}

if ($existing) {
    Say -Level WARN -Message "  -Force: reinstalling over existing claude at $($existing.Source)"
}

# =============================================================================
# Install
# =============================================================================

switch ($Method) {
    'Native' {
        Say -Level INFO -Message "  Running official Anthropic installer: irm https://claude.ai/install.ps1 | iex"
        try {
            $installer = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1'
            Invoke-Expression $installer
        } catch {
            Say -Level ERROR -Message "  Installer failed: $($_.Exception.Message)"
            throw
        }
    }
    'Winget' {
        Say -Level INFO -Message "  winget install --id Anthropic.ClaudeCode"
        & winget install --id Anthropic.ClaudeCode `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget install exited with code $LASTEXITCODE"
        }
    }
}

# =============================================================================
# Locate binary, add to PATH if needed
# =============================================================================

# Refresh process PATH so Get-Command sees the new install location.
$env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
    Say -Level WARN -Message "  Install ran but `claude` is not on PATH. Common install locations to check:"
    Say -Level WARN -Message "    %LocalAppData%\Programs\claude"
    Say -Level WARN -Message "    %LocalAppData%\Programs\anthropic"
    throw "Could not locate claude binary after install."
}

$claudeDir = Split-Path -Parent $claude.Source
Say -Level SUCCESS -Message "  claude installed at: $($claude.Source)"

# Check user PATH for the install dir.
$userPath = ([Environment]::GetEnvironmentVariable('Path','User') -split ';' | Where-Object { $_ })
$onUserPath = $userPath | Where-Object { $_.TrimEnd('\').Equals($claudeDir, [StringComparison]::OrdinalIgnoreCase) }

if (-not $onUserPath) {
    Say -Level INFO -Message "  Install dir not on user PATH yet; adding via snippets/Add-ToPath.ps1"
    $addToPath = Join-Path $repoRoot 'snippets\Add-ToPath.ps1'
    if (-not (Test-Path $addToPath)) {
        throw "snippets/Add-ToPath.ps1 not found at $addToPath — repo layout broken."
    }
    & $addToPath -Path $claudeDir -Scope User
} else {
    Say -Level DEBUG -Message "  Install dir already on user PATH — no PATH change needed."
}

# =============================================================================
# Smoke test
# =============================================================================

Say -Level STEP -Message "==> Smoke test: claude --version (clean shell)"
$version = & pwsh -NoProfile -Command 'claude --version' 2>&1
if ($LASTEXITCODE -ne 0) {
    Say -Level ERROR -Message "  claude --version failed: $version"
    throw "Smoke test failed."
}
Say -Level SUCCESS -Message "  $version"

if ($useModuleLog) { Show-Summary }
Say -Level SUCCESS -Message "Install-ClaudeCode complete."
