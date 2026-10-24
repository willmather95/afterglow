# Disposable runner only: never kills or replaces a user's app.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:OS -ne 'Windows_NT') { throw 'Use a disposable Windows Actions runner.' }
$build = Join-Path $PSScriptRoot 'build'
$zip = Join-Path $build 'Afterglow-Windows-x64.zip'
$expected = (Get-Content -LiteralPath "$zip.sha256" -Raw).Split(' ')[0]
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) { throw 'Package hash mismatch.' }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('afterglow-package-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
$fixture = $null
try {
 Expand-Archive -LiteralPath $zip -DestinationPath $scratch
 $names = @(Get-ChildItem -LiteralPath $scratch -File | Sort-Object Name | ForEach-Object Name)
 if (($names -join ',') -cne 'Afterglow.exe,LICENSE,README.md') { throw 'Unexpected package files.' }
 $exe = Join-Path $scratch 'Afterglow.exe'
 function Run-Owned([string[]] $Arguments) {
  $child = Start-Process -FilePath $exe -ArgumentList $Arguments -Wait -PassThru
  if ($child.ExitCode -ne 0) { throw "Packaged check failed: $($Arguments[0]), $($child.ExitCode)" }
 }
 Run-Owned @('--self-test')
 $renders = Join-Path $build 'ui'
 Run-Owned @('--ui-smoke', "`"$renders`"")
 Run-Owned @('--overlay-smoke', "`"$renders`"")
 Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class OwnedOverlayCheck { [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr handle); }'
 $record = Join-Path $scratch 'owned-handles.txt'
 $fixture = Start-Process -FilePath $exe -ArgumentList @('--overlay-fixture', "`"$record`"") -PassThru
 for ($attempt=0; $attempt -lt 60 -and -not (Test-Path -LiteralPath $record); $attempt++) { Start-Sleep -Milliseconds 100 }
 if (-not (Test-Path -LiteralPath $record)) { throw 'Owned overlay fixture did not report windows.' }
 $handles = @(Get-Content -LiteralPath $record | ForEach-Object { [IntPtr]([long]$_) })
 if ($handles.Count -eq 0) { throw 'Owned overlay fixture returned no windows.' }
 foreach ($handle in $handles) { if (-not [OwnedOverlayCheck]::IsWindow($handle)) { throw 'Overlay fixture window missing before termination.' } }
 Stop-Process -Id $fixture.Id -Force
 $fixture.WaitForExit()
 foreach ($handle in $handles) { if ([OwnedOverlayCheck]::IsWindow($handle)) { throw 'Overlay survived its owning process.' } }
 'PASS native overlay windows disappear on forced owned-process exit; no display settings touched.' | Set-Content -Encoding UTF8 (Join-Path $renders 'crash-removal.txt')
 if (@(Get-ChildItem $renders -Filter '*.png').Count -lt 2) { throw 'Native UI screenshots missing.' }
 Write-Host 'PASS extracted package, own UI, native overlay styles and process-exit cleanup'
} finally {
 if ($null -ne $fixture -and -not $fixture.HasExited) { Stop-Process -Id $fixture.Id -Force }
 Remove-Item -LiteralPath $scratch -Recurse -Force
}
