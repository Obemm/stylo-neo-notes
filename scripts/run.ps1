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

# Messages of this window follow the notes language of the configuration (en | fr); stylo-neo.exe too.
$Fr = $false
function T($en, $fr) { if ($script:Fr) { $fr } else { $en } }
function Step($n, $text) { Write-Host ""; Write-Host "[$n] $text" -ForegroundColor Cyan }
function Done($message, $colour = 'Yellow') {
    Write-Host ""; Write-Host $message -ForegroundColor $colour
    Write-Host ""; Read-Host (T 'Press Enter to close' 'Entrée pour fermer') | Out-Null
    exit
}
function Posix($path) { ($path -replace '\\', '/') }

$host.UI.RawUI.WindowTitle = 'Pen notes'
$cfgText = python $Tool config | Out-String
if ($LASTEXITCODE -ne 0) { Done "Configuration error (see above). Copy config.example.toml to config.toml and set vault.path." 'Red' }
$cfg   = $cfgText | ConvertFrom-Json
$Fr    = $cfg.language -eq 'fr'
$env:STYLO_NEO_LANG = $cfg.language
$host.UI.RawUI.WindowTitle = T 'Pen notes' 'Notes du stylo'
$Vault = $cfg.vault
$Exe   = $cfg.exe
$Data  = $cfg.data_dir
$Log   = $cfg.paths.log_file
foreach ($p in @($Exe, $Vault)) { if (-not $p -or -not (Test-Path $p)) { Done (T "Not found: $p" "Introuvable : $p") 'Red' } }
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
    if ($code -ne 0) { Done (T "Claude stopped with an error (code $code): see the message above." "Claude s'est arrêté en erreur (code $code) : voir le message ci-dessus.") 'Red' }
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
            Write-Host (T "Calendar session expired: sign in in the window that opens." "Session de l'agenda expirée : connectez-vous dans la fenêtre qui s'ouvre.") -ForegroundColor Yellow
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
    Write-Host (T "  1  Load the pen notes (sync, then conversion)" "  1  Charger les notes du stylo (synchro puis conversion)")
    Write-Host (T "  2  Integrate my corrections made in Obsidian" "  2  Intégrer mes corrections faites dans Obsidian")
    $Choice = (Read-Host (T "Your choice (Enter = 1)" "Votre choix (Entrée = 1)")).Trim()
    if ($Choice -notin @('1', '2')) { $Choice = '1' }
}

if ($Choice -eq '2') {
    Step 1 (T 'Notes corrected in Obsidian' 'Notes corrigées dans Obsidian')
    $changed = @((python $Tool changed | Out-String | ConvertFrom-Json).notes)
    if ($changed.Count -eq 0 -and -not $Prompt) { Done (T 'No correction to integrate.' 'Aucune correction à intégrer.') 'Green' }
    $states = @{ modified = 'modifiée'; renamed = 'renommée'; deleted = 'supprimée'; no_reference = 'sans référence' }
    foreach ($c in $changed) { Write-Host (T "  $($c.state): $($c.note)" "  $($states[$c.state]) : $($c.note)") }
    $calendarOk = Test-Calendar
    Step 2 (T 'Integration by Claude (a few minutes)' 'Intégration par Claude (quelques minutes)')
    $instruction = @"
Integration of the user's corrections (launched by run.ps1).
$read, then apply the "Integrate corrections" section of the pen-notes skill, with the rules of "Automatic mode".
Do not convert pages. $rules
Calendar: $(if ($calendarOk) { 'available' } else { 'unavailable, do not look up meetings' }).
"@
    if ($Prompt) { $instruction = $Prompt }
    Invoke-Claude $instruction (T 'Corrections integrated' 'Intégration des corrections')
    Done (T "Finished. Summary appended to the conversion log." "Terminé. Compte rendu ajouté au journal des conversions.") 'Green'
}

# --- 1. calendar --------------------------------------------------------------------------
Step 1 (T 'Calendar' 'Agenda')
$calendarOk = Test-Calendar -AllowLogin
if (-not $agendaOn) { Write-Host (T 'No calendar configured.' 'Aucun agenda configuré.') }
elseif (-not $calendarOk) {
    Write-Host (T "Calendar unavailable: the conversion goes on, without identifying meetings." "Agenda indisponible : la conversion continue, sans identifier les réunions.") -ForegroundColor Yellow
}

# --- 2. sync ------------------------------------------------------------------------------
Step 2 (T 'Pen sync (pen on, blue light, not connected to the phone)' 'Synchro du stylo (allumé, voyant bleu, déconnecté du téléphone)')
if ($NoSync) { Write-Host (T 'Sync skipped (-NoSync).' 'Synchro sautée (-NoSync).') } else {
    & $Exe sync --data-dir $Data
    switch ($LASTEXITCODE) {
        0 { }
        3 { Done (T "A notebook did not arrive in full: run the shortcut again (nothing was converted)." "Un carnet n'est pas arrivé en entier : relancez le raccourci (rien n'a été converti).") }
        default { Done (T "Sync failed (code $LASTEXITCODE): is the pen on and in range? Nothing was converted." "Synchro en échec (code $LASTEXITCODE) : stylo allumé et à portée ? Rien n'a été converti.") 'Red' }
    }
}
$pending = @((python $Tool pending | Out-String | ConvertFrom-Json).pages)
if ($pending.Count -eq 0 -and -not $Prompt) { Done (T 'Nothing new to convert.' 'Rien de nouveau à convertir.') 'Green' }
Write-Host (T "$($pending.Count) page(s) to convert." "$($pending.Count) page(s) à convertir.")

# --- 3. conversion ------------------------------------------------------------------------
Step 3 (T 'Conversion into Obsidian notes by Claude (a few minutes)' 'Conversion en notes Obsidian par Claude (quelques minutes)')
$instruction = @"
Automatic conversion of the pen pages (launched by run.ps1).
$read, then apply the pen-notes skill following its "Automatic mode" section, which wins over the rest.
$rules
Calendar: $(if ($calendarOk) { 'available' } else { 'unavailable, do not look up meetings' }).
"@
if ($Prompt) { $instruction = $Prompt }
Invoke-Claude $instruction (T 'Conversion' 'Conversion')
Done (T "Finished. Summary appended to the conversion log." "Terminé. Compte rendu ajouté au journal des conversions.") 'Green'
