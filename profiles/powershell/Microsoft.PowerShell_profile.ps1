using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# =============================================================================
# PowerShell profile — managed by win-setup
#
# Installed by scripts/Install-Profiles.ps1 to $PROFILE.CurrentUserAllHosts.
# Generic / no personal identifiers — fork-friendly.
#
# Sections:
#   - Module loads (PSReadLine + lazy Terminal-Icons)
#   - Oh-My-Posh prompt init
#   - Argument completers (winget, dotnet, git — branch + subcommand)
#   - PSReadLine keybindings (history search, smart edit, prediction)
#   - z (directory jumper)
#   - Add-Path helper
#   - Terminal transparency trigger (sends Ctrl+Shift+] to active AHK script)
# =============================================================================

# ---- Module loads -----------------------------------------------------------

if ($host.Name -eq 'ConsoleHost') {
    Import-Module PSReadLine
}

# Lazy-load Terminal-Icons: cost moves from every shell start to first `ls`.
$script:__tiLoaded = $false
function global:ls {
    if (-not $script:__tiLoaded) {
        Import-Module Terminal-Icons -ErrorAction SilentlyContinue
        $script:__tiLoaded = $true
    }
    Get-ChildItem @args
}

# ---- Oh-My-Posh -------------------------------------------------------------
# Theme file is deployed by scripts/Install-Profiles.ps1.
# To swap themes: change the filename below, or test built-ins like
# 1_shell / amro / avit / darkblood / emodipt-extend / kali / peru / nordtron.

oh-my-posh init pwsh --config "$env:LocalAppData\oh-my-posh\themes\winsetup.omp.json" | Invoke-Expression

# ---- Argument completers ----------------------------------------------------

# winget
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    [Console]::InputEncoding  = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
    $Local:word = $wordToComplete.Replace('"', '""')
    $Local:ast  = $commandAst.ToString().Replace('"', '""')
    winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# dotnet
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# git — replacement for posh-git's branch + subcommand tab completion. ~5ms cost
# at registration, ~30ms per tab press (vs posh-git's ~700ms import on every
# shell start). Covers the cases that matter: subcommand names + branch names
# (local + remote) for the subcommands that take a branch.
Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokens = @($commandAst.CommandElements)
    # Position 0 is "git" itself. Position 1 is the subcommand.
    if ($tokens.Count -lt 2 -or ($tokens.Count -eq 2 -and $wordToComplete -eq $tokens[1].Value)) {
        # Complete subcommand
        $subcommands = @(
            'add','am','archive','bisect','blame','branch','checkout','cherry-pick','clean','clone',
            'commit','config','describe','diff','fetch','format-patch','grep','init','log','merge',
            'mv','pull','push','rebase','reflog','remote','reset','restore','revert','rm','show',
            'stash','status','submodule','switch','tag','worktree'
        )
        $subcommands |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        return
    }

    $subcommand = $tokens[1].Value

    # Subcommands where the next positional arg is (usually) a branch/ref name.
    $branchSubs = @('checkout','switch','merge','rebase','branch','log','show','diff','reset','pull','push','cherry-pick','revert')
    if ($branchSubs -contains $subcommand) {
        $local  = & git branch --list --format='%(refname:short)' 2>$null
        $remote = & git branch -r --list --format='%(refname:short)' 2>$null | Where-Object { $_ -and $_ -notmatch '->' }
        @($local; $remote) |
            Where-Object { $_ -and ($_ -like "$wordToComplete*") } |
            Sort-Object -Unique |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# ---- PSReadLine: history search via Up/Down -----------------------------------
# Type a prefix, then Up/Down to cycle matching history. The killer feature.
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# F7: full history as Out-GridView. Filterable, multi-select, inserts on accept.
Set-PSReadLineKeyHandler -Key F7 `
                         -BriefDescription History `
                         -LongDescription 'Show command history' `
                         -ScriptBlock {
    $pattern = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$null)
    if ($pattern) { $pattern = [regex]::Escape($pattern) }

    $history = [System.Collections.ArrayList]@(
        $last = ''
        $lines = ''
        foreach ($line in [System.IO.File]::ReadLines((Get-PSReadLineOption).HistorySavePath)) {
            if ($line.EndsWith('`')) {
                $line = $line.Substring(0, $line.Length - 1)
                $lines = if ($lines) { "$lines`n$line" } else { $line }
                continue
            }
            if ($lines) { $line = "$lines`n$line"; $lines = '' }
            if (($line -cne $last) -and (!$pattern -or ($line -match $pattern))) {
                $last = $line
                $line
            }
        }
    )
    $history.Reverse()

    $command = $history | Out-GridView -Title History -PassThru
    if ($command) {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($command -join "`n"))
    }
}

# ---- PSReadLine: smart insert/delete for quotes, parens, braces --------------

