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
try { [void][System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2) } catch { }
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

# --- look and feel ---------------------------------------------------------------------------------------------
# A light, flat design: white cards on a pale background, one accent colour, rounded corners, a dark activity log.
$C = @{
    Bg      = [System.Drawing.Color]::FromArgb(244, 246, 250)
    Card    = [System.Drawing.Color]::White
    Border  = [System.Drawing.Color]::FromArgb(226, 230, 237)
    Text    = [System.Drawing.Color]::FromArgb(17, 24, 39)
    Muted   = [System.Drawing.Color]::FromArgb(107, 114, 128)
    Accent  = [System.Drawing.Color]::FromArgb(37, 99, 235)
    AccentH = [System.Drawing.Color]::FromArgb(29, 78, 216)
    AccentL = [System.Drawing.Color]::FromArgb(219, 234, 254)
    Hover   = [System.Drawing.Color]::FromArgb(243, 244, 246)
    OkBg    = [System.Drawing.Color]::FromArgb(220, 252, 231); OkFg   = [System.Drawing.Color]::FromArgb(21, 128, 61)
    WarnBg  = [System.Drawing.Color]::FromArgb(254, 243, 199); WarnFg = [System.Drawing.Color]::FromArgb(180, 83, 9)
    InfoBg  = [System.Drawing.Color]::FromArgb(241, 245, 249); InfoFg = [System.Drawing.Color]::FromArgb(71, 85, 105)
    DangerFg = [System.Drawing.Color]::FromArgb(185, 28, 28)
    LogBg   = [System.Drawing.Color]::FromArgb(15, 23, 42); LogFg = [System.Drawing.Color]::FromArgb(226, 232, 240)
}
# Screen zoom (125 %, 150 %…): fonts follow it by themselves, pixel sizes are scaled with K.
$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $K = $g0.DpiX / 96; $g0.Dispose()
function K($n) { [int][math]::Round($n * $script:K) }
$uiFont = if ([System.Drawing.FontFamily]::Families.Name -contains 'Segoe UI Variable Text') { 'Segoe UI Variable Text' } else { 'Segoe UI' }
$font      = New-Object System.Drawing.Font($uiFont, 10)
$fontSmall = New-Object System.Drawing.Font($uiFont, 9)
$fontBold  = New-Object System.Drawing.Font($uiFont, 10, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font($uiFont, 15, [System.Drawing.FontStyle]::Bold)
$fontH2    = New-Object System.Drawing.Font($uiFont, 11, [System.Drawing.FontStyle]::Bold)
$monoName  = if ([System.Drawing.FontFamily]::Families.Name -contains 'Cascadia Mono') { 'Cascadia Mono' } else { 'Consolas' }
function Pad($l, $t, $r, $b) { New-Object System.Windows.Forms.Padding((K $l), (K $t), (K $r), (K $b)) }

function Get-RoundPath($rect, $radius) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $p.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $p.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $p.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure(); $p
}
# Rounded corners for a control (buttons, chips): its region follows its size.
function Set-Round($ctrl, $radius = 8) {
    $ctrl.Tag = $radius
    $ctrl.Add_Resize({
        param($s, $e)
        if ($s.Width -gt 2 -and $s.Height -gt 2) {
            $s.Region = New-Object System.Drawing.Region((Get-RoundPath (New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)) $s.Tag))
        }
    })
}
# A white card with a thin rounded border, drawn behind its children.
function New-Card($padding = (Pad 16 14 16 14)) {
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = $C.Bg; $p.Padding = $padding
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $r = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = Get-RoundPath $r 10
        $g.FillPath((New-Object System.Drawing.SolidBrush($C.Card)), $path)
        $g.DrawPath((New-Object System.Drawing.Pen($C.Border)), $path)
    })
    $p
}
function New-Label($text, $style = 'normal') {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true; $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Margin = Pad 0 8 14 4
    switch ($style) {
        'muted' { $l.ForeColor = $C.Muted; $l.Font = $fontSmall }
        'h2'    { $l.ForeColor = $C.Text; $l.Font = $fontH2; $l.Margin = Pad 0 0 0 8 }
        default { $l.ForeColor = $C.Text }
    }
    $l
}
# Buttons: 'primary' (accent), 'secondary' (outlined), 'ghost' (text only), 'danger' (outlined, red text).
function New-Button($text, $kind = 'secondary') {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.AutoSize = $true; $b.AutoSizeMode = 'GrowAndShrink'
    $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.Font = $font
    $b.Padding = Pad 12 5 12 5; $b.Margin = Pad 0 4 8 4
    $b.UseVisualStyleBackColor = $false
    switch ($kind) {
        'primary' {
            $b.BackColor = $C.Accent; $b.ForeColor = [System.Drawing.Color]::White; $b.Font = $fontBold
            $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $C.AccentH
            $b.FlatAppearance.MouseDownBackColor = $C.AccentH
        }
        'ghost' {
            $b.BackColor = $C.Card; $b.ForeColor = $C.Accent
            $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $C.AccentL
            $b.Padding = Pad 6 4 6 4
        }
        'danger' {
            $b.BackColor = $C.Card; $b.ForeColor = $C.DangerFg
            $b.FlatAppearance.BorderColor = $C.Border; $b.FlatAppearance.MouseOverBackColor = $C.Hover
        }
        default {
            $b.BackColor = $C.Card; $b.ForeColor = $C.Text
            $b.FlatAppearance.BorderColor = $C.Border; $b.FlatAppearance.MouseOverBackColor = $C.Hover
        }
    }
    Set-Round $b 8
    $b
}
# Status chips of the header: 'ok', 'warn' or 'info'.
function New-Chip($text) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true; $l.Font = $fontSmall
    $l.Padding = Pad 10 4 10 4; $l.Margin = Pad 0 2 8 2
    Set-Round $l 11
    Set-Chip $l 'info'
    $l
}
function Set-Chip($chip, $state) {
    switch ($state) {
        'ok'   { $chip.BackColor = $C.OkBg;   $chip.ForeColor = $C.OkFg }
        'warn' { $chip.BackColor = $C.WarnBg; $chip.ForeColor = $C.WarnFg }
        default { $chip.BackColor = $C.InfoBg; $chip.ForeColor = $C.InfoFg }
    }
}
function New-Flow($padding = (Pad 0 0 0 0)) {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Dock = 'Top'; $f.AutoSize = $true; $f.WrapContents = $true; $f.Padding = $padding
    $f.BackColor = $C.Card
    $f
}
function New-Gap($height) {
    $g = New-Object System.Windows.Forms.Panel; $g.Dock = 'Top'; $g.Height = $height; $g.BackColor = [System.Drawing.Color]::Transparent
    $g
}

