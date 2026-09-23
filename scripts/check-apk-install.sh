#!/usr/bin/env sh
# Pre-install guard for Android APKs: prevents versionCode downgrade (+ uninstall + data loss)
# and detects split→universal mix (per user spec: pending - installed > 600 -> block).
# Usage: sh scripts/check-apk-install.sh [path/to.apk]
# Exit 0 = safe, 1 = blocked (or adb not available but APK parsed). Pure read/inspect.
set -eu
APK_PATH="${1:-build/app/outputs/flutter-apk/app-tifi7-debug.apk}"
THRESHOLD="${2:-600}"

read_base() {
  if [ -f "android/version.properties" ]; then
    sed -n 's/^\s*versionCode\s*=\s*\([0-9][0-9]*\)\s*$/\1/p' android/version.properties | head -n1
  fi
}

pending_version() {
  # 1) aapt dump badging (most accurate)
  for aapt in "$ANDROID_HOME/build-tools"/*/aapt "$ANDROID_SDK_ROOT/build-tools"/*/aapt "$(command -v aapt 2>/dev/null || true)"; do
    if [ -x "$aapt" ] && [ -f "$APK_PATH" ]; then
      v=$( "$aapt" dump badging "$APK_PATH" 2>/dev/null | grep -o "versionCode='[0-9]*'" | head -n1 | grep -o "[0-9]*" || true)
      if [ -n "$v" ]; then echo "$v"; return; fi
    fi
  done
  # 2) file-name heuristic (split): arm64=+2000 per AGENTS.md:469
  base=$(read_base)
  if [ -n "$base" ] && [ -f "$APK_PATH" ]; then
    case "$(basename "$APK_PATH")" in
      *arm64*) echo $((base + 2000)); return ;;
      *armeabi*|*x86_64*) echo $((base + 1000)); return ;;
      *) echo "$base"; return ;;
    esac
  fi
  echo "$base"
}

installed_version() {
  for id in "iris.tifi7" "iris" "com.example.iris"; do
    v=$(adb shell dumpsys package "$id" 2>/dev/null | grep -m1 'versionCode=' | grep -o '[0-9][0-9]*' | head -n1 || true)
    if [ -n "$v" ]; then echo "$id:$v"; return; fi
  done
  # also probe pm list
  for pkg in $(adb shell pm list packages 2>/dev/null | grep iris | cut -d: -f2); do
    v=$(adb shell dumpsys package "$pkg" 2>/dev/null | grep -m1 'versionCode=' | grep -o '[0-9][0-9]*' | head -n1 || true)
    if [ -n "$v" ]; then echo "$pkg:$v"; return; fi
  done
  echo ""
}

pending=$(pending_version)
if [ -z "$pending" ]; then
  echo "[check-apk-install] cannot determine pending versionCode (apk not found or no aapt). apk=$APK_PATH" >&2
  echo "[check-apk-install] tip: build first with: flutter build apk --debug --flavor tifi7  (universal, see AGENTS.md:474)" >&2
  exit 0
fi

# shellcheck disable=SC2046
installed_raw=$(installed_version || true)
if [ -z "$installed_raw" ]; then
  echo "[check-apk-install] no installed iris package found (fresh install). pending=$pending apk=$APK_PATH -> safe."
  exit 0
fi

installed_id=$(echo "$installed_raw" | cut -d: -f1)
installed_vc=$(echo "$installed_raw" | cut -d: -f2)
delta=$((pending - installed_vc))

echo "[check-apk-install] installed $installed_id versionCode=$installed_vc  pending $APK_PATH versionCode=$pending  delta=$delta  threshold=$THRESHOLD"

if [ "$pending" -lt "$installed_vc" ]; then
  echo "[check-apk-install] BLOCKED: downgrade ($pending < $installed_vc) -> Android will require uninstall + DATA LOSS." >&2
  echo "  Fix: install the same form (universal vs split, debug vs release) and same flavor." >&2
  echo "  Studio Run users: keep Run config --flavor tifi7 + Build Variants tifi7Debug; do not install CI split apks on the dev device." >&2
  exit 1
fi

if [ "$delta" -gt "$THRESHOLD" ]; then
  echo "[check-apk-install] BLOCKED: excessive jump (+$delta > $THRESHOLD). Likely split(+2000) vs universal mix." >&2
  echo "  Fix: use the universal apk for manual installs: build/app/outputs/flutter-apk/app-tifi7-debug.apk" >&2
  echo "  CI split apks (IRIS-android-*.apk) are for distribution only (ci.yml:96 --split-per-abi)." >&2
  exit 1
fi

echo "[check-apk-install] OK: safe to install (delta=$delta within threshold)."
