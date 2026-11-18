# Creates (or recreates) the desktop shortcut that opens the Pen notes window (app.ps1): pen sync, conversion into
# Obsidian notes, integration of your corrections. -Console makes it open the console version (run.ps1) instead.
#
#   pwsh -File scripts\install-shortcut.ps1 [-Name "Pen notes"] [-Config C:\path\to\config.toml] [-Console]
#
# -Config bakes a configuration file into the shortcut (otherwise the scripts look for STYLO_NEO_CONFIG,
# config.toml at the repository root, then %APPDATA%\stylo-neo-notes\config.toml).

param(
    [string]$Name = 'Pen notes',
    [string]$Config,
    [switch]$Console
)
$ErrorActionPreference = 'Stop'
$target  = Join-Path $PSScriptRoot $(if ($Console) { 'run.ps1' } else { 'app.ps1' })
$pwsh    = (Get-Command pwsh -ErrorAction Stop).Source
$desktop = [Environment]::GetFolderPath('Desktop')     # follows a Desktop redirected to a synced folder
$link    = Join-Path $desktop "$Name.lnk"

$hidden    = if ($Console) { '' } else { '-WindowStyle Hidden ' }   # the window has no console behind it
$arguments = "-NoProfile $hidden-ExecutionPolicy Bypass -File `"$target`""
if ($Config) { $arguments += " -Config `"$((Resolve-Path $Config).Path)`"" }

$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($link)
$s.TargetPath       = $pwsh
$s.Arguments        = $arguments
$s.WorkingDirectory = $PSScriptRoot
$s.Description      = 'Neo smartpen sync and conversion into Obsidian notes'
$s.IconLocation     = "$(Join-Path $PSScriptRoot 'pen.ico'),0"   # drawn by icon.py
$s.Save()
Write-Host "Shortcut created: $link"
