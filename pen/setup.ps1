# Fetches the official NeoLAB Windows SDK at a pinned version into vendor/ (not in Git).
# Usage: powershell -ExecutionPolicy Bypass -File pen/setup.ps1
$ErrorActionPreference = 'Stop'
$commit = 'd9a0ea1'   # v2.6.1, April 2026
$repo   = 'https://github.com/NeoSmartpen/Windows-SDK2.0'
$target = Join-Path $PSScriptRoot 'vendor\Windows-SDK2.0'

if (-not (Test-Path $target)) {
    git clone $repo $target
}
git -C $target fetch --quiet origin
git -C $target checkout --quiet $commit
Write-Host "NeoLAB SDK ready: $target (commit $commit)"
