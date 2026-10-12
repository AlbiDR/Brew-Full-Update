#!/bin/zsh
# Dependency-free tests for brew_full_update.zsh. Run: tests/run.sh
# Uses a fake `brew` on PATH, so nothing on the real system is touched.
export LC_ALL=en_US.UTF-8
here="${0:A:h}"
src="$here/../brew_full_update.zsh"
pass=0; fail=0
ok()  { print -P "%F{green}PASS%f $1"; pass=$((pass+1)); }
bad() { print -P "%F{red}FAIL%f $1\n     got: $2"; fail=$((fail+1)); }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "[$2] expected [$3]"; }

zsh -n "$src" && ok "syntax" || bad "syntax" "zsh -n failed"
source "$src"

# --- version parsing
eq "current: single"    "$(_bfu_current_ver 'wget (1.0) < 2.0')" "1.0"
eq "current: multi"     "$(_bfu_current_ver 'wget (1.0, 1.1) < 2.0')" "1.0, 1.1"
eq "new: formula"       "$(_bfu_new_ver 'wget (1.0) < 2.0')" "2.0"
eq "new: cask !="       "$(_bfu_new_ver 'chrome (1.0) != 2.0')" "2.0"
eq "new: pinned"        "$(_bfu_new_ver 'wget (1.0) < 2.0 [pinned at 1.0]')" "2.0"
eq "current: tap name"  "$(_bfu_current_ver 'supabase/tap/supabase (2.117.0) < 2.120.0')" "2.117.0"

# --- exclusion filter (prefix match, not substring)
BFU_EXCLUDED_CASKS=(alfred topaz-photo)
in=$'alfred (5) != 6\ntopaz-photo-ai (1) != 2\nnot-alfred (1) != 2\nfirefox (1) != 2'
eq "exclude: prefixes only" "$(print -r -- "$in" | _bfu_filter_excluded | tr '\n' '|')" "not-alfred (1) != 2|firefox (1) != 2|"
BFU_EXCLUDED_CASKS=()
eq "exclude: empty list passes all" "$(print -r -- "$in" | _bfu_filter_excluded | wc -l | tr -d ' ')" "4"

# --- sizes shown in cleanup and the disk line
eq "size: KB"            "$(_bfu_size 512)"     "512.0 KB"
eq "size: MB"            "$(_bfu_size 2048)"    "2.0 MB"
eq "size: GB"            "$(_bfu_size 1048576)" "1.0 GB"
eq "size: negative kept" "$(_bfu_size -2048)"   "-2.0 MB"
eq "size: zero"          "$(_bfu_size 0)"       "0.0 KB"

# --- brew doctor headlines and macOS update titles (fixed sample output)
doctor_sample=$'Warning: Unbrewed header files were found in /usr/local/include.\n  Some detail\nWarning: A thing to know.\nYour system is ready to brew.'
eq "doctor: one headline per warning" "$(print -r -- "$doctor_sample" | _bfu_doctor_warnings | tr '\n' '|')" \
  "Unbrewed header files were found in /usr/local/include.|A thing to know.|"
eq "doctor: clean output has none" "$(print -r -- "Your system is ready to brew." | _bfu_doctor_warnings)" ""
softwareupdate_sample=$'Software Update Tool\n\nFinding available software\nSoftware Update found the following new or updated software:\n* Label: macOS Sequoia 15.5-24F74\n\tTitle: macOS Sequoia 15.5, Version: 15.5, Size: 1234K, Recommended: YES, Action: restart,'
eq "macOS: title and version" "$(print -r -- "$softwareupdate_sample" | _bfu_macos_updates)" "macOS Sequoia 15.5 (15.5)"
eq "macOS: nothing pending" "$(print -r -- "No new software available." | _bfu_macos_updates)" ""

