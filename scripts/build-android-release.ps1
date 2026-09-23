<#
.SYNOPSIS
  Build the Android release APKs with versioned file names.
.DESCRIPTION
  Reads the version from pubspec.yaml (the single source of truth), strips the
  +build suffix so the name matches the release tag (vMAJOR.MINOR.PATCH), then
  produces the following in the repository root:

    IRIS-android-arm64-v8a-v<version>.apk
    IRIS-android-armeabi-v7a-v<version>.apk
    IRIS-android-x86_64-v<version>.apk
    IRIS-android-universal-v<version>.apk

  The project defines two product flavors (nini22p / tifi7), so a --flavor is
  mandatory; this script defaults to tifi7, which is what gets published.
.PARAMETER SkipCodegen
  Skip "flutter pub get" + build_runner. Use when generated code is fresh.
.PARAMETER NoUniversal
  Do not build the universal (all-ABI) APK; only the three split APKs.
.PARAMETER Flavor
  Android product flavor. Defaults to tifi7.
#>
[CmdletBinding()]
param(
    [switch]$SkipCodegen,
    [switch]$NoUniversal,
    [string]$Flavor = "tifi7"
)

$ErrorActionPreference = "Stop"

function Show-Artifact {
    param([string]$Path)
    $mb = [math]::Round((Get-Item -LiteralPath $Path).Length / 1MB, 1)
    Write-Host ("  -> {0} ({1} MB)" -f (Split-Path -Leaf $Path), $mb) -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    # --- Version (single source of truth: pubspec.yaml) -------------------
    $rawVersion = (Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
    $version = $rawVersion.Split('+')[0]
    Write-Host "IRIS version: $version (flavor: $Flavor)" -ForegroundColor Cyan

    if (-not $SkipCodegen) {
        Write-Host "Generating code..." -ForegroundColor Cyan
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
        dart run build_runner build --delete-conflicting-outputs
        if ($LASTEXITCODE -ne 0) { throw "build_runner failed" }
    }

    $apkDir = Join-Path $repoRoot "build\app\outputs\flutter-apk"

    # --- Split APKs -------------------------------------------------------
    Write-Host "Building split APKs..." -ForegroundColor Cyan
    flutter build apk --flavor $Flavor --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk --split-per-abi failed" }

    foreach ($abi in @("arm64-v8a", "armeabi-v7a", "x86_64")) {
        # Flutter names split outputs app-<abi>-<flavor>-release.apk.
        $source = Join-Path $apkDir "app-$abi-$Flavor-release.apk"
        if (-not (Test-Path $source)) { throw "Expected APK not found: $source" }
        $target = Join-Path $repoRoot "IRIS-android-$abi-v$version.apk"
        Copy-Item -Path $source -Destination $target -Force
        Show-Artifact $target
    }

    # --- Universal APK ----------------------------------------------------
    if (-not $NoUniversal) {
        Write-Host "Building universal APK..." -ForegroundColor Cyan
        flutter build apk --flavor $Flavor
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
        $source = Join-Path $apkDir "app-$Flavor-release.apk"
        if (-not (Test-Path $source)) { throw "Expected APK not found: $source" }
        $target = Join-Path $repoRoot "IRIS-android-universal-v$version.apk"
        Copy-Item -Path $source -Destination $target -Force
        Show-Artifact $target
    }

    Write-Host "Android release artifacts are in $repoRoot" -ForegroundColor Green
} finally {
    Pop-Location
}
