#!/bin/zsh
# Builds MeoMic.app and wraps it in a zip ready to attach to a GitHub release.
#
# The app is ad-hoc signed, not Developer ID signed and not notarized: that
# needs a paid Apple Developer account, and this project does not have one.
# The zip is therefore a normal unsigned download, and first launch needs the
# user to approve it once in System Settings. That is documented in the README
# and printed at the end of this script, so release notes can repeat it.
set -euo pipefail

repo_dir=${0:A:h:h}
build_dir="$repo_dir/build"
app_dir="$build_dir/MeoMic.app"

"$repo_dir/scripts/build-app.sh" release >/dev/null

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$app_dir/Contents/Info.plist")
archive="$build_dir/MeoMic-macOS-v${version}.zip"

# ditto, not zip: it preserves the bundle's signature and resource forks.
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"

# Verify what we are about to ship rather than assuming the build was fine.
codesign --verify --strict "$app_dir"
checksum=$(shasum -a 256 "$archive" | cut -d' ' -f1)

print
print "Built    $archive"
print "Version  $version"
print "SHA-256  $checksum"
print
print "Publish the SHA-256 in the release notes: it is the only way for"
print "someone to check the download, since the app is not notarized."
print
print "First launch on the downloaded copy: open it, let macOS refuse, then"
print "System Settings -> Privacy & Security -> Open Anyway."