# --- progress feed for the app window
eq "feed: off by default" "$(_bfu_emit step 1 6 Diagnostics)" ""
eq "feed: fields joined with |" "$(BFU_EVENTS=1 _bfu_emit step 1 6 Diagnostics)" "@@BFU step|1|6|Diagnostics"
queue_out=$(BFU_EVENTS=1 _bfu_print_queue $'wget (1.0) < 2.0\nchrome (130.1) != 130.2' cask | grep '^@@BFU')
eq "feed: queued rows with bump size" "$(print -r -- "$queue_out" | tr '\n' ' ')" "@@BFU queued|cask|wget|1.0|2.0|major @@BFU queued|cask|chrome|130.1|130.2|minor "
BFU_LAST_ERROR="boom"
eq "feed: failure reason" "$(BFU_EVENTS=1 print_failure_reason | grep '^@@BFU')" "@@BFU reason|boom"
BFU_LAST_ERROR=""

# --- adoption scanner (fixtures only; nothing on this Mac is read)
fx=$(mktemp -d)
/usr/bin/python3 - "$fx" <<'PY'
import json, os, plistlib, sys
fx = sys.argv[1]
def app(name, version, bundle, receipt=False):
    base = os.path.join(fx, "Applications", name + ".app", "Contents")
    os.makedirs(base)
    plistlib.dump({"CFBundleShortVersionString": version, "CFBundleIdentifier": bundle}, open(os.path.join(base, "Info.plist"), "wb"))
    if receipt: os.makedirs(os.path.join(base, "_MASReceipt"))
app("Foo", "1.2.0", "com.example.foo")           # matches its cask exactly
app("Bar", "1.0", "com.example.bar")             # older than its cask; also has an @beta cask
app("Mystery", "3.1", "com.example.mystery")     # no cask known
app("Managed", "1.0", "com.example.managed")     # already in the Caskroom
app("Store", "1.0", "com.example.store", True)   # Mac App Store
app("Safari", "17", "com.apple.Safari")          # Apple
casks = {
  "foo": {"version": "1.2.0", "tap_string": "homebrew/cask", "raw_artifacts": [[":app", ["Foo.app"]]]},
  "bar": {"version": "2.0", "tap_string": "homebrew/cask", "raw_artifacts": [[":app", ["Bar.app"]]]},
  "bar@beta": {"version": "2.1", "tap_string": "homebrew/cask", "raw_artifacts": [[":app", ["Bar.app"]]]},
}
os.makedirs(os.path.join(fx, "api"))
json.dump({"payload": json.dumps({"casks": casks})}, open(os.path.join(fx, "api", "packages.test.jws.json"), "w"))
os.makedirs(os.path.join(fx, "caskroom", "managed-cask", "1.0"))
open(os.path.join(fx, "caskroom", "managed-cask", "1.0", "Managed.app"), "w").close()
meta = os.path.join(fx, "caskroom", "zcask", ".metadata", "1.0", "0", "Casks")
os.makedirs(meta)
json.dump({"tap": "someone/tap"}, open(os.path.join(meta, "zcask.json"), "w"))
for name, tap in (("wget", "homebrew/core"), ("mytool", "me/tools")):
    d = os.path.join(fx, "cellar", name, "1.0")
    os.makedirs(d)
    json.dump({"source": {"tap": tap}}, open(os.path.join(d, "INSTALL_RECEIPT.json"), "w"))
os.makedirs(os.path.join(fx, "taps"))
PY
scan=$(BFU_API_DIR="$fx/api" BFU_TAPS_DIR="$fx/taps" BFU_CASKROOM="$fx/caskroom" BFU_CELLAR="$fx/cellar" \
  BFU_APP_DIRS="$fx/Applications" BFU_TAPS_LIST="" _bfu_adopt_scan_data)
