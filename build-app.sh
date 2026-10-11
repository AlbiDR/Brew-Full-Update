#!/bin/zsh
# Build "Brew Full Update.app" from brew_full_update.zsh.
#   ./build-app.sh [--out DIR]        (default: ./build)
# Env: BFU_SIGN_ID  codesign identity (default "-" = ad-hoc)
set -eu
setopt pipefail

here="${0:A:h}"
out="$here/build"
[[ "${1:-}" == "--out" ]] && out="${2:?--out needs a directory}"

src="$here/brew_full_update.zsh"
template="$here/launcher.applescript.in"
app="$out/Brew Full Update.app"
bundle_id="com.hidoly.brew-full-update"
sign_id="${BFU_SIGN_ID:--}"

zsh -n "$src"
version=$(sed -nE 's/^BFU_VERSION="([^"]+)"/\1/p' "$src")
[[ -n "$version" ]] || { echo "BFU_VERSION not found in $src" >&2; exit 1; }

# Embed the script, escaped for an AppleScript string literal.
code="export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH"$'\n'"$(<"$src")"$'\n'
esc="${code//\\/\\\\}"
esc="${esc//\"/\\\"}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
print -rn -- "${"$(<"$template")"/@@SHELL_CODE@@/$esc}" > "$tmp/launcher.applescript"

mkdir -p "$out"; rm -rf "$app"
osacompile -o "$app" "$tmp/launcher.applescript"

# Icon + identity
cp "$here/assets/applet.icns" "$here/assets/Assets.car" "$app/Contents/Resources/"
plist="$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
plutil -replace CFBundleName -string "Brew Full Update" "$plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$version" "$plist"
xattr -cr "$app"
codesign --force --deep -s "$sign_id" "$app" 2>/dev/null
codesign --verify --deep "$app"

# Verify the embedded source is byte-identical to the file.
embedded=$(osadecompile "$app/Contents/Resources/Scripts/main.scpt" \
  | awk '/^set shellCode to "/{f=1} f{print} /^"$/ && f{exit}')
check="$tmp/embedded.zsh"
print -r -- "$embedded" | sed '1s/^set shellCode to "//' | sed '$d' \
  | sed 's/\\"/"/g; s/\\\\/\\/g' > "$check"
if [[ "$(<"$check")" == *"$(<"$src")"* ]]; then
  echo "Built $app (v$version, signed: $sign_id) - embedded source verified"
else
  echo "Embedded source does not match $src" >&2; exit 1
fi
