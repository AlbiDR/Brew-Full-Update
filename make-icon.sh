#!/bin/zsh
# Regenerate assets/applet.icns from assets/icon.svg (macOS built-ins only: osascript, sips, iconutil).
set -eu
here="${0:A:h}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$here/assets/icon.svg" "$work/icon.svg"
( cd "$work" && osascript -l JavaScript "$here/assets/render-icon.js" >/dev/null )
set=$work/applet.iconset; mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$work/icon_1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$work/icon_1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o "$here/assets/applet.icns"
echo "Wrote assets/applet.icns"
