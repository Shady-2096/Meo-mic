#!/usr/bin/env bash
#
# Copies the probe into /Applications and launches it.
#
# The copy is not optional housekeeping. macOS refuses to install a system
# extension from an app anywhere else, failing with
# `unsupportedParentBundleLocation`. Running it straight out of ./build is the
# single most common way to get a confusing refusal that has nothing to do
# with signing.

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Meo Camera Probe.app"
SRC="build/${APP_NAME}"
DEST="/Applications/${APP_NAME}"

if [[ ! -d "${SRC}" ]]; then
  echo "Not built yet. Run ./build.sh first." >&2
  exit 1
fi

echo "==> Recording pre-install state"
echo "--- system extensions ---"
systemextensionsctl list || true
echo
echo "--- SIP ---"
csrutil status || true
echo

if [[ -d "${DEST}" ]]; then
  echo "==> Removing previous copy at ${DEST}"
  rm -rf "${DEST}"
fi

echo "==> Copying to ${DEST}"
# -R preserves the signature; cp -r or rsync without --archive can break the
# seal and turn a signing question into a validation question.
cp -R "${SRC}" "${DEST}"

echo "==> Verifying the copy still validates"
codesign --verify --deep --strict --verbose=2 "${DEST}" 2>&1 || {
  echo
  echo "The copy does not validate. Record this — it is a result, not a" >&2
  echo "setup problem, and it changes what §8.5 has to say about install." >&2
}

echo
echo "==> Launching"
open "${DEST}"

cat <<'EOF'

The window is open. Now:

  1. Press "Install extension".
  2. Read the log pane. If macOS asks for approval, go to
     System Settings > General > Login Items & Extensions and allow it,
     then press Install again.
  3. Press "Refresh cameras" and see whether "Meo Camera Probe" appears.
  4. Pick it in the preview and check the sweep bar is MOVING.
  5. Then check the real apps listed in RESULTS-TEMPLATE.md.

Watch the system's own view of it in another terminal with:

    systemextensionsctl list
    log stream --predicate 'subsystem == "com.meo.camera.probe.extension"'

Whatever happens, including a flat refusal, is the §18 step 2 answer.
Write it down verbatim.
EOF
