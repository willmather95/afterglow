[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build.ps1')
$build = Join-Path $PSScriptRoot 'build'
$package = Join-Path $build ('package-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $package
try {
 Copy-Item -LiteralPath (Join-Path $build 'Afterglow.exe') -Destination $package
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $package
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\LICENSE') -Destination $package
 $zip = Join-Path $build 'Afterglow-Windows-x64.zip'
 Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip -Force
 $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
 "$sha  Afterglow-Windows-x64.zip" | Set-Content -Encoding ASCII -LiteralPath "$zip.sha256"
} finally { Remove-Item -LiteralPath $package -Recurse -Force }
