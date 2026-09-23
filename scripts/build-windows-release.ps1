<#
.SYNOPSIS
  Build the Windows release artifacts with versioned file names.
.DESCRIPTION
  Reads the version from pubspec.yaml (the single source of truth), strips the
  +build suffix so the name matches the release tag (vMAJOR.MINOR.PATCH), then
  produces the following in the repository root:

    IRIS-windows-v<version>.zip            portable "unzip and run" package
    IRIS-windows-installer-v<version>.exe  Inno Setup installer (needs ISCC.exe)
    IRIS-windows-store-v<version>.msix     Microsoft Store package

  Every step is skippable; missing optional tooling (Inno Setup) only warns.
.PARAMETER SkipCodegen
  Skip "flutter pub get" + build_runner. Use when generated code is fresh.
.PARAMETER SkipInstaller
  Do not build the Inno Setup installer.
.PARAMETER SkipMsix
  Do not build the MSIX package.
#>
[CmdletBinding()]
param(
    [switch]$SkipCodegen,
    [switch]$SkipInstaller,
    [switch]$SkipMsix
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    # --- Version (single source of truth: pubspec.yaml) -------------------
    $rawVersion = (Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
    $version = $rawVersion.Split('+')[0]
    Write-Host "IRIS version: $version" -ForegroundColor Cyan

    # --- Codegen + Windows build -----------------------------------------
    if (-not $SkipCodegen) {
        Write-Host "Generating code..." -ForegroundColor Cyan
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
        dart run build_runner build --delete-conflicting-outputs
        if ($LASTEXITCODE -ne 0) { throw "build_runner failed" }
    }

    Write-Host "Building Windows release..." -ForegroundColor Cyan
    flutter build windows
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

    $releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"

    # The in-app Windows updater is dead code (CI strips it too); the portable
    # package ships portable_update_by_zip.* instead.
    Remove-Item -Path (Join-Path $releaseDir "iris-updater.bat") -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "windows\portable_update_by_zip.bat" -Destination $releaseDir -Force
    Copy-Item -Path "windows\portable_update_by_zip.ps1" -Destination $releaseDir -Force

    # --- Portable ZIP -----------------------------------------------------
    $stage = Join-Path $repoRoot "IRIS"
    if (Test-Path $stage) { Remove-Item -Path $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -Path (Join-Path $releaseDir "*") -Destination $stage -Recurse -Force
    # Portable marker: its presence redirects all user data into .\userdata.
    New-Item -ItemType File -Path (Join-Path $stage "portable.flag") | Out-Null
    $zipName = "IRIS-windows-v$version.zip"
    Compress-Archive -Path $stage -DestinationPath (Join-Path $repoRoot $zipName) -Force
    Write-Host "  -> $zipName" -ForegroundColor Green

    # --- Installer --------------------------------------------------------
    if (-not $SkipInstaller) {
        $isccPath = $null
        $isccCmd = Get-Command iscc -ErrorAction SilentlyContinue
        if ($isccCmd) { $isccPath = $isccCmd.Source }
        if (-not $isccPath) {
            foreach ($candidate in @(
                    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
                    "C:\Program Files\Inno Setup 6\ISCC.exe"
                )) {
                if (Test-Path $candidate) { $isccPath = $candidate; break }
            }
        }

        if (-not $isccPath) {
            Write-Warning "ISCC.exe not found; skipping installer. Install Inno Setup 6 or pass -SkipInstaller."
        } else {
            Write-Host "Building installer..." -ForegroundColor Cyan
            & $isccPath "/DMyAppVersion=$version" "inno.iss"
            if ($LASTEXITCODE -ne 0) { throw "iscc failed" }
            $exeName = "IRIS-windows-installer-v$version.exe"
            Copy-Item -Path (Join-Path $releaseDir $exeName) -Destination $repoRoot -Force
            Write-Host "  -> $exeName" -ForegroundColor Green
        }
    }

    # --- MSIX -------------------------------------------------------------
    if (-not $SkipMsix) {
        Write-Host "Building MSIX..." -ForegroundColor Cyan
        # Mirror CI: drop the release folder so the installer / portable scripts
        # are not bundled. msix:build runs "flutter build windows" again.
        Remove-Item -Path $releaseDir -Recurse -Force -ErrorAction SilentlyContinue
        dart run msix:build --store true
        if ($LASTEXITCODE -ne 0) { throw "msix:build failed" }
        Remove-Item -Path (Join-Path $releaseDir "iris-updater.bat") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $releaseDir "portable_update_by_zip.bat") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $releaseDir "portable_update_by_zip.ps1") -Force -ErrorAction SilentlyContinue

        $msixName = "IRIS-windows-store-v$version"
        dart run msix:pack --store true --output-name $msixName
        if ($LASTEXITCODE -ne 0) { throw "msix:pack failed" }
        Copy-Item -Path (Join-Path $releaseDir "$msixName.msix") -Destination $repoRoot -Force
        Write-Host "  -> $msixName.msix" -ForegroundColor Green
    }

    Write-Host "Windows release artifacts are in $repoRoot" -ForegroundColor Green
} finally {
    Pop-Location
}
