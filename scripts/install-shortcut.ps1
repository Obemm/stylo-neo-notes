# Creates (or recreates) the desktop shortcut that runs run.ps1: pen sync, then conversion into Obsidian notes
# (or integration of your corrections).
#
#   pwsh -File scripts\install-shortcut.ps1 [-Name "Pen notes"] [-Config C:\path\to\config.toml]
#
# -Config bakes a configuration file into the shortcut (otherwise run.ps1 looks for STYLO_NEO_CONFIG,
# config.toml at the repository root, then %APPDATA%\stylo-neo-notes\config.toml).

param(
    [string]$Name = 'Pen notes',
    [string]$Config
)
$ErrorActionPreference = 'Stop'
$run     = Join-Path $PSScriptRoot 'run.ps1'
$pwsh    = (Get-Command pwsh -ErrorAction Stop).Source
$desktop = [Environment]::GetFolderPath('Desktop')     # follows a Desktop redirected to a synced folder
$link    = Join-Path $desktop "$Name.lnk"

$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$run`""
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
