# Creates (or recreates) the desktop shortcut that opens the Pen notes window (app.ps1): pen sync, conversion into
# Obsidian notes, integration of your corrections. -Console makes it open the console version (run.ps1) instead.
#
#   pwsh -File scripts\install-shortcut.ps1 [-Name "Pen notes"] [-Config C:\path\to\config.toml] [-Console]
#
# -Config bakes a configuration file into the shortcut (otherwise the scripts look for STYLO_NEO_CONFIG,
# config.toml at the repository root, then %APPDATA%\stylo-neo-notes\config.toml).
#
# The window is started through the Windows console host in headless mode (conhost --headless): PowerShell gets a
# console without any window. "pwsh -WindowStyle Hidden" is not enough: when Windows Terminal is the default
# terminal (Windows 11), a Terminal window opens before PowerShell can hide anything, and stays open.

param(
    [string]$Name = 'Pen notes',
    [string]$Config,
    [switch]$Console
)
$ErrorActionPreference = 'Stop'
$target  = Join-Path $PSScriptRoot $(if ($Console) { 'run.ps1' } else { 'app.ps1' })
$pwsh    = (Get-Command pwsh -ErrorAction Stop).Source
$conhost = Join-Path $env:windir 'System32\conhost.exe'
$desktop = [Environment]::GetFolderPath('Desktop')     # follows a Desktop redirected to a synced folder
$link    = Join-Path $desktop "$Name.lnk"

$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$target`""
if ($Config) { $arguments += " -Config `"$((Resolve-Path $Config).Path)`"" }

$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($link)
if ($Console) {
    $s.TargetPath = $pwsh; $s.Arguments = $arguments
} elseif (Test-Path $conhost) {
    $s.TargetPath = $conhost; $s.Arguments = "--headless `"$pwsh`" $arguments"
} else {
    $s.TargetPath = $pwsh; $s.Arguments = "-WindowStyle Hidden $arguments"   # older Windows: brief console flash
}
$s.WorkingDirectory = $PSScriptRoot
$s.Description      = 'Neo smartpen sync and conversion into Obsidian notes'
$s.IconLocation     = "$(Join-Path $PSScriptRoot 'pen.ico'),0"   # drawn by icon.py
$s.Save()
Write-Host "Shortcut created: $link"
