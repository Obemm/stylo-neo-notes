# Pen notes — desktop window (Windows Forms, nothing to install).
#
# Buttons: sync + conversion (all notebooks or one), convert without sync, integrate my corrections, stop, open
# today's note, open the conversion log. Each action runs scripts/run.ps1 in the background (-NoPause) and shows
# its output live. The pen password is never typed here: when the pen asks for one that is not saved
# (run.ps1 exits with 4), the sync opens in a separate console, then the conversion goes on here.
#
#   pwsh -NoProfile -WindowStyle Hidden -File scripts\app.ps1 [-Config C:\path\to\config.toml]

param(
    [string]$Config,
    [ValidateSet('', 'status', 'convert', 'fix', 'paste')]
    [string]$SelfTest,             # tests: clicks one action by itself, writes the window text to -SelfTestOut, closes
    [string]$SelfTestOut,
    [string]$SelfTestText,         # paste test: file whose text is pasted
    [int]$SelfTestMeeting = 0,     # paste test: index in the meeting list (0 = no meeting)
    [string]$SelfTestDate          # paste test: date of the meeting list (YYYY-MM-DD)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$env:PYTHONIOENCODING = 'utf-8'
$env:NO_COLOR = '1'
if ($Config) { $env:STYLO_NEO_CONFIG = (Resolve-Path $Config).Path }
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Tool = Join-Path $Repo '.claude\skills\pen-notes\pen_tool.py'
$Run  = Join-Path $PSScriptRoot 'run.ps1'
$Pwsh = (Get-Command pwsh).Source

function Show-Error($text) {
    [System.Windows.Forms.MessageBox]::Show($text, 'stylo-neo-notes', 'OK', 'Error') | Out-Null
}
$cfgText = & python $Tool config 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Show-Error "Configuration error / erreur de configuration :`n`n$cfgText"; exit 1 }
$cfg = $cfgText | ConvertFrom-Json
$Fr = $cfg.language -eq 'fr'
$env:STYLO_NEO_LANG = $cfg.language
function T($en, $fr) { if ($script:Fr) { $fr } else { $en } }
$ConfigDir = if ($cfg.config_file) { Split-Path $cfg.config_file } else { $Repo }

# --- window --------------------------------------------------------------------------------------------------
$font = New-Object System.Drawing.Font('Segoe UI', 10)
$form = New-Object System.Windows.Forms.Form
$form.Text = T 'Pen notes' 'Notes du stylo'
$form.Size = New-Object System.Drawing.Size(860, 640)
$form.MinimumSize = New-Object System.Drawing.Size(700, 480)
$form.StartPosition = 'CenterScreen'
$form.Font = $font
$ico = Join-Path $PSScriptRoot 'pen.ico'
if (Test-Path $ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }

$top = New-Object System.Windows.Forms.FlowLayoutPanel
$top.Dock = 'Top'; $top.AutoSize = $true; $top.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 0)
$top.WrapContents = $true

function New-Label($text) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true; $l.Margin = New-Object System.Windows.Forms.Padding(0, 8, 18, 4)
    $l
}
function New-Button($text, $width = 0) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.AutoSize = $true; $b.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 2)
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 4)
    if ($width) { $b.Width = $width }
    $b
}

$lblAgenda  = New-Label (T 'Calendar: …' 'Agenda : …')
$lblPending = New-Label (T 'Pages pending: …' 'Pages en attente : …')
$lblFixed   = New-Label (T 'Notes corrected: …' 'Notes corrigées : …')
$btnLogin   = New-Button (T 'Sign in again' 'Se reconnecter'); $btnLogin.Visible = $false
$btnRefresh = New-Button (T 'Refresh' 'Actualiser')
$top.Controls.AddRange(@($lblAgenda, $btnLogin, $lblPending, $lblFixed, $btnRefresh))

