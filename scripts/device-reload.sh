#!/usr/bin/env bash
# Rebuild + reinstall Lull onto the plugged-in physical iPhone when Swift sources change.
# Not true Swift hot-reload (InjectionIII) — full incremental rebuild + launch.
#
# Usage (from repo root):
#   ./scripts/device-reload.sh
#   DEVICE_UDID=... ./scripts/device-reload.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Lull"
BUNDLE_ID="com.williambjork.Lull"
TEAM="${DEVELOPMENT_TEAM:-74952LBRMQ}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/lull-pillow-device}"
DEVICE_UDID="${DEVICE_UDID:-00008150-001258260245401C}"
POLL_SECONDS="${POLL_SECONDS:-1}"

cd "$ROOT"

stamp_sources() {
  find "$ROOT/Lull" "$ROOT/LullCore/Sources" -type f \( -name '*.swift' -o -name '*.plist' \) -print0 \
    | xargs -0 stat -f '%m %N' 2>/dev/null \
    | sort \
    | shasum -a 256 \
    | awk '{ print $1 }'
}

build_install_launch() {
  echo ""
  echo "==> $(date '+%H:%M:%S') building for device $DEVICE_UDID"
  xcodebuild \
    -project "$ROOT/Lull.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    DEVELOPMENT_TEAM="$TEAM" \
    build \
    | awk '/error:|BUILD SUCCEEDED|BUILD FAILED|\*\*/ { print }'

  local app
  app="$(find "$DERIVED_DATA/Build/Products/Debug-iphoneos" -name 'Lull.app' -maxdepth 2 | head -n 1)"
  if [[ -z "$app" || ! -d "$app" ]]; then
    echo "error: Lull.app not found under $DERIVED_DATA" >&2
    return 1
  fi

  echo "==> installing"
  xcrun devicectl device install app --device "$DEVICE_UDID" "$app" >/dev/null
  echo "==> launching $BUNDLE_ID"
  xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" >/dev/null || true
  echo "==> on device"
}

echo "Watching $ROOT/Lull (+ LullCore) → iPhone $DEVICE_UDID"
echo "Ctrl-C to stop. First deploy…"

last="$(stamp_sources || true)"
build_install_launch

while true; do
  sleep "$POLL_SECONDS"
  now="$(stamp_sources || true)"
  if [[ "$now" != "$last" ]]; then
    last="$now"
    # Debounce burst saves
    sleep 0.4
    last="$(stamp_sources || true)"
    build_install_launch || echo "==> deploy failed; still watching"
  fi
done
