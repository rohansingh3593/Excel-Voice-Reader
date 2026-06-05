<#
.SYNOPSIS
  Repairs stale Flutter Windows generated files and build cache.

.DESCRIPTION
  Flutter generates windows/flutter/ephemeral and build/windows locally. If a
  repository is moved, copied, or partially cleaned, Visual Studio/MSBuild can
  keep stale absolute paths to missing cpp_client_wrapper files such as
  flutter_engine.cc and flutter_view_controller.cc. This script removes the
  generated Windows artifacts, restores packages, and optionally launches the
  Windows app so Flutter regenerates the missing files from the installed SDK.

.PARAMETER Run
  Launch the app on Windows after repairing generated files.
#>
param(
  [switch]$Run
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter was not found on PATH. Install Flutter and run this script from a Flutter-enabled terminal.'
}

Write-Host 'Repairing Flutter Windows generated files...'

$generatedPaths = @(
  'build/windows',
  'windows/flutter/ephemeral'
)

foreach ($path in $generatedPaths) {
  if (Test-Path $path) {
    Write-Host "Removing $path"
    Remove-Item -Recurse -Force $path
  }
}

flutter clean
flutter pub get
flutter config --enable-windows-desktop

if ($Run) {
  flutter run -d windows
} else {
  Write-Host 'Repair complete. Run `flutter run -d windows` to launch the app.'
}