$actions = New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Top'; $actions.AutoSize = $true; $actions.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$cmbNotebook = New-Object System.Windows.Forms.ComboBox
$cmbNotebook.DropDownStyle = 'DropDownList'; $cmbNotebook.Width = 170
$cmbNotebook.Margin = New-Object System.Windows.Forms.Padding(0, 4, 6, 4)
[void]$cmbNotebook.Items.Add((T 'All notebooks' 'Tous les carnets')); $cmbNotebook.SelectedIndex = 0
$btnSync    = New-Button (T 'Sync + conversion' 'Synchro + conversion')
$chkErase   = New-Object System.Windows.Forms.CheckBox
$chkErase.Text = T 'Erase from the pen after the sync' 'Effacer du stylo après la synchro'
$chkErase.AutoSize = $true; $chkErase.Checked = $false
$chkErase.Margin = New-Object System.Windows.Forms.Padding(0, 7, 12, 4)
$tips = New-Object System.Windows.Forms.ToolTip
$tips.SetToolTip($chkErase, (T 'Only notebooks fully received, and only once saved on the PC. Makes the next syncs faster.' `
                               'Seulement les carnets reçus en entier, et seulement une fois enregistrés sur le PC. Les synchros suivantes sont plus rapides.'))
$btnConvert = New-Button (T 'Convert without sync' 'Convertir sans synchro')
$btnFix     = New-Button (T 'Integrate my corrections' 'Intégrer mes corrections')
$btnStop    = New-Button (T 'Stop' 'Arrêter'); $btnStop.Enabled = $false
$actions.Controls.AddRange(@($cmbNotebook, $btnSync, $chkErase, $btnConvert, $btnFix, $btnStop))

$links = New-Object System.Windows.Forms.FlowLayoutPanel
$links.Dock = 'Top'; $links.AutoSize = $true; $links.Padding = New-Object System.Windows.Forms.Padding(8, 0, 8, 6)
$btnToday = New-Button (T "Open today's note" 'Ouvrir la note du jour')
$btnLog   = New-Button (T 'Open the conversion log' 'Ouvrir le journal des conversions')
$links.Controls.AddRange(@($btnToday, $btnLog))

$out = New-Object System.Windows.Forms.TextBox
$out.Multiline = $true; $out.ReadOnly = $true; $out.ScrollBars = 'Vertical'; $out.Dock = 'Fill'
$out.Font = New-Object System.Drawing.Font('Consolas', 10); $out.BackColor = [System.Drawing.Color]::White
$out.WordWrap = $true

# --- tabs: "Sync" (actions + live output) and "Paste" (notes or a meeting transcript typed elsewhere) -----------
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabSync  = New-Object System.Windows.Forms.TabPage; $tabSync.Text = T 'Sync' 'Synchro'
$tabPaste = New-Object System.Windows.Forms.TabPage; $tabPaste.Text = T 'Paste notes or a transcript' 'Coller des notes ou une transcription'
$tabSync.Controls.Add($out)      # Fill first, then the Top panels (docking order)
$tabSync.Controls.Add($links)
$tabSync.Controls.Add($actions)

$pasteTop = New-Object System.Windows.Forms.FlowLayoutPanel
$pasteTop.Dock = 'Top'; $pasteTop.AutoSize = $true; $pasteTop.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 0)
$rbNotes = New-Object System.Windows.Forms.RadioButton
$rbNotes.Text = T 'Notes' 'Notes'; $rbNotes.AutoSize = $true; $rbNotes.Checked = $true
$rbNotes.Margin = New-Object System.Windows.Forms.Padding(0, 7, 8, 4)
$rbTranscript = New-Object System.Windows.Forms.RadioButton
$rbTranscript.Text = T 'Meeting transcript' 'Transcription de réunion'; $rbTranscript.AutoSize = $true
$rbTranscript.Margin = New-Object System.Windows.Forms.Padding(0, 7, 18, 4)
$dtDate = New-Object System.Windows.Forms.DateTimePicker
$dtDate.Format = 'Short'; $dtDate.Width = 120; $dtDate.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 4)
$cmbMeeting = New-Object System.Windows.Forms.ComboBox
$cmbMeeting.DropDownStyle = 'DropDownList'; $cmbMeeting.Width = 430
$cmbMeeting.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 4)
$pasteTop.Controls.AddRange(@($rbNotes, $rbTranscript, $dtDate, $cmbMeeting))

$pasteFree = New-Object System.Windows.Forms.FlowLayoutPanel
$pasteFree.Dock = 'Top'; $pasteFree.AutoSize = $true; $pasteFree.Padding = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
$lblTitle = New-Label (T 'Title:' 'Titre :'); $lblTitle.Margin = New-Object System.Windows.Forms.Padding(0, 8, 4, 4)
$txtTitle = New-Object System.Windows.Forms.TextBox; $txtTitle.Width = 330
$lblStart = New-Label (T 'Start (HH:MM):' 'Début (HH:MM) :'); $lblStart.Margin = New-Object System.Windows.Forms.Padding(8, 8, 4, 4)
$txtStart = New-Object System.Windows.Forms.TextBox; $txtStart.Width = 60
$pasteFree.Controls.AddRange(@($lblTitle, $txtTitle, $lblStart, $txtStart))

$pasteBottom = New-Object System.Windows.Forms.FlowLayoutPanel
$pasteBottom.Dock = 'Bottom'; $pasteBottom.AutoSize = $true; $pasteBottom.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 8)
$btnFile = New-Button (T 'File it in Obsidian' 'Ranger dans Obsidian')
$lblPaste = New-Label ''
$pasteBottom.Controls.AddRange(@($btnFile, $lblPaste))

$txtPaste = New-Object System.Windows.Forms.TextBox
$txtPaste.Multiline = $true; $txtPaste.ScrollBars = 'Vertical'; $txtPaste.Dock = 'Fill'; $txtPaste.AcceptsReturn = $true
$txtPaste.Font = New-Object System.Drawing.Font('Segoe UI', 10); $txtPaste.MaxLength = 0
$tabPaste.Controls.Add($txtPaste)
$tabPaste.Controls.Add($pasteBottom)
$tabPaste.Controls.Add($pasteFree)
$tabPaste.Controls.Add($pasteTop)

$tabs.TabPages.AddRange(@($tabSync, $tabPaste))
$form.Controls.Add($tabs)
$form.Controls.Add($top)

function Write-Out($line) {
    $clean = $line -replace "`e\[[0-9;]*[A-Za-z]", ''
    $out.AppendText($clean + "`r`n")
}

# --- background processes, polled by a UI timer (no threads touch the window) ------------------------------
$script:job = $null        # @{ Proc; Out; Err; OnExit; Live }
$script:queue = @()        # follow-up actions to start when the current one ends

function Start-Proc($file, [string[]]$arguments, [scriptblock]$onExit, [switch]$Live, $workDir = $Repo) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    foreach ($a in $arguments) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $workDir
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    @{ Proc = $p; Out = $p.StandardOutput.ReadLineAsync(); Err = $p.StandardError.ReadLineAsync()
       OnExit = $onExit; Live = [bool]$Live; Text = New-Object System.Text.StringBuilder; Done = $false }
}

$script:bg = [System.Collections.ArrayList]::new()   # quiet helpers (status, calendar check)

function Pump($j) {
    foreach ($s in 'Out', 'Err') {
        while ($j[$s] -and $j[$s].IsCompleted) {
            $line = $j[$s].Result
            if ($null -eq $line) { $j[$s] = $null; break }
            if ($j.Live) { Write-Out $line } else { [void]$j.Text.AppendLine($line) }
            $j[$s] = if ($s -eq 'Out') { $j.Proc.StandardOutput.ReadLineAsync() } else { $j.Proc.StandardError.ReadLineAsync() }
        }
    }
    if (-not $j.Done -and -not $j.Out -and -not $j.Err -and $j.Proc.HasExited) {
        $j.Done = $true
        & $j.OnExit $j.Proc.ExitCode $j.Text.ToString()
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
    if ($script:job) { Pump $script:job; if ($script:job.Done) { $script:job = $null } }
    foreach ($j in @($script:bg)) { Pump $j; if ($j.Done) { $script:bg.Remove($j) } }
    if ($script:console -and $script:console.HasExited) {
        $c = $script:console; $script:console = $null
        & $script:afterConsole $c.ExitCode
    }
})

function Set-Busy($busy) {
    foreach ($b in @($btnSync, $btnConvert, $btnFix, $btnRefresh, $cmbNotebook, $chkErase, $btnFile)) { $b.Enabled = -not $busy }
    $btnStop.Enabled = $busy
    $form.Cursor = if ($busy) { 'AppStarting' } else { 'Default' }
}

# --- status line -------------------------------------------------------------------------------------------
function Update-Status {
    [void]$script:bg.Add((Start-Proc 'python' @($Tool, 'status') {
        param($code, $text)
        try {
            $s = $text | ConvertFrom-Json
            $lblPending.Text = if ($null -eq $s.pending) { T 'Pages pending: ?' 'Pages en attente : ?' } else { (T 'Pages pending: ' 'Pages en attente : ') + $s.pending }
            $lblFixed.Text = (T 'Notes corrected: ' 'Notes corrigées : ') + $s.corrected
            $keep = $cmbNotebook.SelectedItem
            while ($cmbNotebook.Items.Count -gt 1) { $cmbNotebook.Items.RemoveAt(1) }
            foreach ($n in $s.notebooks) { [void]$cmbNotebook.Items.Add($n) }
            $cmbNotebook.SelectedItem = $keep; if ($cmbNotebook.SelectedIndex -lt 0) { $cmbNotebook.SelectedIndex = 0 }
        } catch { $lblPending.Text = T 'Pages pending: ?' 'Pages en attente : ?' }
    }))
    if ($cfg.agenda.source -ne 'mcp') { $lblAgenda.Text = T 'Calendar: not configured' 'Agenda : non configuré'; return }
    if (-not $cfg.agenda.session_check) { $lblAgenda.Text = T 'Calendar: configured' 'Agenda : configuré'; return }
    $lblAgenda.Text = T 'Calendar: checking…' 'Agenda : vérification…'
    [void]$script:bg.Add((Start-Proc $Pwsh @('-NoProfile', '-Command', $cfg.agenda.session_check) {
        param($code, $text)
        $btnLogin.Visible = ($code -eq 2 -and $cfg.agenda.login)
        $lblAgenda.Text = switch ($code) {
            0 { T 'Calendar: OK' 'Agenda : session valide' }
            2 { T 'Calendar: session expired' 'Agenda : session expirée' }
            default { T 'Calendar: unavailable' 'Agenda : indisponible' }
        }
        $lblAgenda.ForeColor = if ($code -eq 0) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
    } -workDir $ConfigDir))
}

# --- actions -----------------------------------------------------------------------------------------------
function Start-Run([string[]]$runArgs, $title) {
    Set-Busy $true
    Write-Out ''; Write-Out "=== $title — $(Get-Date -Format 'HH:mm') ==="
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Run, '-NoPause') + $runArgs
    if ($env:STYLO_NEO_CONFIG) { $all += @('-Config', $env:STYLO_NEO_CONFIG) }
    $script:job = Start-Proc $Pwsh $all {
        param($code, $text)
        if ($code -eq 4) {
            # The pen wants a password that is not saved: sync in a separate console, never in this window.
            Write-Out (T '→ Type the pen password in the console window, then the conversion goes on here.' `
                         '→ Tapez le mot de passe du stylo dans la console qui s''ouvre ; la conversion reprendra ici.')
            $syncArgs = "& '$($cfg.exe)' sync --data-dir '$($cfg.data_dir)'"
            if ($script:notebook) { $syncArgs += " --notebook $script:notebook" }
            if ($chkErase.Checked) { $syncArgs += ' --erase-received' }
            $syncArgs += "; Read-Host '$(T 'Press Enter to close' 'Entrée pour fermer')'"
            $script:afterConsole = {
                param($c)
                Start-Run @('-Choice', '1', '-NoSync') (T 'Conversion' 'Conversion')
            }
            $script:console = Start-Process $Pwsh -ArgumentList @('-NoProfile', '-Command', $syncArgs) -PassThru
            return
        }
        if ($code -eq 0) { Write-Out (T '— finished —' '— terminé —') } else { Write-Out ((T '— stopped, code ' '— arrêt, code ') + $code + ' —') }
        Set-Busy $false
        Update-Status
    } -Live
}

$btnSync.Add_Click({
    $script:notebook = if ($cmbNotebook.SelectedIndex -gt 0) { [string]$cmbNotebook.SelectedItem } else { $null }
    $a = @('-Choice', '1'); if ($script:notebook) { $a += @('-Notebook', $script:notebook) }
    if ($chkErase.Checked) { $a += '-Erase' }
    Start-Run $a (T 'Sync + conversion' 'Synchro + conversion')
})
$btnConvert.Add_Click({ $script:notebook = $null; Start-Run @('-Choice', '1', '-NoSync') (T 'Convert without sync' 'Conversion sans synchro') })
$btnFix.Add_Click({ $script:notebook = $null; Start-Run @('-Choice', '2') (T 'Integrate my corrections' 'Intégration des corrections') })
$btnStop.Add_Click({
    if ($script:job -and -not $script:job.Proc.HasExited) {
        try { $script:job.Proc.Kill($true) } catch { }
        Write-Out (T '— stopped by the user (pages not marked done will be taken up next time) —' `
                     '— arrêté par l''utilisateur (les pages non marquées traitées seront reprises la prochaine fois) —')
    }
})
$btnRefresh.Add_Click({ Update-Status })
$btnLogin.Add_Click({
    $btnLogin.Visible = $false
    $lblAgenda.Text = T 'Calendar: sign in in the window that opens…' 'Agenda : connectez-vous dans la fenêtre qui s''ouvre…'
    $script:afterConsole = { param($c) Update-Status }
    $script:console = Start-Process $Pwsh -ArgumentList @('-NoProfile', '-Command', $cfg.agenda.login) `
                        -WorkingDirectory $ConfigDir -WindowStyle Minimized -PassThru
})

# --- paste tab: meetings of the chosen date, then "File it" ------------------------------------------------
$script:events = @()
function Update-Meetings {
    $cmbMeeting.Items.Clear(); $script:events = @()
    [void]$cmbMeeting.Items.Add((T '(no meeting: title and start below)' '(aucune réunion : titre et début ci-dessous)'))
    $cmbMeeting.SelectedIndex = 0
    $command = $cfg.agenda.list_command
    if (-not $command) { $lblPaste.Text = T 'No meeting list configured: type a title.' 'Pas de liste de réunions configurée : saisissez un titre.'; return }
    # Callbacks run later from the timer, without this function's variables: keep the date at script level.
    $script:meetingsDay = $dtDate.Value.ToString('yyyy-MM-dd')
    $lblPaste.Text = T 'Reading the calendar…' 'Lecture de l''agenda…'
    [void]$script:bg.Add((Start-Proc $Pwsh @('-NoProfile', '-Command', ($command -replace '\{date\}', $script:meetingsDay)) {
        param($code, $text)
        if ($dtDate.Value.ToString('yyyy-MM-dd') -ne $script:meetingsDay) { return }   # the date changed meanwhile
        try {
            if ($code -ne 0) { throw "code $code" }
            $json = ($text -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
            $script:events = @($json.events)
            while ($cmbMeeting.Items.Count -gt 1) { $cmbMeeting.Items.RemoveAt(1) }   # two answers for one date: no duplicates
            foreach ($e in $script:events) {
                $label = if ($e.private) { T '(private meeting)' '(réunion privée)' } else { $e.subject }
                [void]$cmbMeeting.Items.Add("$($e.start.Substring(11, 5))–$($e.end.Substring(11, 5))  $label")
            }
            $lblPaste.Text = if ($script:events.Count) { T "$($script:events.Count) meeting(s) on this day." "$($script:events.Count) réunion(s) ce jour-là." } `
                             else { T 'No meeting on this day.' 'Aucune réunion ce jour-là.' }
        } catch {
            $lblPaste.Text = T 'Calendar unavailable: type a title.' 'Agenda indisponible : saisissez un titre.'
        }
    } -workDir $ConfigDir))
}
$dtDate.Add_ValueChanged({ Update-Meetings })
$cmbMeeting.Add_SelectedIndexChanged({ $pasteFree.Visible = ($cmbMeeting.SelectedIndex -le 0) })

