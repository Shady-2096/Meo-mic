#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
configuration=${1:-debug}
build_dir="$repo_dir/build"
app_dir="$build_dir/MeoMic.app"
contents_dir="$app_dir/Contents"
binary_dir="$repo_dir/.build/$configuration"

cd "$repo_dir"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/ModuleCache"
swift build --disable-sandbox -c "$configuration"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/MeoMic" "$contents_dir/MacOS/MeoMic"
cp "pc-app/icon.jpg" "$contents_dir/Resources/icon.jpg"

icon_source="$build_dir/AppIcon-1024.png"
iconset="$build_dir/AppIcon.iconset"
asset_catalog="$build_dir/MeoMicAssets.xcassets"
sips -s format png -z 1024 1024 "pc-app/icon.jpg" --out "$icon_source" >/dev/null
sips -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
    "$icon_source" --out "$icon_source" >/dev/null
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
rm -rf "$asset_catalog"
mkdir -p "$asset_catalog/AppIcon.appiconset"
cp "$iconset"/*.png "$asset_catalog/AppIcon.appiconset/"
cp "Packaging/AppIconContents.json" "$asset_catalog/AppIcon.appiconset/Contents.json"
xcrun actool "$asset_catalog" \
    --compile "$contents_dir/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$build_dir/AppIconInfo.plist"

cp "$binary_dir/MeoMic_MeoMicApp.bundle/icon.jpg" "$contents_dir/Resources/icon.jpg" 2>/dev/null || true

plutil -create xml1 "$contents_dir/Info.plist"
plutil -insert CFBundleDisplayName -string "Meo Mic" "$contents_dir/Info.plist"
plutil -insert CFBundleExecutable -string "MeoMic" "$contents_dir/Info.plist"
plutil -insert CFBundleIdentifier -string "app.meomic.macos" "$contents_dir/Info.plist"
plutil -insert CFBundleIconName -string "AppIcon" "$contents_dir/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$contents_dir/Info.plist"
plutil -insert CFBundleName -string "Meo Mic" "$contents_dir/Info.plist"
plutil -insert CFBundlePackageType -string "APPL" "$contents_dir/Info.plist"
plutil -insert CFBundleShortVersionString -string "1.0.0" "$contents_dir/Info.plist"
plutil -insert CFBundleVersion -string "1" "$contents_dir/Info.plist"
plutil -insert LSMinimumSystemVersion -string "14.0" "$contents_dir/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$contents_dir/Info.plist"
plutil -insert NSLocalNetworkUsageDescription -string "Meo Mic receives your phone’s microphone audio over your local network." "$contents_dir/Info.plist"
plutil -insert NSBonjourServices -json '["_meomic._udp"]' "$contents_dir/Info.plist"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
