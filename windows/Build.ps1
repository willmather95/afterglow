[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build Afterglow for Windows on Windows.' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows x64 .NET Framework compiler unavailable.' }
$build = Join-Path $PSScriptRoot 'build'
$null = New-Item -ItemType Directory -Force -Path $build
$sources = @(Get-ChildItem (Join-Path $PSScriptRoot 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object FullName)
$sources += @(Get-ChildItem (Join-Path $PSScriptRoot 'tests') -Filter '*.cs' | Sort-Object Name | ForEach-Object FullName)
$output = Join-Path $build 'Afterglow.exe'
$arguments = @('/nologo','/target:winexe','/platform:x64','/optimize+','/warnaserror+', '/main:Afterglow.Windows.Program',"/out:$output", "/win32manifest:$(Join-Path $PSScriptRoot 'src\app.manifest')", "/win32icon:$(Join-Path $PSScriptRoot 'assets\Afterglow.ico')")
$arguments += @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Runtime.Serialization.dll' | ForEach-Object { "/reference:$_" })
& $compiler @arguments @sources
if ($LASTEXITCODE -ne 0) { throw "C# compiler failed: $LASTEXITCODE" }
$test = Start-Process -FilePath $output -ArgumentList '--self-test' -Wait -PassThru -RedirectStandardOutput (Join-Path $build 'tests.txt') -RedirectStandardError (Join-Path $build 'tests.stderr')
Get-Content -LiteralPath (Join-Path $build 'tests.txt')
Get-Content -LiteralPath (Join-Path $build 'tests.stderr')
if ($test.ExitCode -ne 0) { throw "Afterglow tests failed: $($test.ExitCode)" }