$btnFile.Add_Click({
    $text = $txtPaste.Text.Trim()
    if (-not $text) { $lblPaste.Text = T 'Paste some text first.' 'Collez d''abord un texte.'; return }
    $day = $dtDate.Value.ToString('yyyy-MM-dd')
    $a = @($Tool, 'paste-save', '--kind', $(if ($rbTranscript.Checked) { 'transcript' } else { 'notes' }), '--date', $day)
    $private = $false
    if ($cmbMeeting.SelectedIndex -gt 0) {
        $e = $script:events[$cmbMeeting.SelectedIndex - 1]
        $a += @('--start', $e.start.Substring(11, 5), '--end', $e.end.Substring(11, 5), '--event-id', $e.id)
        if ($e.private) { $private = $true; $a += @('--title', (T 'Private meeting' 'Réunion privée')) } else { $a += @('--title', $e.subject) }
    } else {
        if ($txtTitle.Text.Trim()) { $a += @('--title', $txtTitle.Text.Trim()) }
        if ($txtStart.Text.Trim()) { $a += @('--start', $txtStart.Text.Trim()) }
    }
    if ($private) { $a += '--private' }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "stylo-neo-paste-$([guid]::NewGuid()).txt"
    try {
        [IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))
        $res = & python @($a + @('--text-file', $tmp)) 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { $lblPaste.Text = $res.Trim(); return }
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    $txtPaste.Clear(); $txtTitle.Clear(); $txtStart.Clear()
    $lblPaste.Text = T 'Saved in the vault; filing by Claude in the Sync tab.' 'Enregistré dans le coffre ; rangement par Claude dans l''onglet Synchro.'
    $tabs.SelectedTab = $tabSync
    Start-Run @('-Choice', '3') (T 'Filing what was pasted' 'Rangement des collages')
})

