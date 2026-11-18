# Pen notes: from the pen to Obsidian notes, in one double-click.
#
# Asks first: 1 = load the pen notes (Enter), 2 = integrate my corrections.
#
# Choice 1:
#   1. calendar session checked (only if the config has agenda.session_check); expired -> agenda.login
#   2. stylo-neo sync (never --erase); stops if the pen is unreachable or nothing is new
#   3. locked-down `claude -p`: conversion with the pen-notes skill, no question, writing in the vault only
#   4. summary shown and appended to the conversion log in the vault
# Choice 2 (no pen, no sign-in): the same locked-down `claude -p` reads the notes corrected in Obsidian
#   (diff with the converter's version kept outside the vault), settles the doubts, completes glossary and
#   tags, never rewriting the user's text.
#
# Launched by the desktop shortcut (install-shortcut.ps1). The pen password, if asked, is typed here, at the
# password prompt of stylo-neo.

param(
    [ValidateSet('', '1', '2')]
    [string]$Choice,               # 1 = load the pen, 2 = integrate my corrections (asked otherwise)
    [string]$Config,               # configuration file (otherwise STYLO_NEO_CONFIG, config.toml, %APPDATA%)
    [switch]$NoSync,               # convert what is already pending, without touching the pen
    [string]$Prompt                # tests: replaces the instruction sent to Claude
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'
if ($Config) { $env:STYLO_NEO_CONFIG = (Resolve-Path $Config).Path }

$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Skill = Join-Path $Repo '.claude\skills\pen-notes'
$Tool  = Join-Path $Skill 'pen_tool.py'

function Step($n, $text) { Write-Host ""; Write-Host "[$n] $text" -ForegroundColor Cyan }
function Done($message, $colour = 'Yellow') {
    Write-Host ""; Write-Host $message -ForegroundColor $colour
    Write-Host ""; Read-Host "Press Enter to close" | Out-Null
    exit
}
function Posix($path) { ($path -replace '\\', '/') }

$host.UI.RawUI.WindowTitle = 'Pen notes'
$cfgText = python $Tool config | Out-String
if ($LASTEXITCODE -ne 0) { Done "Configuration error (see above). Copy config.example.toml to config.toml and set vault.path." 'Red' }
$cfg   = $cfgText | ConvertFrom-Json
$Vault = $cfg.vault
$Exe   = $cfg.exe
$Data  = $cfg.data_dir
$Log   = $cfg.paths.log_file
foreach ($p in @($Exe, $Vault)) { if (-not $p -or -not (Test-Path $p)) { Done "Not found: $p" 'Red' } }
$Rotated  = $cfg.rotated_dir
$agendaOn = $cfg.agenda.source -eq 'mcp'

# Locked-down claude -p: file tools limited to the vault, the pen data and the skill; the repository is denied;
# the only command is pen_tool.py; the only MCP tools are the configured calendar tools.
function Invoke-Claude($instruction, $title) {
    New-Item -ItemType Directory -Force $Rotated | Out-Null
    $allowed = @('Read', 'Glob', 'Grep', 'Write', 'Edit', "Bash(python `"$(Posix $Tool)`":*)")
    $mcpArgs = @('--strict-mcp-config')
    if ($agendaOn -and $cfg.agenda.mcp_config) {
        $mcpFile = $cfg.agenda.mcp_config
        if (-not [IO.Path]::IsPathRooted($mcpFile) -and $cfg.config_file) {
            $mcpFile = Join-Path (Split-Path $cfg.config_file) $mcpFile   # relative to the config file
        }
        $mcpArgs += @('--mcp-config', $mcpFile)
        $allowed += @($cfg.agenda.tools)
    }
    $repoRule = "Edit(//$((Posix $Repo) -replace '^([A-Za-z]):', { $_.Groups[1].Value.ToLower() })/**)"
    Push-Location $Vault
    try {
        $text = & claude -p $instruction `
            --restricted --tools 'Read,Write,Edit,Glob,Grep,Bash' --permission-mode dontAsk `
            --add-dir (Posix $Data) (Posix $Skill) (Posix (Join-Path $Repo 'pen')) (Posix $Rotated) `
            --allowedTools @allowed --disallowedTools $repoRule `
            @mcpArgs --no-session-persistence | Out-String
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    Write-Host ""
    Write-Host $text
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
    if (-not (Test-Path $Log)) { "# $([IO.Path]::GetFileNameWithoutExtension($Log))`n" | Set-Content -Encoding utf8 $Log }
    "`n## $stamp — $title`n`n$($text.Trim())`n" | Add-Content -Encoding utf8 $Log
    if ($code -ne 0) { Done "Claude stopped with an error (code $code): see the message above." 'Red' }
}

# Calendar session, checked by the configured command if any. Returns $true when the calendar answers.
function Test-Calendar([switch]$AllowLogin) {
    if (-not $agendaOn) { return $false }
    if (-not $cfg.agenda.session_check) { return $true }
    # Commands run from the configuration file's folder, so they may use relative paths.
    if ($cfg.config_file) { Push-Location (Split-Path $cfg.config_file) }
    try {
        & pwsh -NoProfile -Command $cfg.agenda.session_check | Out-Host
        if ($LASTEXITCODE -eq 2 -and $AllowLogin -and $cfg.agenda.login) {
            Write-Host "Calendar session expired: sign in in the window that opens." -ForegroundColor Yellow
            & pwsh -NoProfile -Command $cfg.agenda.login | Out-Host
            & pwsh -NoProfile -Command $cfg.agenda.session_check | Out-Host
        }
        return ($LASTEXITCODE -eq 0)
    } finally { if ($cfg.config_file) { Pop-Location } }
}

$read  = "Read $(Posix (Join-Path $Skill 'SKILL.md')), $(Posix (Join-Path $Skill 'lessons.md')) and $(Posix (Join-Path $Repo 'pen\lessons.md'))"
$rules = "Only allowed command: python `"$(Posix $Tool)`" <subcommand>. The vault is the current folder. " +
         "Your last message is the summary, in the notes' language ($($cfg.language)), with no question."

# --- choice -------------------------------------------------------------------------------
if (-not $Choice) {
    Write-Host ""
    Write-Host "  1  Load the pen notes (sync, then conversion)"
    Write-Host "  2  Integrate my corrections made in Obsidian"
    $Choice = (Read-Host "Your choice (Enter = 1)").Trim()
    if ($Choice -notin @('1', '2')) { $Choice = '1' }
}

if ($Choice -eq '2') {
    Step 1 'Notes corrected in Obsidian'
    $changed = @((python $Tool changed | Out-String | ConvertFrom-Json).notes)
    if ($changed.Count -eq 0 -and -not $Prompt) { Done 'No correction to integrate.' 'Green' }
    foreach ($c in $changed) { Write-Host "  $($c.state): $($c.note)" }
    $calendarOk = Test-Calendar
    Step 2 'Integration by Claude (a few minutes)'
    $instruction = @"
Integration of the user's corrections (launched by run.ps1).
$read, then apply the "Integrate corrections" section of the pen-notes skill, with the rules of "Automatic mode".
Do not convert pages. $rules
Calendar: $(if ($calendarOk) { 'available' } else { 'unavailable, do not look up meetings' }).
"@
    if ($Prompt) { $instruction = $Prompt }
    Invoke-Claude $instruction 'Corrections integrated'
    Done "Finished. Summary appended to the conversion log." 'Green'
}

# --- 1. calendar --------------------------------------------------------------------------
Step 1 'Calendar'
$calendarOk = Test-Calendar -AllowLogin
if (-not $agendaOn) { Write-Host 'No calendar configured.' }
elseif (-not $calendarOk) {
    Write-Host "Calendar unavailable: the conversion goes on, without identifying meetings." -ForegroundColor Yellow
}

# --- 2. sync ------------------------------------------------------------------------------
Step 2 'Pen sync (pen on, blue light, not connected to the phone)'
if ($NoSync) { Write-Host 'Sync skipped (-NoSync).' } else {
    & $Exe sync --data-dir $Data
    switch ($LASTEXITCODE) {
        0 { }
        3 { Done "A notebook did not arrive in full: run the shortcut again (nothing was converted)." }
        default { Done "Sync failed (code $LASTEXITCODE): is the pen on and in range? Nothing was converted." 'Red' }
    }
}
$pending = @((python $Tool pending | Out-String | ConvertFrom-Json).pages)
if ($pending.Count -eq 0 -and -not $Prompt) { Done 'Nothing new to convert.' 'Green' }
Write-Host "$($pending.Count) page(s) to convert."

# --- 3. conversion ------------------------------------------------------------------------
Step 3 'Conversion into Obsidian notes by Claude (a few minutes)'
$instruction = @"
Automatic conversion of the pen pages (launched by run.ps1).
$read, then apply the pen-notes skill following its "Automatic mode" section, which wins over the rest.
$rules
Calendar: $(if ($calendarOk) { 'available' } else { 'unavailable, do not look up meetings' }).
"@
if ($Prompt) { $instruction = $Prompt }
Invoke-Claude $instruction 'Conversion'
Done "Finished. Summary appended to the conversion log." 'Green'
