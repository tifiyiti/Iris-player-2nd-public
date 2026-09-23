<#
.SYNOPSIS
  One-shot release build: Windows portable ZIP + Android split/universal APKs.
.DESCRIPTION
  A thin orchestrator around build-windows-release.ps1 and
  build-android-release.ps1. It produces exactly the distributable set:

    IRIS-windows-v<version>.zip
    IRIS-android-arm64-v8a-v<version>.apk
    IRIS-android-armeabi-v7a-v<version>.apk
    IRIS-android-x86_64-v<version>.apk
    IRIS-android-universal-v<version>.apk   (unless -NoUniversal)

  The installer / MSIX are intentionally NOT built here; use
  build-windows-release.ps1 for the full Windows set. Codegen runs once, then
  both workers are invoked with -SkipCodegen.
.PARAMETER SkipWindows
  Only build the Android APKs.
.PARAMETER SkipAndroid
  Only build the Windows portable ZIP.
.PARAMETER SkipCodegen
  Skip "flutter pub get" + build_runner. Use when generated code is fresh.
.PARAMETER NoUniversal
  Do not build the universal (all-ABI) APK.
#>
[CmdletBinding()]
param(
    [switch]$SkipWindows,
    [switch]$SkipAndroid,
    [switch]$SkipCodegen,
    [switch]$NoUniversal
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsScript = Join-Path $PSScriptRoot "build-windows-release.ps1"
$androidScript = Join-Path $PSScriptRoot "build-android-release.ps1"

Push-Location $repoRoot
try {
    # --- Version (single source of truth: pubspec.yaml) -------------------
    $rawVersion = (Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
    $version = $rawVersion.Split('+')[0]
    Write-Host "IRIS version: $version" -ForegroundColor Cyan

    # --- Codegen once for both workers -----------------------------------
    if (-not $SkipCodegen) {
        Write-Host "Generating code..." -ForegroundColor Cyan
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
        dart run build_runner build --delete-conflicting-outputs
        if ($LASTEXITCODE -ne 0) { throw "build_runner failed" }
    }

    if (-not $SkipWindows) {
        & $windowsScript -SkipCodegen -SkipInstaller -SkipMsix
        if ($LASTEXITCODE -ne 0) { throw "build-windows-release.ps1 failed" }
    }

    if (-not $SkipAndroid) {
        & $androidScript -SkipCodegen -NoUniversal:$NoUniversal
        if ($LASTEXITCODE -ne 0) { throw "build-android-release.ps1 failed" }
    }

    Write-Host "Release artifacts are in $repoRoot" -ForegroundColor Green
} finally {
    Pop-Location
}
