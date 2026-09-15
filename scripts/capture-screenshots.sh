#!/usr/bin/env bash
# Capture Lull's primary UI screens to PNGs for markup / review.
#
# Re-run:
#   ./scripts/capture-screenshots.sh
#   OUTPUT_DIR=/path/to/dir ./scripts/capture-screenshots.sh
#   DEVICE_NAME="iPhone 17" ./scripts/capture-screenshots.sh
#
# Output files (default OUTPUT_DIR is the Project store media folder):
#   onboarding.png  — first-run setup (no baby profile)
#   home.png        — Now tab (default launch) with demo sleep data
#   history.png     — History tab
#   patterns.png    — Patterns tab
#
# Uses launch args -UIScreen and -UIDemoSeed (see Lull/ScreenshotCaptureSupport.swift).
# Does not automate sheets/detail push screens (Start Sleep, Sleep Detail, etc.).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Lull"
BUNDLE_ID="com.williambjork.Lull"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DEFAULT_OUTPUT="/cursor/stores/bc-1535975c-53b5-4e22-8d38-f7b1e5e7fab3/media/screenshots"
# On private workers the store lives under Application Support; fall back if /cursor is missing.
if [[ ! -d "$(dirname "$DEFAULT_OUTPUT")" && ! -d "/cursor/stores" ]]; then
  DEFAULT_OUTPUT="${HOME}/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-1535975c-53b5-4e22-8d38-f7b1e5e7fab3/files/media/screenshots"
fi
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT}"
# Keep DerivedData off iCloud/FileProvider paths (e.g. Documents) — those inject
# FinderInfo xattrs that make codesign fail with "resource fork … not allowed".
DERIVED_DATA="${DERIVED_DATA:-/tmp/lull-screenshots-derived}"
SETTLE_SECONDS="${SETTLE_SECONDS:-3}"

mkdir -p "$OUTPUT_DIR"

echo "==> Looking up simulator: $DEVICE_NAME"
# Exact device name match (avoid "iPhone 17" matching "iPhone 17e").
DEVICE_ID="$(xcrun simctl list devices available | awk -F '[()]' -v name="$DEVICE_NAME" '
  {
    line = $0
    sub(/^[[:space:]]+/, "", line)
    # Device lines look like: Name (UDID) (State)
    if (index(line, name " (") == 1) {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit }
      }
    }
  }
')"
if [[ -z "${DEVICE_ID:-}" ]]; then
  echo "error: no available simulator named '$DEVICE_NAME'" >&2
  exit 1
fi
echo "    UDID $DEVICE_ID"

echo "==> Booting simulator"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
open -a Simulator --args -CurrentDeviceUDID "$DEVICE_ID" >/dev/null 2>&1 || true

echo "==> Building & installing ($SCHEME → $DEVICE_NAME)"
set -o pipefail
xcodebuild \
  -project "$ROOT/Lull.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  build \
  | awk '/error:|warning:|BUILD SUCCEEDED|BUILD FAILED|\*\*/ { print }'
set +o pipefail

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -name 'Lull.app' -maxdepth 2 | head -n 1)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "error: Lull.app not found under $DERIVED_DATA" >&2
  exit 1
fi

# Strip any residual xattrs before install (belt and suspenders).
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --force --sign - --timestamp=none --generate-entitlement-der "$APP_PATH"

xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

capture() {
  local name="$1"
  shift
  local out="$OUTPUT_DIR/${name}.png"
  echo "==> Capturing ${name}.png ($*)"
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
  # Fresh install container on first seeded launch keeps demo data deterministic.
  xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" "$@"
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$DEVICE_ID" screenshot "$out"
  if [[ ! -s "$out" ]]; then
    echo "error: screenshot missing or empty: $out" >&2
    exit 1
  fi
  echo "    wrote $out ($(wc -c < "$out" | tr -d ' ') bytes)"
}

# Onboarding first (no demo seed — empty profile).
capture onboarding -UIScreen onboarding

# Primary tab states with a seeded demo baby.
capture home -UIScreen home -UIDemoSeed
capture history -UIScreen history -UIDemoSeed
capture patterns -UIScreen patterns -UIDemoSeed

echo "==> Done. Screenshots in $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/*.png
