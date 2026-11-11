#!/usr/bin/env bash
# Archive Loge, export an App Store Connect IPA and upload it to TestFlight (ADR 0022).
# Usage: scripts/release-testflight.sh [--no-upload]
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.h6245.vortxtv"
BUILD_NUMBER="$(date +%Y%m%d%H%M)" # unique and increasing, as App Store Connect requires
ARTIFACTS=".asc/artifacts"
ARCHIVE="$ARTIFACTS/Loge.xcarchive"
IPA="$ARTIFACTS/Loge.ipa"

[ -d Vendor/TVVLCKit.xcframework ] || { echo "Run ./scripts/fetch-vlckit.sh first" >&2; exit 1; }

mkdir -p "$ARTIFACTS"
rm -rf "$ARCHIVE" "$IPA"

xcodegen generate

xcodebuild archive \
  -project Loge.xcodeproj -scheme Loge \
  -destination "generic/platform=tvOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

asc xcode export \
  --archive-path "$ARCHIVE" --ipa-path "$IPA" \
  --xcodebuild-flag=-allowProvisioningUpdates

echo "Built $IPA (build $BUILD_NUMBER)"
[ "${1:-}" = "--no-upload" ] && exit 0

asc builds upload --app "$BUNDLE_ID" --ipa "$IPA" --wait
