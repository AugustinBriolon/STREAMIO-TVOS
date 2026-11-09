#!/usr/bin/env bash
# Downloads the official VideoLAN TVVLCKit build into Vendor/ (git-ignored). See ADR 0007.
set -euo pipefail

VERSION="3.7.3-319ed2c0-79128878"
SHA256="b5f90c226ed54d9dc1c03901c60dc7749b74a53caace2c3047e4c0b7a063e46c"
URL="https://download.videolan.org/cocoapods/prod/TVVLCKit-${VERSION}.tar.xz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
ARCHIVE="$VENDOR/TVVLCKit-${VERSION}.tar.xz"

if [ -d "$VENDOR/TVVLCKit.xcframework" ]; then
  echo "TVVLCKit already present in $VENDOR"
  exit 0
fi

mkdir -p "$VENDOR"
[ -f "$ARCHIVE" ] || curl -fL --retry 3 -o "$ARCHIVE" "$URL"
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c -

tar -xJf "$ARCHIVE" -C "$VENDOR" TVVLCKit-binary/TVVLCKit.xcframework TVVLCKit-binary/COPYING.txt
mv "$VENDOR/TVVLCKit-binary/TVVLCKit.xcframework" "$VENDOR/"
mv "$VENDOR/TVVLCKit-binary/COPYING.txt" "$VENDOR/TVVLCKit-COPYING.txt"
rm -rf "$VENDOR/TVVLCKit-binary" "$ARCHIVE"
echo "TVVLCKit ${VERSION} installed in $VENDOR"
