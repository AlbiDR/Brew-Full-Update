#!/bin/zsh
# Build "Brew Full Update.app": a native window that runs brew_full_update.zsh.
#   ./build-app.sh [--out DIR]        (default: ./build)
# Env: BFU_SIGN_ID  codesign identity (default "-" = ad-hoc)
set -eu
setopt pipefail

here="${0:A:h}"
out="$here/build"
[[ "${1:-}" == "--out" ]] && out="${2:?--out needs a directory}"

src="$here/brew_full_update.zsh"
app="$out/Brew Full Update.app"
bundle_id="com.hidoly.brew-full-update"
sign_id="${BFU_SIGN_ID:--}"

zsh -n "$src"
version=$(sed -nE 's/^BFU_VERSION="([^"]+)"/\1/p' "$src")
[[ -n "$version" ]] || { echo "BFU_VERSION not found in $src" >&2; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# The script ships inside the bundle, so the window always runs the same version it was built with.
cp "$src" "$app/Contents/Resources/brew_full_update.zsh"
cp "$here/assets/applet.icns" "$app/Contents/Resources/AppIcon.icns"

# The window uses macOS 27 APIs (tabs picker, Liquid Glass), so that is the deployment target.
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos27.0" \
  -o "$app/Contents/MacOS/Brew Full Update" "$here"/native/*.swift

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Brew Full Update</string>
  <key>CFBundleDisplayName</key><string>Brew Full Update</string>
  <key>CFBundleExecutable</key><string>Brew Full Update</string>
  <key>CFBundleIdentifier</key><string>${bundle_id}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$sign_id" "$app" >/dev/null 2>&1

cmp -s "$src" "$app/Contents/Resources/brew_full_update.zsh" \
  || { echo "embedded script differs from source" >&2; exit 1; }
echo "Built $app (v$version, signed: $sign_id) - embedded script verified"
