#!/bin/zsh
# Dependency-free tests for brew_full_update.zsh. Run: tests/run.sh
# Uses a fake `brew` on PATH, so nothing on the real system is touched.
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

# --- failure counter
BFU_FAILS=0
print_action_result x fail >/dev/null; print_action_result y done >/dev/null; print_action_result z fail >/dev/null
eq "fail counter counts only failures" "$BFU_FAILS" "2"

# --- orchestrator, with a fake brew and no network
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/brew" <<'B'
#!/bin/zsh
case "$1" in
  outdated) [[ "$2" == --formula ]] && echo "wget (1.0) < 2.0" ;;
  info) echo '{"formulae":[],"casks":[]}' ;;
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
[[ "$out" == *"UPDATE ABORTED"* && "$out" == *"EXIT=1"* && "$out" != *"UPDATE COMPLETE"* ]] \
  && ok "network down: aborts, exit 1, no COMPLETE banner" || bad "network abort" "$out"
out=$(run 0)
[[ "$out" == *"wget"*"1.0"*"2.0"* && "$out" == *"UPDATE COMPLETE"* && "$out" == *"EXIT=0"* ]] \
  && ok "dry run: shows versions, completes, exit 0" || bad "dry run" "$out"
[[ "$out" == *"Excluding: alfred"* ]] && ok "dry run: exclusion note from config" || bad "exclusion note" "$out"
[[ -f "$tmp/Library/Logs/brew-full-update.log" ]] && ok "log file created under HOME" || bad "log file" "missing"

print "\n$pass passed, $fail failed"
(( fail == 0 ))