function Open-InVault($relative) {
    $vaultName = Split-Path $cfg.vault -Leaf
    $rel = $relative -replace '\\', '/'
    $uri = "obsidian://open?vault=$([uri]::EscapeDataString($vaultName))&file=$([uri]::EscapeDataString($rel))"
    try { Start-Process $uri }
    catch {
        $path = Join-Path $cfg.vault $relative
        if (Test-Path "$path.md") { Start-Process "$path.md" } elseif (Test-Path $path) { Start-Process $path }
        else { Show-Error ((T 'Not found: ' 'Introuvable : ') + $path) }
    }
}
$btnToday.Add_Click({ Open-InVault (Join-Path $cfg.journal_dir (Get-Date -Format 'yyyy-MM-dd')) })
$btnLog.Add_Click({ Open-InVault (Join-Path $cfg.system_dir ([IO.Path]::GetFileNameWithoutExtension($cfg.log_file))) })

$form.Add_Shown({
    if ($SelfTestDate) { $dtDate.Value = [datetime]::ParseExact($SelfTestDate, 'yyyy-MM-dd', $null) }
    Update-Status; Update-Meetings; $timer.Start()
    if ($SelfTest) {
        switch ($SelfTest) { 'convert' { $btnConvert.PerformClick() } 'fix' { $btnFix.PerformClick() } }
        $script:pasteDone = $SelfTest -ne 'paste'
        $script:selfTimer = New-Object System.Windows.Forms.Timer; $script:selfTimer.Interval = 500
        $script:selfTimer.Add_Tick({
            if (-not $script:pasteDone -and $script:bg.Count -eq 0) {
                $script:pasteDone = $true
                $tabs.SelectedTab = $tabPaste
                $txtPaste.Text = Get-Content -Raw -Encoding utf8 $SelfTestText
                if ($SelfTestMeeting -lt $cmbMeeting.Items.Count) { $cmbMeeting.SelectedIndex = $SelfTestMeeting }
                $script:pasteState = "paste: $($cmbMeeting.SelectedItem) | $($lblPaste.Text)"
                $btnFile.PerformClick()
                return
            }
            if ($script:pasteDone -and -not $script:job -and $script:bg.Count -eq 0 -and -not $script:console) {
                $script:selfTimer.Stop()
                $state = "$($lblAgenda.Text) | $($lblPending.Text) | $($lblFixed.Text) | notebooks: " +
                         (($cmbNotebook.Items | ForEach-Object { $_ }) -join ', ') + " | meetings: $($cmbMeeting.Items.Count - 1)" +
                         "`r`n$($script:pasteState) | $($lblPaste.Text)"
                ($state + "`r`n" + $out.Text) | Set-Content -Encoding utf8 $SelfTestOut
                $form.Close()
            }
        })
        $script:selfTimer.Start()
    }
})
$form.Add_FormClosing({
    param($s, $e)
    if ($script:job -and -not $script:job.Proc.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            (T 'A task is running. Stop it and close?' 'Un traitement est en cours. L''arrêter et fermer ?'),
            $form.Text, 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $e.Cancel = $true; return }
        try { $script:job.Proc.Kill($true) } catch { }
    }
    $timer.Stop()
})

Write-Out (T 'Pen on (blue light), phone Bluetooth off, then "Sync + conversion".' `
             'Stylo allumé (voyant bleu), Bluetooth du téléphone coupé, puis « Synchro + conversion ».')
[void]$form.ShowDialog()
