# Builds a self-contained exe (no .NET needed on the machine that runs it) into dist\.
# Run on a machine with the .NET 8 SDK and the NeoLAB SDK (setup.ps1), then copy dist\ wherever you need it.
# Usage: powershell -ExecutionPolicy Bypass -File pen/publish.ps1
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'src\StyloNeo\StyloNeo.csproj'
$output  = Join-Path $PSScriptRoot 'dist'

if (-not (Test-Path (Join-Path $PSScriptRoot 'vendor\Windows-SDK2.0'))) {
    throw "NeoLAB SDK missing: run setup.ps1 first"
}
dotnet publish $project -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $output
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }
Write-Host "Self-contained exe ready: $(Join-Path $output 'stylo-neo.exe')"
