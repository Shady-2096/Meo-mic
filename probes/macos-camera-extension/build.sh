#!/usr/bin/env bash
#
# Builds the macOS camera-extension probe as a self-contained .app with the
# .systemextension embedded, signed ad-hoc.
#
# Bundles are assembled by hand rather than through an Xcode project on
# purpose. CAMERA_BUILD_PLAN.md §8.1 asks what happens with a FREE Apple ID
# and no provisioning profile; an .xcodeproj quietly pulls in whatever signing
# identity and team the machine happens to have, which is exactly the variable
# the probe is trying to control. Every signing decision here is visible on
# one line.
#
#   ./build.sh              ad-hoc signature (the zero-budget case)
#   ./build.sh <identity>   sign with a named identity, e.g. a personal team,
#                           to test the other half of the §8.1 question

set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="${1:--}"          # "-" is ad-hoc
BUILD_DIR="build"
APP="${BUILD_DIR}/Meo Camera Probe.app"
EXT="${APP}/Contents/Library/SystemExtensions/com.meo.camera.probe.extension.systemextension"

# The deployment target is the plan's floor (§3): 12.3 is when Core Media I/O
# camera extensions arrived. Building against 13.0 keeps a little headroom
# while staying well under the macOS 14 target Meo Mic inherited by inertia.
TARGET="arm64-apple-macos13.0"

echo "==> Cleaning"
rm -rf "${BUILD_DIR}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${EXT}/Contents/MacOS"

echo "==> Building extension executable"
swiftc \
  -target "${TARGET}" \
  -O \
  -framework CoreMediaIO \
  -framework CoreMedia \
  -framework CoreVideo \
  -o "${EXT}/Contents/MacOS/MeoCameraProbeExtension" \
  Extension/main.swift

cp Extension/Info.plist "${EXT}/Contents/Info.plist"

echo "==> Building host executable"
swiftc \
  -target "${TARGET}" \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework SystemExtensions \
  -o "${APP}/Contents/MacOS/MeoCameraProbe" \
  Host/main.swift

cp Host/Info.plist "${APP}/Contents/Info.plist"

# The extension has to be signed before the app that contains it, or the
# app's own seal will not cover it and validation fails with a nested-code
# error that looks nothing like the real cause.
echo "==> Signing extension (identity: ${IDENTITY})"
codesign --force \
  --sign "${IDENTITY}" \
  --entitlements Extension/Extension.entitlements \
  --options runtime \
  --timestamp=none \
  "${EXT}"

echo "==> Signing app (identity: ${IDENTITY})"
codesign --force \
  --sign "${IDENTITY}" \
  --entitlements Host/Host.entitlements \
  --options runtime \
  --timestamp=none \
  "${APP}"

echo
echo "==> Signature check"
codesign -dv --entitlements - "${APP}" 2>&1 || true
echo
codesign -dv --entitlements - "${EXT}" 2>&1 || true

echo
echo "==> Built: ${APP}"
echo
cat <<'EOF'
Next: the app must be in /Applications before macOS will let it install a
system extension. Run:

    ./install.sh

Then press "Install extension" in the window and read the log. Whatever it
says — including a refusal — is the Milestone 0 answer. Copy it into
RESULTS-TEMPLATE.md.
EOF
