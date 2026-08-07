# Builds both probe binaries. Run from a normal (non-elevated) PowerShell.
#
#   .\scripts\build.ps1
#
# Requires Visual Studio 2022 with the "Desktop development with C++"
# workload, which brings CMake and the Windows SDK.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $root "build"

Write-Host "Configuring..." -ForegroundColor Cyan
cmake -S $root -B $buildDir -A x64

Write-Host "Building..." -ForegroundColor Cyan
cmake --build $buildDir --config Release

$out = Join-Path $buildDir "out"
Write-Host ""
Write-Host "Built into $out" -ForegroundColor Green
Get-ChildItem $out | Format-Table Name, Length

Write-Host @"

Next: register the source DLL, then run the host.

  Per-user   (no UAC)   .\scripts\register-hkcu.ps1
  Machine    (one UAC)  .\scripts\register-hklm.ps1
  Then                  $out\MeoProbeHost.exe

Probe 3 is answered by which of those two makes the host's Start() succeed.
"@ -ForegroundColor Yellow
