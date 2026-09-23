#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
  Pre-install guard for Android APKs: prevents accidental versionCode
  downgrade (+ uninstall + data loss) and detects split→universal mix.

  Rules (per user spec):
    - downgrade: pending < installed  -> must warn (would require uninstall)
    - excessive jump: pending - installed > 600 -> warn (split's +2000/+1000 is split, normal commit is +1)

  Usage:
    pwsh scripts/check-apk-install.ps1 [path/to.apk]
    pwsh scripts/check-apk-install.ps1 -ApkPath build/app/outputs/flutter-apk/app-tifi7-debug.apk
  Exit 0 = safe, 1 = blocked (or adb not available but APK parsed).

  Notes:
    - Reads pending versionCode via: aapt dump badging (preferred) -> file-name fallback
      (arm64=+2000, armeabi-v7a/x86_64=+1000 heuristic per AGENTS.md:469)
      -> version.properties base fallback
    - Reads installed versionCode via: adb shell dumpsys package <appId>
      (queries both iris and iris.tifi7 flavors)
    - Never modifies files. Pure read/inspect.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$ApkPath = "build/app/outputs/flutter-apk/app-tifi7-debug.apk",

  [string]$AppId = "",
  [int]$ExcessiveThreshold = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-VersionPropertiesBase {
  $p = "android/version.properties"
  if (Test-Path -LiteralPath $p) {
    foreach ($line in Get-Content -LiteralPath $p) {
      if ($line -match '^\s*versionCode\s*=\s*(\d+)\s*$') { return [int]$Matches[1] }
    }
  }
  return $null
}

function Get-PendingVersionCode {
  param([string]$Path)
  # 1) aapt dump badging (most accurate)
  $aaptCandidates = @(
    "$env:ANDROID_HOME\build-tools\*\aapt.exe",
    "$env:ANDROID_SDK_ROOT\build-tools\*\aapt.exe",
    "aapt"
  )
  foreach ($pat in $aaptCandidates) {
    try {
      $aapt = $null
      if ($pat -like "*`**`*") {
        $hits = Get-ChildItem -Path $pat -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($hits) { $aapt = $hits.FullName }
      } elseif (Get-Command $pat -ErrorAction SilentlyContinue) {
        $aapt = $pat
      }
      if (-not $aapt -or -not (Test-Path -LiteralPath $Path)) { continue }
      $out = & $aapt dump badging $Path 2>$null | Select-String "versionCode"
      if ($out -and $out.ToString() -match "versionCode='(\d+)'") {
        return [int]$Matches[1]
      }
    } catch { continue }
  }
  # 2) file-name heuristic (split): AGENTS.md:469 arm64 ~ base+2000
  $base = Read-VersionPropertiesBase
  if ($null -ne $base -and (Test-Path -LiteralPath $Path)) {
    $name = Split-Path -Leaf $Path
    if ($name -match "arm64") { return $base + 2000 }
    if ($name -match "armeabi|arm-v7a|x86_64") { return $base + 1000 }
    return $base
  }
  return $base
}

function Get-InstalledVersionCode {
  param([string]$AppIdHint)
  $ids = @()
  if ($AppIdHint) { $ids += $AppIdHint }
  $ids += @("iris.tifi7", "iris", "com.example.iris")
  # also probe via adb shell pm list packages
  try {
    $list = & adb shell pm list packages 2>$null
    foreach ($line in $list) {
      if ($line -match "package:(.*iris.*)") {
        $pkg = $Matches[1].Trim()
        if ($pkg -and $ids -notcontains $pkg) { $ids += $pkg }
      }
    }
  } catch {}

  foreach ($id in $ids) {
    try {
      $out = & adb shell dumpsys package $id 2>$null
      foreach ($line in $out) {
        if ($line -match 'versionCode=(\d+)') { return @{ appId = $id; versionCode = [int]$Matches[1] } }
      }
    } catch { continue }
  }
  return $null
}

$pending = Get-PendingVersionCode -Path $ApkPath
if ($null -eq $pending) {
  Write-Warning "[check-apk-install] cannot determine pending versionCode (apk not found or no aapt). apk=$ApkPath"
  Write-Host "[check-apk-install] tip: build first with: flutter build apk --debug --flavor tifi7  (universal, see AGENTS.md:474)"
  exit 0
}

$installed = Get-InstalledVersionCode -AppIdHint $AppId
if ($null -eq $installed) {
  Write-Host "[check-apk-install] no installed iris package found (fresh install). pending=$pending apk=$ApkPath -> safe."
  exit 0
}

$installedVc = $installed.versionCode
$installedId = $installed.appId
$delta = $pending - $installedVc

Write-Host "[check-apk-install] installed $installedId versionCode=$installedVc  pending $ApkPath versionCode=$pending  delta=$delta  threshold=$ExcessiveThreshold"

# Rule 1: downgrade
if ($pending -lt $installedVc) {
  Write-Warning "[check-apk-install] BLOCKED: downgrade ($pending < $installedVc) -> Android will require uninstall + DATA LOSS."
  Write-Host "  Fix: install the same form (universal vs split, debug vs release) and same flavor."
  Write-Host "  Studio Run users: keep Run config --flavor tifi7 + Build Variants tifi7Debug; do not install CI split apks on the dev device."
  Write-Host "  If you must downgrade, use: adb install -d <apk>  (still risky) or adb uninstall -k $installedId first."
  exit 1
}

# Rule 2: excessive jump (>600 per user spec) -> split mix
if ($delta -gt $ExcessiveThreshold) {
  Write-Warning "[check-apk-install] BLOCKED: excessive jump (+$delta > $ExcessiveThreshold). Likely split(+2000) vs universal mix."
  Write-Host "  Fix: use the universal apk for manual installs: build/app/outputs/flutter-apk/app-tifi7-debug.apk"
  Write-Host "  CI split apks (IRIS-android-*.apk) are for distribution only (ci.yml:96 --split-per-abi)."
  exit 1
}

Write-Host "[check-apk-install] OK: safe to install (delta=$delta within threshold)."
exit 0