Set-PSReadLineKeyHandler -Key '"',"'" `
                         -BriefDescription SmartInsertQuote `
                         -LongDescription "Insert paired quotes if not already on a quote" `
                         -ScriptBlock {
    param($key, $arg)
    $quote = $key.KeyChar

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # If text is selected, just quote it without any smarts.
    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    $ast = $null
    $tokens = $null
    $parseErrors = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)

    function FindToken {
        param($tokens, $cursor)
        foreach ($token in $tokens) {
            if ($cursor -lt $token.Extent.StartOffset) { continue }
            if ($cursor -lt $token.Extent.EndOffset) {
                $result = $token
                $token = $token -as [StringExpandableToken]
                if ($token) {
                    $nested = FindToken $token.NestedTokens $cursor
                    if ($nested) { $result = $nested }
                }
                return $result
            }
        }
        return $null
    }

    $token = FindToken $tokens $cursor

    # If we're on or inside a quoted string token, behave smarter.
    if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
        if ($token.Extent.StartOffset -eq $cursor) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
        if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
    }

    if ($null -eq $token -or
        $token.Kind -eq [TokenKind]::RParen -or $token.Kind -eq [TokenKind]::RCurly -or $token.Kind -eq [TokenKind]::RBracket) {
        if ($line[0..$cursor].Where{$_ -eq $quote}.Count % 2 -eq 1) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
        return
    }

    if ($token.Extent.StartOffset -eq $cursor) {
        if ($token.Kind -eq [TokenKind]::Generic -or $token.Kind -eq [TokenKind]::Identifier -or
            $token.Kind -eq [TokenKind]::Variable -or $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
            $end = $token.Extent.EndOffset
            $len = $end - $cursor
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $quote + $line.SubString($cursor, $len) + $quote)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
            return
        }
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
}

Set-PSReadLineKeyHandler -Key '(','{','[' `
                         -BriefDescription InsertPairedBraces `
                         -LongDescription "Insert matching braces" `
                         -ScriptBlock {
    param($key, $arg)
    $closeChar = switch ($key.KeyChar) {
        '(' { [char]')'; break }
        '{' { [char]'}'; break }
        '[' { [char]']'; break }
    }
    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key ')',']','}' `
                         -BriefDescription SmartCloseBraces `
                         -LongDescription "Insert closing brace or skip" `
                         -ScriptBlock {
    param($key, $arg)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($line[$cursor] -eq $key.KeyChar) {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
    }
}

Set-PSReadLineKeyHandler -Key Backspace `
                         -BriefDescription SmartBackspace `
                         -LongDescription "Delete previous character or matching quotes/parens/braces" `
                         -ScriptBlock {
    param($key, $arg)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($cursor -gt 0) {
        $toMatch = $null
        if ($cursor -lt $line.Length) {
            switch ($line[$cursor]) {
                '"' { $toMatch = '"'; break }
                "'" { $toMatch = "'"; break }
                ')' { $toMatch = '('; break }
                ']' { $toMatch = '['; break }
                '}' { $toMatch = '{'; break }
            }
        }
        if ($null -ne $toMatch -and $line[$cursor-1] -eq $toMatch) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
        }
    }
}

# ---- PSReadLine: utility keys ----------------------------------------------

# Alt+W: save current line in history without executing (for "I'll do this in a sec" commands)
Set-PSReadLineKeyHandler -Key Alt+w `
                         -BriefDescription SaveInHistory `
                         -LongDescription "Save current line in history but do not execute" `
                         -ScriptBlock {
    param($key, $arg)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
}

# Ctrl+V: paste clipboard text as a here-string @'...'@ (preserves quotes, newlines)
Set-PSReadLineKeyHandler -Key Ctrl+V `
                         -BriefDescription PasteAsHereString `
                         -LongDescription "Paste the clipboard text as a here string" `
                         -ScriptBlock {
    param($key, $arg)
    Add-Type -Assembly PresentationCore
    if ([System.Windows.Clipboard]::ContainsText()) {
        $text = ([System.Windows.Clipboard]::GetText() -replace "\p{Zs}*`r?`n","`n").TrimEnd()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@'`n$text`n'@")
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
    }
}

# RightArrow: when at end of line, accept next predicted word (vs whole suggestion via ForwardChar)
Set-PSReadLineKeyHandler -Key RightArrow `
                         -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
                         -LongDescription "At end of line, accept next predicted word; otherwise move cursor right" `
                         -ScriptBlock {
    param($key, $arg)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
    }
}

# Auto-correct 'git cmt' -> 'git commit' on submit.
Set-PSReadLineOption -CommandValidationHandler {
    param([CommandAst]$CommandAst)
    switch ($CommandAst.GetCommandName()) {
        'git' {
            $gitCmd = $CommandAst.CommandElements[1].Extent
            switch ($gitCmd.Text) {
                'cmt' {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $gitCmd.StartOffset, $gitCmd.EndOffset - $gitCmd.StartOffset, 'commit')
                }
            }
        }
    }
}

# PSReadLine prediction settings.
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows

# ---- z (directory jumper) ---------------------------------------------------
# Install once: Install-Module z -Scope CurrentUser
Import-Module z -ErrorAction SilentlyContinue

# ---- Helpers ----------------------------------------------------------------

function Add-Path($Path) {
    $current = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    [Environment]::SetEnvironmentVariable('Path', "$current$([IO.Path]::PathSeparator)$Path", 'Machine')
}

# ---- Terminal transparency trigger ------------------------------------------
# WtTransparent.ahk binds Ctrl+Shift+] to toggle window transparency. Sending
# the chord on shell start opens every new PowerShell window already transparent.
# Drop this line if it interferes with another app's Ctrl+Shift+] binding.
$wshell = New-Object -ComObject wscript.shell
$wshell.SendKeys("^+]")
