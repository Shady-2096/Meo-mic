#!/usr/bin/env bash
#
# Removes the probe and its extension.
#
# §8.5 requires the real product to have a clean uninstall path, so the probe
# models one. Deactivation is requested through the app itself, because
# `systemextensionsctl uninstall` needs a team identifier that an ad-hoc build
# does not have.

set -euo pipefail

APP_NAME="Meo Camera Probe.app"
DEST="/Applications/${APP_NAME}"

echo "==> Extensions before"
systemextensionsctl list || true
echo

if [[ -d "${DEST}" ]]; then
  cat <<'EOF'
The extension must be deactivated by the app that installed it.

  1. Open "Meo Camera Probe" from /Applications.
  2. Press "Uninstall extension".
  3. Wait for the log to report completion.
  4. Re-run this script.

Press Enter once that is done, or Ctrl-C to stop here.
EOF
  read -r _
fi

echo "==> Removing ${DEST}"
rm -rf "${DEST}"

echo
echo "==> Extensions after"
systemextensionsctl list || true

echo
echo "If a 'com.meo.camera.probe.extension' entry is still listed as"
echo "[terminated waiting to uninstall on reboot], that is expected — it"
echo "clears on the next restart. Record it; §8.5 has to account for it."