has() { [[ "$scan" == *"$1"* ]] && ok "adopt: $2" || bad "adopt: $2" "$scan"; }
lacks() { [[ "$scan" != *"$1"* ]] && ok "adopt: $2" || bad "adopt: $2" "$scan"; }
has   $'A\tfoo\tFoo\t1.2.0\t1.2.0\thomebrew/cask\tmatch'  "an exact match is ready to adopt"
has   $'A\tbar\tBar\t1.0\t2.0\thomebrew/cask\tolder'      "an older app is flagged, and the plain cask beats @beta"
lacks "bar@beta"                                          "variants are not offered"
has   $'U\tMystery\t3.1\tcom.example.mystery'             "an app with no cask is listed apart"
lacks "Managed"                                           "apps Homebrew already manages are skipped"
lacks "Store"                                             "Mac App Store apps are skipped"
lacks "Safari"                                            "Apple apps are skipped"
has   $'T\tme/tools\tformula:mytool'                      "a formula from a missing tap is found"
has   $'T\tsomeone/tap\tcask:zcask'                       "a cask from a missing tap is found"
lacks "homebrew/core"                                     "the official tap is never reported"
scan=$(BFU_API_DIR="$fx/api" BFU_TAPS_DIR="$fx/taps" BFU_CASKROOM="$fx/caskroom" BFU_CELLAR="$fx/cellar" \
  BFU_APP_DIRS="$fx/Applications" BFU_TAPS_LIST=$'me/tools\nsomeone/tap' _bfu_adopt_scan_data)
lacks $'T\t'                                              "added taps are no longer reported"

# --- failure counter
BFU_FAILS=0
print_action_result x fail >/dev/null; print_action_result y done >/dev/null; print_action_result z fail >/dev/null
eq "fail counter counts only failures" "$BFU_FAILS" "2"

