#!/bin/zsh
# Regenerate assets/applet.icns and assets/icon.png from assets/make-icon.swift.
# Needs the Swift compiler (Xcode or the Command Line Tools) plus sips and iconutil.
set -eu
here="${0:A:h}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos27.0" "$here/assets/make-icon.swift" -o "$work/make-icon"
"$work/make-icon" "$work/icon_1024.png" >/dev/null

set=$work/applet.iconset; mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$work/icon_1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$work/icon_1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o "$here/assets/applet.icns"
sips -Z 512 "$work/icon_1024.png" --out "$here/assets/icon.png" >/dev/null
echo "Wrote assets/applet.icns and assets/icon.png"