# --- window ----------------------------------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = T 'Pen notes' 'Notes du stylo'
$form.AutoScaleMode = 'None'
$form.Size = New-Object System.Drawing.Size((K 1000), (K 760))
$form.MinimumSize = New-Object System.Drawing.Size((K 780), (K 560))
$form.StartPosition = 'CenterScreen'
$form.Font = $font; $form.BackColor = $C.Bg; $form.ForeColor = $C.Text
$ico = Join-Path $PSScriptRoot 'pen.ico'
if (Test-Path $ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }

# Taskbar identity: the window gets its own taskbar button (pen icon, app name) instead of being grouped under
# PowerShell — a Store PowerShell even lends its own logo to every window it hosts. Pinning the button relaunches the
# app, not PowerShell. The small helper is compiled once and cached; any failure leaves the default behaviour.
$taskbarSource = @'
using System;
using System.Runtime.InteropServices;
namespace StyloNeoUi {
    public static class Taskbar {
        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        struct PropertyKey { public Guid fmtid; public uint pid; }
        [StructLayout(LayoutKind.Explicit, Size = 24)]
        struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr ptr; }
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IPropertyStore {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int GetAt(uint index, out PropertyKey key);
            [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
            [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
            [PreserveSig] int Commit();
        }
        [DllImport("shell32.dll")]
        static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [Out, MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
        static readonly Guid AppUserModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        static void Set(IPropertyStore store, uint pid, string value) {
            var key = new PropertyKey { fmtid = AppUserModel, pid = pid };
            var v = new PropVariant { vt = 31, ptr = Marshal.StringToCoTaskMemUni(value) };   // VT_LPWSTR, copied by the store
            try { store.SetValue(ref key, ref v); } finally { Marshal.FreeCoTaskMem(v.ptr); }
        }
        public static bool SetIdentity(IntPtr hwnd, string id, string relaunchCommand, string iconResource, string displayName) {
            var iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            IPropertyStore store;
            if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) != 0 || store == null) return false;
            try {
                Set(store, 2, relaunchCommand);   // RelaunchCommand
                Set(store, 3, iconResource);      // RelaunchIconResource
                Set(store, 4, displayName);       // RelaunchDisplayNameResource
                Set(store, 5, id);                // ID, last: the relaunch properties must already be there
                return store.Commit() == 0;
            } finally { Marshal.ReleaseComObject(store); }
        }
    }
}
'@
try {
    if (-not ('StyloNeoUi.Taskbar' -as [type])) {
        $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($taskbarSource))).Replace('-', '').Substring(0, 12)
        $dll = Join-Path $env:LOCALAPPDATA "stylo-neo-notes\ui\taskbar-$hash.dll"
        if (-not (Test-Path $dll)) {
            New-Item -ItemType Directory -Force (Split-Path $dll) | Out-Null
            Add-Type -TypeDefinition $taskbarSource -OutputAssembly $dll -OutputType Library
        }
        if (-not ('StyloNeoUi.Taskbar' -as [type])) { Add-Type -Path $dll }
    }
    $relaunch = "`"$(Join-Path $env:windir 'System32\conhost.exe')`" --headless `"$Pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($env:STYLO_NEO_CONFIG) { $relaunch += " -Config `"$env:STYLO_NEO_CONFIG`"" }
    $form.Add_HandleCreated({
        try { $script:taskbarSet = [StyloNeoUi.Taskbar]::SetIdentity($form.Handle, 'StyloNeoNotes.PenNotes', $relaunch, "$ico,0", $form.Text) } catch { }
    })
} catch { }