# --- exclusion note fits the layout width
BFU_W=78; BFU_EXCLUDED_CASKS=(alfred daisydisk)
eq "excluded note: short list in full" "$(_bfu_excluded_note)" "Excluding: alfred, daisydisk"
BFU_EXCLUDED_CASKS=(aaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbb cccccccccccccccc dddddddddddddddd eeeeeeeeeeeeeeee)
note=$(_bfu_excluded_note)
[[ "$note" == *"+"*" more" && ${#note} -le 78 ]] && ok "excluded note: long list truncated with +N more" || bad "excluded note truncation" "$note"
BFU_EXCLUDED_CASKS=()

# --- names saved by the app's Exclusions button are added to the list
fixture=$(mktemp)
printf '# saved by the app\n  zoom  \n\nobs-studio\n' > "$fixture"
n_default=$(zsh -c "source '$src'; print \${#BFU_EXCLUDED_CASKS}")
eq "exclusions file: names appended, comments and blanks skipped" \
  "$(BFU_EXCLUSIONS_FILE="$fixture" zsh -c "source '$src'; print -r -- \"\${BFU_EXCLUDED_CASKS[@]: -2}\" | tr '\n' ' '")" "zoom obs-studio "
eq "exclusions file: count grows by the saved names only" \
  "$(BFU_EXCLUSIONS_FILE="$fixture" zsh -c "source '$src'; print \${#BFU_EXCLUDED_CASKS}")" "$((n_default + 2))"
: > "$fixture"
eq "exclusions file: empty file adds nothing" \
  "$(BFU_EXCLUSIONS_FILE="$fixture" zsh -c "source '$src'; print \${#BFU_EXCLUDED_CASKS}")" "$n_default"
BFU_EXCLUSIONS_FILE="$fixture/missing" zsh -c "source '$src'" && ok "exclusions file: missing file is fine" || bad "exclusions file: missing file" "source failed"
rm -f "$fixture"

# --- exclusions file location: saved by the app's Location button, else the default
home=$(mktemp -d)
support="$home/Library/Application Support/Brew Full Update"
mkdir -p "$support"
printf 'zoom\n' > "$home/elsewhere.txt"
eq "location: default file when nothing is saved" \
  "$(env -u BFU_EXCLUSIONS_FILE HOME="$home" zsh -c "source '$src'; print -r -- \$BFU_EXCLUSIONS_FILE")" "$support/exclusions.txt"
printf '%s\n' "$home/elsewhere.txt" > "$support/exclusions-location.txt"
eq "location: saved path is used" \
  "$(env -u BFU_EXCLUSIONS_FILE HOME="$home" zsh -c "source '$src'; print -r -- \$BFU_EXCLUSIONS_FILE")" "$home/elsewhere.txt"
eq "location: names read from the saved file" \
  "$(env -u BFU_EXCLUSIONS_FILE HOME="$home" zsh -c "source '$src'; print -r -- \"\${BFU_EXCLUDED_CASKS[@]: -1}\"")" "zoom"

# --- closing summary
out=$(DRY_RUN=false BFU_FAILS=1 BFU_UPGRADED=3 BFU_SKIPPED_NAMES=(slack chrome) BFU_LOG=/x print_summary 9 2>&1)
[[ "$out" == *"3 upgraded"*"2 skipped"*"1 failed"* && "$out" == *"slack, chrome"* && "$out" == *"Finished with 1 failure"* ]] \
  && ok "summary: counts, skipped names, failure banner" || bad "summary" "$out"

# --- colour handling
out=$(NO_COLOR=1 zsh -c "source '$src'; _bfu_init_ui; print_status '✓' \"\$accent_green\" hi" | LC_ALL=C grep -c $'\033' )
eq "NO_COLOR: no escape codes" "$out" "0"
out=$(zsh -c "source '$src'; _bfu_init_ui; print_status '✓' \"\$accent_green\" hi" | LC_ALL=C grep -c $'\033' )
eq "piped output: no escape codes" "$out" "0"

# --- version bump classification and badges
eq "bump: major" "$(_bfu_bump 1.25.0 2.0.0)" "major"
eq "bump: minor" "$(_bfu_bump 1.25.0 1.26.0)" "minor"
eq "bump: patch" "$(_bfu_bump 1.25.0 1.25.3)" "patch"
eq "bump: multi-version current uses the first" "$(_bfu_bump "1.0, 0.9" 1.1)" "minor"
eq "bump: non-numeric falls back to update" "$(_bfu_bump latest 2.0)" "update"
eq "bump: casks with commas" "$(_bfu_bump 130.0.1 "131.0.2,abc")" "major"

# --- hints for known failures
[[ "$(_bfu_hint "Your Command Line Tools (CLT) does not support macOS 27.")" == *"xcode-select --install"* ]] && ok "hint: Command Line Tools" || bad "hint CLT" ""
eq "hint: unknown errors get no hint" "$(_bfu_hint "something odd")" ""

# --- progress line and gradient
eq "bar: half filled" "$(_bfu_bar 4 8 8 | LC_ALL=en_US.UTF-8 sed 's/\x1b\[[0-9;]*m//g')" "━━━━────"
eq "bar: never empty once started" "$(_bfu_bar 1 100 8 | sed 's/\x1b\[[0-9;]*m//g')" "━───────"
eq "gradient: plain text without colours" "$(reset="" _bfu_gradient "Brew")" "Brew"

# --- long failure reasons wrap instead of being cut off
BFU_W=50; BFU_LAST_ERROR="Your Command Line Tools do not support this version of macOS and must be updated before building"
out=$(print_failure_reason); rows=$(print "$out" | wc -l | tr -d ' ')
[[ "$rows" -ge 3 && "$out" == *"building"* ]] && ok "failure reason: wraps long text, nothing lost" || bad "wrap" "$out"
BFU_W=78; BFU_LAST_ERROR=""

# --- spinner/retry helper (non-TTY, so no spinner output)
BFU_LOG=$(mktemp); BFU_RETRIED=""; BFU_RUN_SECS=0
_bfu_attempt "T" true; rc=$?
eq "attempt: success, no retry" "$rc/${BFU_RETRIED:-none}" "0/none"
_bfu_attempt "T" false >/dev/null; rc=$?
eq "attempt: failure retried once, returns failure" "$rc/$BFU_RETRIED" "1/1"
flag=$(mktemp -u)
flaky() { if [[ -e "$flag" ]]; then return 0; else touch "$flag"; return 1; fi }
_bfu_attempt "T" flaky >/dev/null; rc=$?
eq "attempt: fails then succeeds on retry" "$rc/$BFU_RETRIED" "0/1"
eq "attempt note: retried" "$(_bfu_attempt_note | tr -d ' ' | sed 's/[0-9]*s/Ns/')" "(Ns,retried)"
rm -f "$flag"
_bfu_attempt "T" sh -c 'echo "Error: Your CLT does not support macOS 27." >&2; echo "more noise" >&2; exit 1' >/dev/null
eq "failure reason: first Error line, prefix removed" "$BFU_LAST_ERROR" "Your CLT does not support macOS 27."
out=$(BFU_LAST_ERROR="Error: boom" print_failure_reason)
[[ "$out" == *"┃ Error: boom"* ]] && ok "failure reason: printed under the result" || bad "print_failure_reason" "$out"
_bfu_attempt "T" true; eq "failure reason: cleared after a success" "$BFU_LAST_ERROR" ""
BFU_FAILS=0
eq "attempt: output of the command lands in the log" "$( _bfu_attempt "T" echo hello-from-step; grep -c '^hello-from-step$' "$BFU_LOG")" "1"

# --- box rows are exactly as wide as the box borders
BFU_W=78
w_top=$(_bfu_box_top | sed 's/\x1b\[[0-9;]*m//g'); w_row=$(_bfu_box_row "ab" "ab" "cd" "cd" | sed 's/\x1b\[[0-9;]*m//g')
eq "box: row width equals border width" "${#w_row}" "${#w_top}"
BFU_W=60; w_top=$(_bfu_box_top); w_row=$(_bfu_box_row "left" "left" "right" "right")
eq "box: stays aligned on a narrow layout" "${#w_row}" "${#w_top}"
BFU_W=78

# --- coloured box rows render escapes, never the literal text "\033"
out=$(reset='\033[0m' bold='\033[1m' _bfu_box_row "x" "${bold}x${reset}" "" "" )
[[ "$out" != *'\033'* ]] && ok "box row: colour codes are interpreted" || bad "box row escapes" "$out"

# --- narrow layout: summary rows and header never overflow the box
BFU_W=50; BFU_STEP=0; BFU_STEP_TITLES=(); BFU_STEP_SECS=(); BFU_STEP_NOTES=(); BFU_STEP_T0=""
print_section "Dev runtimes" >/dev/null; _bfu_step_note "Node ✓ · Python ✓ · Ruby ✓ · and a very long extra note"
out=$(DRY_RUN=false BFU_FAILS=0 BFU_UPGRADED=0 BFU_SKIPPED_NAMES=() BFU_LOG=/x print_summary 3 2>&1)
w_top=$(print -r -- "$out" | grep "╭" | head -1); bad_rows=0
while IFS= read -r l; do [[ "$l" == *"│"* && ${#l} -ne ${#w_top} ]] && bad_rows=$((bad_rows+1)); done <<< "$out"
eq "narrow summary: every row as wide as the border" "$bad_rows" "0"
BFU_W=78; BFU_STEP=0; BFU_STEP_TITLES=(); BFU_STEP_SECS=(); BFU_STEP_NOTES=()

# --- step bookkeeping and summary rows
BFU_STEP=0; BFU_STEP_TITLES=(); BFU_STEP_SECS=(); BFU_STEP_NOTES=(); BFU_STEP_T0=""
print_section "Formulae" >/dev/null; _bfu_step_note "2 upgraded"
print_section "Casks" >/dev/null; _bfu_step_note "up to date"
out=$(DRY_RUN=false BFU_FAILS=0 BFU_UPGRADED=2 BFU_SKIPPED_NAMES=() BFU_LOG=/x print_summary 5 2>&1)
[[ "$out" == *"Update complete"* && "$out" == *"Formulae"*"2 upgraded"* && "$out" == *"Casks"*"up to date"* ]] \
  && ok "summary: step rows with notes" || bad "summary rows" "$out"
eq "step titles recorded in order" "${BFU_STEP_TITLES[*]}" "Formulae Casks"

# --- aligned queue
BFU_NAME_W=$(_bfu_name_width $'a (1) < 2\nlonger-name (1) < 2')
eq "queue: name column fits longest name" "$BFU_NAME_W" "11"
eq "count: singular" "$(_bfu_count 1 formula formulae)" "1 formula"
eq "count: plural"   "$(_bfu_count 3 formula formulae)" "3 formulae"

# --- casks are skipped, not attempted, when admin authentication failed
BFU_STEP=0; BFU_STEP_TITLES=(); BFU_STEP_NOTES=(); BFU_STEP_SECS=(); BFU_STEP_T0=""
called=$(mktemp -u); brew() { touch "$called"; }
out=$(DRY_RUN=false ADMIN_OK=false OUTDATED_CASKS="raycast (1) != 2" BFU_LOG=/dev/null update_casks 2>&1)
[[ "$out" == *"no admin access"* && ! -e "$called" ]] && ok "casks: skipped without admin access, brew not run" || bad "admin skip" "$out"
unset -f brew; rm -f "$called"

# --- orchestrator, with a fake brew and no network
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/brew" <<'B'
#!/bin/zsh
case "$1" in
  outdated) [[ "$2" == --formula ]] && echo "wget (1.0) < 2.0" ;;
  info) echo '{"formulae":[],"casks":[]}' ;;
  install) [[ "$*" == *badcask* ]] && { echo "Error: It seems there is already an App at '/Applications/Bad.app'."; exit 1; } ;;
esac
exit 0
B
cat > "$tmp/nc" <<'B'
#!/bin/zsh
exit ${FAKE_NC_RC:-0}
B
chmod +x "$tmp/brew" "$tmp/nc"
run() { FAKE_NC_RC=$1 HOME="$tmp" PATH="$tmp:/usr/bin:/bin:/usr/sbin:/sbin" zsh -c "BFU_EXCLUDED_CASKS=(alfred); source '$src'; brew_full_update --dry-run; echo EXIT=\$?" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }

out=$(run 1)
[[ "$out" == *"Update aborted"* && "$out" == *"EXIT=1"* && "$out" != *"Update complete"* && "$out" != *"Dry run complete"* ]] \
  && ok "network down: aborts, exit 1, no COMPLETE banner" || bad "network abort" "$out"
out=$(run 0)
[[ "$out" == *"wget"*"1.0"*"2.0"* && "$out" == *"Dry run complete"* && "$out" == *"EXIT=0"* ]] \
  && ok "dry run: shows versions, completes, exit 0" || bad "dry run" "$out"
[[ "$out" == *"Excluding: alfred"* ]] && ok "dry run: exclusion note from config" || bad "exclusion note" "$out"
[[ -f "$tmp/Library/Logs/brew-full-update.log" ]] && ok "log file created under HOME" || bad "log file" "missing"

# --- adopting apps and adding taps
run_mode() { HOME="$tmp" PATH="$tmp:/usr/bin:/bin:/usr/sbin:/sbin" BFU_EVENTS=1 zsh -c "source '$src'; brew_full_update $1; echo EXIT=\$?" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
out=$(run_mode "--adopt goodcask")
[[ "$out" == *"@@BFU item|1|1|goodcask|"* && "$out" == *"@@BFU result|done|Adopted"* && "$out" == *"EXIT=0"* ]] \
  && ok "adopt: an adoption reports its item and result" || bad "adopt success" "$out"
out=$(run_mode "--adopt badcask")
[[ "$out" == *"@@BFU result|fail|Could not adopt"* && "$out" == *"@@BFU reason|It seems there is already an App"* && "$out" == *"EXIT=1"* ]] \
  && ok "adopt: a failure carries Homebrew's reason and exits 1" || bad "adopt failure" "$out"
out=$(run_mode "--tap me/tools")
[[ "$out" == *"@@BFU item|1|1|me/tools|"* && "$out" == *"@@BFU result|done|Added"* && "$out" == *"EXIT=0"* ]] \
  && ok "tap: adding a tap reports its item and result" || bad "tap success" "$out"
out=$(run_mode "--adopt")
[[ "$out" == *"Usage: brew_full_update --adopt"* && "$out" == *"EXIT=2"* ]] \
  && ok "adopt: no cask given prints usage, exit 2" || bad "adopt usage" "$out"
out=$(run_mode "--adopt-scan")
[[ "$out" == *"@@BFU scandone|"* && "$out" == *"EXIT=0"* ]] \
  && ok "adopt: the scan ends with a scandone event" || bad "adopt scan" "$out"

print "\n$pass passed, $fail failed"
(( fail == 0 ))
