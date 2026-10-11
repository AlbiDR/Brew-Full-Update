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

# --- closing summary
out=$(DRY_RUN=false BFU_FAILS=1 BFU_UPGRADED=3 BFU_SKIPPED_NAMES=(slack chrome) BFU_LOG=/x print_summary 9 2>&1)
[[ "$out" == *"3 upgraded"*"2 skipped"*"1 failed"* && "$out" == *"slack, chrome"* && "$out" == *"Finished with 1 failure"* ]] \
  && ok "summary: counts, skipped names, failure banner" || bad "summary" "$out"

# --- colour handling
out=$(NO_COLOR=1 zsh -c "source '$src'; _bfu_init_ui; print_status '✓' \"\$accent_green\" hi" | LC_ALL=C grep -c $'\033' )
eq "NO_COLOR: no escape codes" "$out" "0"
out=$(zsh -c "source '$src'; _bfu_init_ui; print_status '✓' \"\$accent_green\" hi" | LC_ALL=C grep -c $'\033' )
eq "piped output: no escape codes" "$out" "0"

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
[[ "$out" == *"↳ Error: boom"* ]] && ok "failure reason: printed under the result" || bad "print_failure_reason" "$out"
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

print "\n$pass passed, $fail failed"
(( fail == 0 ))