# Header: icon, title, status chips, refresh.
$header = New-Object System.Windows.Forms.TableLayoutPanel
$header.Dock = 'Top'; $header.AutoSize = $true; $header.BackColor = $C.Card; $header.Padding = Pad 20 12 16 12
$header.ColumnCount = 3; $header.RowCount = 1
[void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
[void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
[void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$header.Add_Paint({ param($s, $e) $e.Graphics.DrawLine((New-Object System.Drawing.Pen($C.Border)), 0, $s.Height - 1, $s.Width, $s.Height - 1) })
# Left: logo, title, subtitle.
$brand = New-Object System.Windows.Forms.FlowLayoutPanel
$brand.AutoSize = $true; $brand.WrapContents = $false; $brand.BackColor = $C.Card; $brand.Margin = Pad 0 0 0 0
$logo = New-Object System.Windows.Forms.PictureBox
$logo.Size = New-Object System.Drawing.Size((K 40), (K 40)); $logo.SizeMode = 'Zoom'; $logo.Margin = Pad 0 2 12 0
$png = Join-Path $PSScriptRoot 'pen.png'
if (Test-Path $png) { $logo.Image = [System.Drawing.Image]::FromFile($png) }
elseif (Test-Path $ico) { $logo.Image = (New-Object System.Drawing.Icon($ico, 48, 48)).ToBitmap() }
$titles = New-Object System.Windows.Forms.FlowLayoutPanel
$titles.AutoSize = $true; $titles.FlowDirection = 'TopDown'; $titles.WrapContents = $false; $titles.BackColor = $C.Card
$titles.Margin = Pad 0 0 0 0
$lblAppTitle = New-Object System.Windows.Forms.Label
$lblAppTitle.Text = T 'Pen notes' 'Notes du stylo'; $lblAppTitle.Font = $fontTitle; $lblAppTitle.AutoSize = $true
$lblAppTitle.ForeColor = $C.Text; $lblAppTitle.Margin = Pad 0 0 0 0
$lblAppSub = New-Object System.Windows.Forms.Label
$lblAppSub.Text = T 'Neo smartpen → Obsidian' 'Stylo Neo → Obsidian'; $lblAppSub.Font = $fontSmall; $lblAppSub.AutoSize = $true
$lblAppSub.ForeColor = $C.Muted; $lblAppSub.Margin = Pad 1 0 0 0
$titles.Controls.AddRange(@($lblAppTitle, $lblAppSub))
$brand.Controls.AddRange(@($logo, $titles))
# Right: status chips and refresh (they wrap under each other when the window is narrow).
$top = New-Object System.Windows.Forms.FlowLayoutPanel
$top.AutoSize = $true; $top.WrapContents = $false; $top.BackColor = $C.Card; $top.Anchor = 'Right'
$top.Margin = Pad 12 6 0 0
$lblAgenda  = New-Chip (T 'Calendar …' 'Agenda …')
$lblPending = New-Chip (T 'Pages pending …' 'Pages en attente …')
$lblFixed   = New-Chip (T 'Notes corrected …' 'Notes corrigées …')
$btnLogin   = New-Button (T 'Sign in again' 'Se reconnecter') 'ghost'; $btnLogin.Visible = $false
$btnRefresh = New-Button (T '⟳  Refresh' '⟳  Actualiser') 'ghost'
foreach ($b in @($btnLogin, $btnRefresh)) { $b.Margin = Pad 0 0 4 0 }
$top.Controls.AddRange(@($lblAgenda, $btnLogin, $lblPending, $lblFixed, $btnRefresh))
$header.Controls.Add($brand, 0, 0)
$header.Controls.Add($top, 2, 0)

# Navigation: two segments over a tab control whose own headers are hidden.
$nav = New-Object System.Windows.Forms.FlowLayoutPanel
$nav.Dock = 'Top'; $nav.AutoSize = $true; $nav.Padding = Pad 20 14 20 0; $nav.BackColor = $C.Bg
$segSync  = New-Button (T 'Pen sync' 'Synchro du stylo')
$segPaste = New-Button (T 'Paste notes or a transcript' 'Coller des notes ou une transcription')
foreach ($s in @($segSync, $segPaste)) { $s.Padding = Pad 16 7 16 7; $s.Margin = Pad 0 0 6 0 }
$nav.Controls.AddRange(@($segSync, $segPaste))

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'; $tabs.Appearance = 'FlatButtons'; $tabs.ItemSize = New-Object System.Drawing.Size(0, 1)
$tabs.SizeMode = 'Fixed'; $tabs.Padding = New-Object System.Drawing.Point(0, 0)
$tabSync  = New-Object System.Windows.Forms.TabPage; $tabSync.Text = T 'Pen sync' 'Synchro du stylo'
$tabPaste = New-Object System.Windows.Forms.TabPage; $tabPaste.Text = T 'Paste notes or a transcript' 'Coller des notes ou une transcription'
foreach ($t in @($tabSync, $tabPaste)) { $t.BackColor = $C.Bg; $t.Font = $font; $t.Padding = Pad 20 12 20 18; $t.UseVisualStyleBackColor = $false }
function Set-Segments {
    foreach ($pair in @(@($segSync, $tabSync), @($segPaste, $tabPaste))) {
        $on = $tabs.SelectedTab -eq $pair[1]
        $pair[0].BackColor = if ($on) { $C.Accent } else { $C.Card }
        $pair[0].ForeColor = if ($on) { [System.Drawing.Color]::White } else { $C.Text }
        $pair[0].Font = if ($on) { $fontBold } else { $font }
        $pair[0].FlatAppearance.BorderSize = if ($on) { 0 } else { 1 }
        $pair[0].FlatAppearance.MouseOverBackColor = if ($on) { $C.AccentH } else { $C.Hover }
    }
}
$segSync.Add_Click({ $tabs.SelectedTab = $tabSync })
$segPaste.Add_Click({ $tabs.SelectedTab = $tabPaste })
$tabs.Add_SelectedIndexChanged({ Set-Segments })

# --- "Pen sync" page -------------------------------------------------------------------------------------------
$cardSync = New-Card; $cardSync.Dock = 'Top'; $cardSync.AutoSize = $true
$lblSyncTitle = New-Label (T 'Sync the pen' 'Synchroniser le stylo') 'h2'; $lblSyncTitle.Dock = 'Top'
$actions = New-Flow
$cmbNotebook = New-Object System.Windows.Forms.ComboBox
$cmbNotebook.DropDownStyle = 'DropDownList'; $cmbNotebook.Width = (K 190)
$cmbNotebook.Margin = Pad 0 8 8 4
[void]$cmbNotebook.Items.Add((T 'All notebooks' 'Tous les carnets')); $cmbNotebook.SelectedIndex = 0
$btnSync  = New-Button (T 'Sync + conversion' 'Synchro + conversion') 'primary'
$chkErase = New-Object System.Windows.Forms.CheckBox
$chkErase.Text = T 'Erase from the pen after the sync' 'Effacer du stylo après la synchro'
$chkErase.AutoSize = $true; $chkErase.Checked = $false; $chkErase.Margin = Pad 6 10 12 4; $chkErase.BackColor = $C.Card
$tips = New-Object System.Windows.Forms.ToolTip
$tips.SetToolTip($chkErase, (T 'Only notebooks fully received, and only once saved on the PC. Makes the next syncs faster.' `
                               'Seulement les carnets reçus en entier, et seulement une fois enregistrés sur le PC. Les synchros suivantes sont plus rapides.'))
$actions.Controls.AddRange(@($cmbNotebook, $btnSync, $chkErase))
$actions2 = New-Flow (Pad 0 4 0 0)
$btnConvert = New-Button (T 'Convert without sync' 'Convertir sans synchro')
$btnFix     = New-Button (T 'Integrate my corrections' 'Intégrer mes corrections')
$btnStop    = New-Button (T 'Stop' 'Arrêter') 'danger'; $btnStop.Enabled = $false
$actions2.Controls.AddRange(@($btnConvert, $btnFix, $btnStop))
$links = New-Flow (Pad 0 6 0 0)
$btnToday   = New-Button (T "Today's note ↗" 'Note du jour ↗') 'ghost'
$btnLog     = New-Button (T 'Conversion log ↗' 'Journal des conversions ↗') 'ghost'
$btnGoPaste = New-Button (T 'Paste notes or a transcript →' 'Coller des notes ou une transcription →') 'ghost'
$links.Controls.AddRange(@($btnToday, $btnLog, $btnGoPaste))
$cardSync.Controls.Add($links); $cardSync.Controls.Add($actions2); $cardSync.Controls.Add($actions); $cardSync.Controls.Add($lblSyncTitle)

$lblLog = New-Label (T 'Activity' 'Activité') 'h2'; $lblLog.Dock = 'Top'; $lblLog.Padding = Pad 2 14 0 6
$logFrame = New-Object System.Windows.Forms.Panel
$logFrame.Dock = 'Fill'; $logFrame.BackColor = $C.LogBg; $logFrame.Padding = Pad 14 12 6 12
Set-Round $logFrame 10
$out = New-Object System.Windows.Forms.TextBox
$out.Multiline = $true; $out.ReadOnly = $true; $out.ScrollBars = 'Vertical'; $out.Dock = 'Fill'
$out.Font = New-Object System.Drawing.Font($monoName, 10); $out.BackColor = $C.LogBg; $out.ForeColor = $C.LogFg
$out.BorderStyle = 'None'; $out.WordWrap = $true
$logFrame.Controls.Add($out)
$tabSync.Controls.Add($logFrame); $tabSync.Controls.Add($lblLog); $tabSync.Controls.Add($cardSync)

# --- "Paste" page ----------------------------------------------------------------------------------------------
$cardPaste = New-Card; $cardPaste.Dock = 'Fill'
$lblPasteTitle = New-Label (T 'Notes or a meeting transcript typed elsewhere' 'Notes ou transcription de réunion tapées ailleurs') 'h2'
$lblPasteTitle.Dock = 'Top'
$pasteTop = New-Flow
$rbNotes = New-Object System.Windows.Forms.RadioButton
$rbNotes.Text = T 'Notes' 'Notes'; $rbNotes.AutoSize = $true; $rbNotes.Checked = $true; $rbNotes.Margin = Pad 0 9 10 4
$rbTranscript = New-Object System.Windows.Forms.RadioButton
$rbTranscript.Text = T 'Meeting transcript' 'Transcription de réunion'; $rbTranscript.AutoSize = $true; $rbTranscript.Margin = Pad 0 9 22 4
$dtDate = New-Object System.Windows.Forms.DateTimePicker
$dtDate.Format = 'Long'; $dtDate.Width = (K 290); $dtDate.Margin = Pad 0 6 8 4
$pasteTop.Controls.AddRange(@($rbNotes, $rbTranscript, $dtDate))
$pasteMeeting = New-Flow (Pad 0 6 0 0)
$lblMeeting = New-Label (T 'Meeting' 'Réunion') 'muted'; $lblMeeting.Margin = Pad 0 10 8 4
$cmbMeeting = New-Object System.Windows.Forms.ComboBox
$cmbMeeting.DropDownStyle = 'DropDownList'; $cmbMeeting.Width = (K 600); $cmbMeeting.Margin = Pad 0 6 8 4
$pasteMeeting.Controls.AddRange(@($lblMeeting, $cmbMeeting))
$pasteFree = New-Flow (Pad 0 2 0 0)
$lblTitle = New-Label (T 'Title' 'Titre') 'muted'; $lblTitle.Margin = Pad 0 10 8 4
$txtTitle = New-Object System.Windows.Forms.TextBox; $txtTitle.Width = (K 360); $txtTitle.Margin = Pad 0 6 14 4; $txtTitle.BorderStyle = 'FixedSingle'
$lblStart = New-Label (T 'Start (HH:MM)' 'Début (HH:MM)') 'muted'; $lblStart.Margin = Pad 0 10 8 4
$txtStart = New-Object System.Windows.Forms.TextBox; $txtStart.Width = (K 70); $txtStart.Margin = Pad 0 6 8 4; $txtStart.BorderStyle = 'FixedSingle'
$pasteFree.Controls.AddRange(@($lblTitle, $txtTitle, $lblStart, $txtStart))
$pasteBottom = New-Flow (Pad 0 10 0 0); $pasteBottom.Dock = 'Bottom'
$btnFile  = New-Button (T 'File it in Obsidian' 'Ranger dans Obsidian') 'primary'
$lblPaste = New-Label '' 'muted'; $lblPaste.Margin = Pad 8 12 0 4
$pasteBottom.Controls.AddRange(@($btnFile, $lblPaste))
$txtFrame = New-Object System.Windows.Forms.Panel
$txtFrame.Dock = 'Fill'; $txtFrame.BackColor = $C.Border; $txtFrame.Padding = Pad 1 1 1 1
$txtPaste = New-Object System.Windows.Forms.TextBox
$txtPaste.Multiline = $true; $txtPaste.ScrollBars = 'Vertical'; $txtPaste.Dock = 'Fill'; $txtPaste.AcceptsReturn = $true
$txtPaste.Font = $font; $txtPaste.MaxLength = 0; $txtPaste.BorderStyle = 'None'; $txtPaste.BackColor = $C.Card
$txtPaste.PlaceholderText = T 'Paste the text here (Ctrl+V)…' 'Collez le texte ici (Ctrl+V)…'
$txtFrame.Controls.Add($txtPaste)
$gapText = New-Gap 10
$cardPaste.Controls.Add($txtFrame); $cardPaste.Controls.Add($gapText); $cardPaste.Controls.Add($pasteBottom)
$cardPaste.Controls.Add($pasteFree); $cardPaste.Controls.Add($pasteMeeting); $cardPaste.Controls.Add($pasteTop)
$cardPaste.Controls.Add($lblPasteTitle)
$tabPaste.Controls.Add($cardPaste)

$tabs.TabPages.AddRange(@($tabSync, $tabPaste))
$form.Controls.Add($tabs)
$form.Controls.Add($nav)
$form.Controls.Add($header)
Set-Segments
# The sync card is as tall as its content (flows wrap when the window narrows).
function Set-CardHeight {
    $h = $cardSync.Padding.Vertical
    foreach ($c in $cardSync.Controls) { if ($c.Visible) { $h += $c.Height + $c.Margin.Vertical } }
    if ($cardSync.Height -ne $h) { $cardSync.Height = $h }
}
$cardSync.AutoSize = $false
$cardSync.Add_Layout({ Set-CardHeight })
$form.Add_Resize({ Set-CardHeight; $cardSync.Invalidate(); $cardPaste.Invalidate() })

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
            Set-Chip $lblPending $(if ($s.pending -gt 0) { 'warn' } else { 'info' })
            Set-Chip $lblFixed $(if ($s.corrected -gt 0) { 'warn' } else { 'info' })
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
        Set-Chip $lblAgenda $(if ($code -eq 0) { 'ok' } else { 'warn' })
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
            # The only console the app ever shows, on purpose: the pen password is typed there, never in the window.
            $syncArgs = "`$Host.UI.RawUI.WindowTitle = '$(T 'Pen password' 'Mot de passe du stylo')'; " + $syncArgs
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
    # The sign-in command opens its own browser window: it runs without any console window.
    [void]$script:bg.Add((Start-Proc $Pwsh @('-NoProfile', '-Command', $cfg.agenda.login) { param($code, $text) Update-Status } -workDir $ConfigDir))
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
            if ($cmbMeeting.SelectedIndex -lt 0) { $cmbMeeting.SelectedIndex = 0 }
            $lblPaste.Text = if ($script:events.Count) { T "$($script:events.Count) meeting(s) on this day." "$($script:events.Count) réunion(s) ce jour-là." } `
                             else { T 'No meeting on this day.' 'Aucune réunion ce jour-là.' }
        } catch {
            if ($cmbMeeting.SelectedIndex -lt 0) { $cmbMeeting.SelectedIndex = 0 }
            $lblPaste.Text = T 'Calendar unavailable: type a title.' 'Agenda indisponible : saisissez un titre.'
        }
    } -workDir $ConfigDir))
}
$dtDate.Add_ValueChanged({ Update-Meetings })
$btnGoPaste.Add_Click({ $tabs.SelectedTab = $tabPaste; $txtPaste.Focus() })
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
                foreach ($tab in @($tabSync, $tabPaste)) {   # screenshots of both tabs next to the output file
                    $tabs.SelectedTab = $tab; $form.Refresh()
                    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
                    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
                    $bmp.Save(($SelfTestOut -replace '\.txt$', '') + "-$($tabs.SelectedIndex).png"); $bmp.Dispose()
                }
                $state = "$($lblAgenda.Text) | $($lblPending.Text) | $($lblFixed.Text) | K=$K | selected: [$($cmbNotebook.Text)] [$($cmbMeeting.Text)] | notebooks: " +
                         (($cmbNotebook.Items | ForEach-Object { $_ }) -join ', ') + " | meetings: $($cmbMeeting.Items.Count - 1)" +
                         "`r`n$($script:pasteState) | $($lblPaste.Text)"
                $state += " | taskbar identity: $($script:taskbarSet)"
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
