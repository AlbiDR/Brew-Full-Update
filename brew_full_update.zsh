#!/usr/bin/env zsh

# ============================================================================
# BREW FULL UPDATE (v9.0)
# One command to update Homebrew formulae and casks, Mac App Store apps and
# language-runtime installs, then clean up and report what happened.
# ============================================================================

BFU_VERSION="9.0"

# ----------------------------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------------------------
# Casks whose names START with one of these are never upgraded.
# Override by defining BFU_EXCLUDED_CASKS before this file is sourced.
(( ${+BFU_EXCLUDED_CASKS} )) || BFU_EXCLUDED_CASKS=(
  alfred
  daisydisk
  gemini
  macdroid
  topaz-gigapixel
  topaz-photo
  topaz-video
  commander-one
)

# ============================================================================
# STYLE
# ============================================================================
# Layout width and colours are (re)computed on every run by _bfu_init_ui, so
# piped output and NO_COLOR get plain text without affecting later runs.
typeset -g BFU_W=78
reset='' bold='' dim='' accent_blue='' accent_cyan='' accent_green='' accent_amber='' accent_red=''

# Per-run step tracking, used for the closing summary.
typeset -g BFU_STEP=0 BFU_STEP_T0=""
typeset -ga BFU_STEP_TITLES BFU_STEP_SECS BFU_STEP_NOTES

_bfu_init_ui() {
  # Box padding counts characters, so a UTF-8 locale is required (the app may launch us without one).
  [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]* ]] || export LC_CTYPE=en_US.UTF-8

  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    reset='\033[0m';  bold='\033[1m';  dim='\033[38;5;244m'
    accent_blue='\033[38;5;75m';    accent_cyan='\033[38;5;80m'
    accent_green='\033[38;5;114m';  accent_amber='\033[38;5;179m'
    accent_red='\033[38;5;203m'
  else
    reset='' bold='' dim='' accent_blue='' accent_cyan='' accent_green='' accent_amber='' accent_red=''
  fi

  # Fit the terminal when it is narrower than the default 78-column layout.
  local cols=${COLUMNS:-0}
  (( cols > 0 )) || cols=$(tput cols 2>/dev/null || echo 80)
  BFU_W=78
  (( cols - 2 < BFU_W )) && BFU_W=$(( cols - 2 ))
  (( BFU_W < 50 )) && BFU_W=50
}

# ============================================================================
# LAYOUT PRIMITIVES
# ============================================================================

# draw_line CHAR COUNT
draw_line() {
  local char="$1" len="$2" i
  for ((i=0; i<len; i++)); do printf "%s" "$char"; done
}

# One row inside a box: left text, right text, padded to the box width.
# _bfu_box_row LEFT_PLAIN LEFT_STYLED RIGHT_PLAIN RIGHT_STYLED
_bfu_box_row() {
  local inner=$(( BFU_W - 2 ))
  local space=$(( inner - 2 - ${#1} - ${#3} ))
  (( space < 1 )) && space=1
  printf "  ${accent_blue}│${reset} %b%*s%b ${accent_blue}│${reset}\n" "$2" "$space" "" "$4"
}

_bfu_box_top()    { printf "  ${accent_blue}╭$(draw_line ─ $(( BFU_W - 2 )))╮${reset}\n"; }
_bfu_box_divider(){ printf "  ${accent_blue}├$(draw_line ─ $(( BFU_W - 2 )))┤${reset}\n"; }
_bfu_box_bottom() { printf "  ${accent_blue}╰$(draw_line ─ $(( BFU_W - 2 )))╯${reset}\n"; }

# ============================================================================
# SECTIONS & STATUS LINES
# ============================================================================

# Close out the timing of the step that is currently open.
_bfu_step_close() {
  [[ -n "$BFU_STEP_T0" ]] && BFU_STEP_SECS[$BFU_STEP]=$(( SECONDS - BFU_STEP_T0 ))
  BFU_STEP_T0=""
}

# Remember a short result for the current step (shown in the closing summary).
_bfu_step_note() {
  BFU_STEP_NOTES[$BFU_STEP]="$1"
}

# Header banner: name and version, then machine context.
print_top_banner() {
  local title="$1"
  local host macos brewv when sub max
  host=$(scutil --get ComputerName 2>/dev/null || hostname -s)
  macos=$(sw_vers -productVersion 2>/dev/null)
  brewv=$(brew --version 2>/dev/null | head -1 | sed -E 's/-[0-9]+-g[0-9a-f]+$//')
  when=$(date '+%a %-d %b, %H:%M')
  sub="${host} · macOS ${macos} · ${brewv} · ${when}"
  max=$(( BFU_W - 6 ))
  (( ${#sub} > max )) && sub="${sub[1,max-1]}…"

  local right_plain="v${BFU_VERSION}" right_styled="${dim}v${BFU_VERSION}${reset}"
  if [[ "$DRY_RUN" == true ]]; then
    right_plain="dry run  v${BFU_VERSION}"
    right_styled="${accent_amber}dry run${reset}  ${dim}v${BFU_VERSION}${reset}"
  fi

  printf "\n"
  _bfu_box_top
  _bfu_box_row "$title" "${bold}${title}${reset}" "$right_plain" "$right_styled"
  _bfu_box_row "$sub" "${dim}${sub}${reset}" "" ""
  _bfu_box_bottom
}

# Numbered section rule: "── 2 · Formulae ─────────────"
print_section() {
  _bfu_step_close
  BFU_STEP=$(( BFU_STEP + 1 ))
  BFU_STEP_TITLES[$BFU_STEP]="$1"
  BFU_STEP_T0=$SECONDS
  local label="${BFU_STEP} · $1"
  local fill=$(( BFU_W - ${#label} - 4 ))
  printf "\n  ${accent_blue}──${reset} ${bold}%s${reset} ${accent_blue}%s${reset}\n\n" "$label" "$(draw_line ─ $fill)"
}

print_subsection() {
  printf "\n    ${bold}${accent_cyan}▸${reset} ${bold}%s${reset}\n" "$1"
}

# print_status SYMBOL COLOR MESSAGE
print_status() {
  printf "    ${2}${1}${reset}  ${3}\n"
}

# [1/3]  name  1.0 → 2.0
print_action_start() {
  printf "    ${dim}[${reset}${accent_cyan}%s${dim}/${reset}${accent_cyan}%s${dim}]${reset}  ${bold}%s${reset}  ${dim}%s${reset}\n" "$1" "$2" "$3" "$4"
}

# Aligned upgrade-queue row: name, current version, new version.
print_item_with_versions() {
  local name="$1" current="$2" new="$3"
  if [[ -z "$new" ]]; then
    printf "      ${accent_amber}↑${reset}  %-*s  ${dim}%s${reset}\n" "${BFU_NAME_W:-28}" "$name" "$current"
  else
    printf "      ${accent_amber}↑${reset}  %-*s  ${dim}%s${reset} → ${accent_green}%s${reset}\n" "${BFU_NAME_W:-28}" "$name" "$current" "$new"
  fi
}

print_action_result() {
  local action="$1" res_status="$2" symbol="" color=""
  case "$res_status" in
    "done") symbol="✓"; color="$accent_green" ;;
    "skip") symbol="○"; color="$accent_cyan" ;;
    "fail") symbol="✗"; color="$accent_red"; BFU_FAILS=$(( BFU_FAILS + 1 )) ;;
  esac
  printf "          ${color}${symbol} ${action}${reset}\n"
}

# Closing summary card: overall result, one row per step, total time.
print_summary() {
  local duration="$1"
  _bfu_step_close

  local title_plain title_styled
  if [[ "$DRY_RUN" == true ]]; then
    title_plain="Dry run complete · no changes made"
    title_styled="${bold}${accent_amber}Dry run complete${reset} ${dim}· no changes made${reset}"
  elif (( BFU_FAILS > 0 )); then
    title_plain="! Finished with ${BFU_FAILS} failure(s)"
    title_styled="${bold}${accent_amber}! Finished with ${BFU_FAILS} failure(s)${reset}"
  else
    title_plain="✓ Update complete"
    title_styled="${bold}${accent_green}✓ Update complete${reset}"
  fi

  printf "\n"
  _bfu_box_top
  _bfu_box_row "$title_plain" "$title_styled" "${duration}s" "${dim}${duration}s${reset}"
  _bfu_box_divider
  local i name note secs
  for (( i = 1; i <= ${#BFU_STEP_TITLES}; i++ )); do
    name="${BFU_STEP_TITLES[i]}"
    note="${BFU_STEP_NOTES[i]:-done}"
    secs="${BFU_STEP_SECS[i]:-0}"
    _bfu_box_row "${(r:14:)name}${note}" "${dim}${(r:14:)name}${reset}${note}" "${secs}s" "${dim}${secs}s${reset}"
  done
  _bfu_box_bottom

  if [[ "$DRY_RUN" != true ]]; then
    local fail_color="$dim"
    (( BFU_FAILS > 0 )) && fail_color="$accent_red"
    printf "\n  ${accent_green}%s upgraded${reset} ${dim}·${reset} ${accent_cyan}%s skipped${reset} ${dim}·${reset} ${fail_color}%s failed${reset}\n" \
      "$BFU_UPGRADED" "${#BFU_SKIPPED_NAMES}" "$BFU_FAILS"
    if (( ${#BFU_SKIPPED_NAMES} > 0 )); then
      printf "  ${dim}Still running, so not upgraded: ${(j:, :)BFU_SKIPPED_NAMES}. Quit and run again to update them.${reset}\n"
    fi
    (( BFU_FAILS > 0 )) && printf "  ${dim}Details: ${BFU_LOG}${reset}\n"
  fi
  printf "\n"

  # Native macOS notification
  if [[ "$DRY_RUN" != true ]]; then
    if (( BFU_FAILS > 0 )); then
      osascript -e "display notification \"${BFU_FAILS} step(s) failed. See ~/Library/Logs/brew-full-update.log\" with title \"Brew Command Center\" subtitle \"Finished with failures\"" 2>/dev/null
    else
      osascript -e "display notification \"${BFU_UPGRADED} upgraded, ${#BFU_SKIPPED_NAMES} skipped\" with title \"Brew Command Center\" subtitle \"Update complete\"" 2>/dev/null
    fi
  fi
}

# ============================================================================
# 1 · DIAGNOSTICS
# ============================================================================

check_system_health() {
  print_section "Diagnostics"

  # Network guard
  if ! nc -zw1 1.1.1.1 443 &>/dev/null; then
    print_status "✗" "$accent_red" "No network connection"
    return 1
  fi
  print_status "✓" "$accent_green" "Network reachable"

  # Refresh the index with a spinner. A failure here is not fatal: cached data is used.
  local t0=$SECONDS
  BFU_SPIN_INDENT=4
  if _bfu_run "Updating Homebrew index" brew update; then
    print_status "✓" "$accent_green" "Homebrew index refreshed ${dim}($(( SECONDS - t0 ))s)${reset}"
  else
    print_status "!" "$accent_amber" "Could not refresh the index, using cached data"
  fi
  BFU_SPIN_INDENT=""
  brew analytics off > /dev/null 2>&1 || true

  OUTDATED_FORMULAE=$(brew outdated --formula --verbose 2>/dev/null)
  OUTDATED_CASKS=$(brew outdated --cask --verbose 2>/dev/null | _bfu_filter_excluded)

  local f_count=0 c_count=0
  [[ -n "$OUTDATED_FORMULAE" ]] && f_count=$(echo "$OUTDATED_FORMULAE" | wc -l | tr -d ' ')
  [[ -n "$OUTDATED_CASKS" ]] && c_count=$(echo "$OUTDATED_CASKS" | wc -l | tr -d ' ')
  local total_outdated=$(( f_count + c_count ))

  if (( total_outdated > 0 )); then
    print_status "✓" "$accent_green" "$(_bfu_count "$total_outdated" update updates) available ${dim}($(_bfu_count "$f_count" formula formulae), $(_bfu_count "$c_count" cask casks))${reset}"
    _bfu_step_note "$(_bfu_count "$total_outdated" update updates) found"
    if [[ "$DRY_RUN" != true ]]; then
      (
        local f_list=$(echo "$OUTDATED_FORMULAE" | awk '{print $1}')
        local c_list=$(echo "$OUTDATED_CASKS" | awk '{print $1}')
        if [[ -n "$f_list" ]]; then echo "$f_list" | xargs brew fetch --formula >/dev/null 2>&1; fi
        if [[ -n "$c_list" ]]; then echo "$c_list" | xargs brew fetch --cask >/dev/null 2>&1; fi
      ) &
      PREFETCH_PID=$!
      print_status "·" "$dim" "${dim}Downloads are pre-fetching in the background${reset}"
    fi
  else
    print_status "✓" "$accent_green" "Everything is up to date"
    _bfu_step_note "up to date"
  fi

  # Health
  local missing_deps deprecated_items
  missing_deps=$(brew missing 2>/dev/null)
  deprecated_items=$(_bfu_deprecated)

  if [[ -z "$missing_deps" && -z "$deprecated_items" ]]; then
    print_status "✓" "$accent_green" "No missing or deprecated packages"
  else
    [[ -n "$missing_deps" ]] && print_status "!" "$accent_amber" "Missing dependencies: $missing_deps"
    if [[ -n "$deprecated_items" ]]; then
      print_subsection "Deprecated packages"
      local line
      while read -r line; do
        print_status "!" "$accent_red" "$line"
      done <<< "$deprecated_items"
    fi
  fi
}

# ============================================================================
# SHARED UPGRADE HELPERS
# ============================================================================

# "1 formula" / "3 formulae"
_bfu_count() {
  if (( $1 == 1 )); then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi
}

# Width of the longest package name in an outdated list (capped), for aligned columns.
_bfu_name_width() {
  local line name max=8
  while read -r line; do
    name="${line%% *}"
    (( ${#name} > max )) && max=${#name}
  done <<< "$1"
  (( max > 34 )) && max=34
  printf '%s' "$max"
}

# Print an outdated list as an aligned queue.
_bfu_print_queue() {
  local list="$1" line name
  BFU_NAME_W=$(_bfu_name_width "$list")
  while read -r line; do
    name="${line%% *}"
    print_item_with_versions "$name" "$(_bfu_current_ver "$line")" "$(_bfu_new_ver "$line")"
  done <<< "$list"
}

# Wait for the background pre-fetch started during diagnostics, if any.
_bfu_wait_prefetch() {
  [[ -n "$PREFETCH_PID" ]] || return 0
  printf "    ${dim}Waiting for downloads to finish...${reset}\n"
  wait "$PREFETCH_PID" 2>/dev/null
  PREFETCH_PID=""
}

# ============================================================================
# 2 · FORMULAE
# ============================================================================

update_formulae() {
  print_section "Formulae"

  if [[ -z "$OUTDATED_FORMULAE" ]]; then
    print_status "✓" "$accent_green" "All formulae are up to date"
    _bfu_step_note "up to date"
    return
  fi

  local count=$(echo "$OUTDATED_FORMULAE" | wc -l | tr -d ' ')
  print_status "›" "$accent_cyan" "$(_bfu_count "$count" formula formulae) to upgrade"

  print_subsection "Upgrade queue"
  _bfu_print_queue "$OUTDATED_FORMULAE"

  if [[ "$DRY_RUN" == true ]]; then
    printf "\n    ${dim}Dry run: nothing will be installed.${reset}\n"
    _bfu_step_note "$count would be upgraded"
    return
  fi

  print_subsection "Installing"
  _bfu_wait_prefetch

  local i=1 ok=0 bad=0 line pkg_name
  while read -r line; do
    pkg_name="${line%% *}"
    print_action_start "$i" "$count" "$pkg_name" "$(_bfu_current_ver "$line") → $(_bfu_new_ver "$line")"

    if _bfu_attempt "Installing" brew upgrade --formula "$pkg_name"; then
      BFU_UPGRADED=$(( BFU_UPGRADED + 1 )); ok=$(( ok + 1 ))
      print_action_result "Installed and verified$(_bfu_attempt_note)" "done"
    else
      bad=$(( bad + 1 ))
      print_action_result "Installation failed$(_bfu_attempt_note)" "fail"
    fi
    i=$(( i + 1 ))
  done <<< "$OUTDATED_FORMULAE"

  local note="${ok} upgraded"
  (( bad > 0 )) && note+=" · ${bad} failed"
  _bfu_step_note "$note"
}

# ============================================================================
# 3 · CASKS
# ============================================================================

update_casks() {
  print_section "Casks"
  printf "    ${dim}$(_bfu_excluded_note)${reset}\n\n"

  if [[ -z "$OUTDATED_CASKS" ]]; then
    print_status "✓" "$accent_green" "All applications are up to date"
    _bfu_step_note "up to date"
    return
  fi

  local count=$(echo "$OUTDATED_CASKS" | wc -l | tr -d ' ')
  print_status "›" "$accent_cyan" "$(_bfu_count "$count" application applications) to upgrade"

  print_subsection "Upgrade queue"
  _bfu_print_queue "$OUTDATED_CASKS"

  if [[ "$DRY_RUN" == true ]]; then
    printf "\n    ${dim}Dry run: nothing will be installed.${reset}\n"
    _bfu_step_note "$count would be upgraded"
    return
  fi

  print_subsection "Installing"
  _bfu_wait_prefetch

  local j=1 ok=0 bad=0 skipped=0 line cask_name
  while read -r line; do
    cask_name="${line%% *}"
    print_action_start "$j" "$count" "$cask_name" "$(_bfu_current_ver "$line") → $(_bfu_new_ver "$line")"

    if _bfu_cask_running "$cask_name"; then
      BFU_SKIPPED_NAMES+=("$cask_name"); skipped=$(( skipped + 1 ))
      print_action_result "Application running (skipped)" "skip"
    else
      if _bfu_attempt "Deploying" brew upgrade --cask --force "$cask_name"; then
        BFU_UPGRADED=$(( BFU_UPGRADED + 1 )); ok=$(( ok + 1 ))
        print_action_result "Deployed and verified$(_bfu_attempt_note)" "done"
      else
        bad=$(( bad + 1 ))
        print_action_result "Deployment failed$(_bfu_attempt_note)" "fail"
      fi
    fi
    j=$(( j + 1 ))
  done <<< "$OUTDATED_CASKS"

  local note="${ok} upgraded"
  (( skipped > 0 )) && note+=" · ${skipped} skipped"
  (( bad > 0 )) && note+=" · ${bad} failed"
  _bfu_step_note "$note"
}

# ============================================================================
# 4 · APP STORE
# ============================================================================

update_app_store() {
  print_section "App Store"

  if ! command -v mas &> /dev/null; then
    print_status "!" "$accent_amber" "mas is not installed (skipped)"
    _bfu_step_note "mas not installed"
    return
  fi

  export MAS_NO_AUTO_INDEX=1

  local mas_out
  mas_out=$(mas outdated 2>/dev/null)

  if [[ -z "$mas_out" ]]; then
    print_status "✓" "$accent_green" "All App Store apps are up to date"
    _bfu_step_note "up to date"
    return
  fi

  local n=$(echo "$mas_out" | wc -l | tr -d ' ')
  print_status "›" "$accent_cyan" "$(_bfu_count "$n" update updates) available"
  print_subsection "Pending"
  local line
  while read -r line; do
    printf "      ${accent_amber}↑${reset}  %s\n" "$line"
  done <<< "$mas_out"

  if [[ "$DRY_RUN" == true ]]; then
    printf "\n    ${dim}Dry run: nothing will be installed.${reset}\n"
    _bfu_step_note "$n would be updated"
    return
  fi

  print_subsection "Updating"
  if _bfu_attempt "Updating" mas upgrade; then
    print_action_result "App Store synchronized$(_bfu_attempt_note)" "done"
    _bfu_step_note "$n updated"
  else
    print_action_result "Sync failed, sign in to the App Store and retry$(_bfu_attempt_note)" "fail"
    _bfu_step_note "failed"
  fi
}

# ============================================================================
# 5 · DEV RUNTIMES
# ============================================================================

sync_dev_environments() {
  print_section "Dev runtimes"

  if [[ "$DRY_RUN" == true ]]; then
    print_status "·" "$dim" "${dim}Node, Python and Ruby environments would be synced${reset}"
    _bfu_step_note "dry run"
    return
  fi

  local tool label note=""
  for tool label in nodenv Node pyenv Python rbenv Ruby; do
    _bfu_log "brew ${tool}-sync"
    if brew "${tool}-sync" >> "$BFU_LOG" 2>&1; then
      print_status "✓" "$accent_green" "$label synced"
      note+="${note:+ · }${label} ✓"
    else
      print_status "○" "$accent_cyan" "${label} skipped ${dim}(${tool} not set up)${reset}"
      note+="${note:+ · }${label} ○"
    fi
  done
  _bfu_step_note "$note"
}

# ============================================================================
# 6 · CLEANUP
# ============================================================================

optimize_storage() {
  print_section "Cleanup"

  if [[ "$DRY_RUN" == true ]]; then
    print_status "·" "$dim" "${dim}Skipped in dry run${reset}"
    _bfu_step_note "dry run"
    return
  fi

  _bfu_log "brew autoremove"
  BFU_SPIN_INDENT=4
  _bfu_run "Removing unused dependencies" brew autoremove

  # Run cleanup through the log, then read what it reported.
  local offset
  offset=$(stat -f %z "$BFU_LOG")
  _bfu_log "brew cleanup --prune=7"
  _bfu_run "Clearing old downloads and versions" brew cleanup --prune=7
  BFU_SPIN_INDENT=""

  local freed
  freed=$(tail -c +"$(( offset + 1 ))" "$BFU_LOG" | sed -nE 's/.*freed approximately ([^ ]+).*/\1/p' | head -1)
  if [[ -n "$freed" ]]; then
    print_status "✓" "$accent_green" "Freed ${bold}${freed}${reset}"
    _bfu_step_note "freed ${freed}"
  else
    print_status "✓" "$accent_green" "Already tidy"
    _bfu_step_note "already tidy"
  fi
}

# ============================================================================
# PARSING & SAFETY HELPERS
# ============================================================================

# "name (1.0, 1.1) < 2.0 [pinned at 1.0]" -> "1.0, 1.1"
_bfu_current_ver() {
  echo "$1" | sed -nE 's/^[^(]*\(([^)]*)\).*/\1/p'
}

# "name (1.0) < 2.0" or "name (1.0) != 2.0" -> "2.0"
_bfu_new_ver() {
  echo "$1" | sed -nE 's/.*(<|!=) +([^ ]+).*/\2/p'
}

# "Excluding: a, b, c" or "Excluding: a, b +5 more", fitted to the layout width.
_bfu_excluded_note() {
  local max=$(( BFU_W - 10 )) full="${(j:, :)BFU_EXCLUDED_CASKS}"
  local total=${#BFU_EXCLUDED_CASKS} acc="" cand name n=0
  if (( ${#full} <= max )); then
    printf 'Excluding: %s' "$full"
    return
  fi
  for name in "${BFU_EXCLUDED_CASKS[@]}"; do
    cand="${acc:+$acc, }$name"
    (( ${#cand} + 10 > max )) && break
    acc="$cand"; n=$(( n + 1 ))
  done
  printf 'Excluding: %s +%d more' "$acc" $(( total - n ))
}

# Drop outdated-cask lines whose name starts with an excluded prefix.
_bfu_filter_excluded() {
  local excluded="${(j:|:)BFU_EXCLUDED_CASKS}"
  [[ -z "$excluded" ]] && { cat; return; }
  grep -v -E "^($excluded)"
}

# Print the .app bundle names a cask installs (one per line).
_bfu_cask_apps() {
  brew info --cask --json=v2 "$1" 2>/dev/null | /usr/bin/osascript -l JavaScript -e '
    ObjC.import("Foundation");
    var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    var text = $.NSString.alloc.initWithDataEncoding(data, 4).js;
    var out = [];
    JSON.parse(text).casks[0].artifacts.forEach(function (a) {
      (a.app || []).forEach(function (x) { if (typeof x === "string") out.push(x); });
    });
    out.join("\n");
  ' 2>/dev/null
}

# True if any app bundle belonging to the cask is currently running.
_bfu_cask_running() {
  local cask="$1" app
  while read -r app; do
    [[ -z "$app" ]] && continue
    pgrep -f "/${app}/Contents/MacOS/" > /dev/null 2>&1 && return 0
  done <<< "$(_bfu_cask_apps "$cask")"
  # Also covers pkg/binary-only casks (no app artifact): nothing to guard.
  return 1
}

# Append a header line to the run log.
_bfu_log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$BFU_LOG"
}

# Installed formulae/casks that Homebrew marks deprecated or disabled.
_bfu_deprecated() {
  brew info --json=v2 --installed 2>/dev/null | /usr/bin/osascript -l JavaScript -e '
    ObjC.import("Foundation");
    var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    var o = JSON.parse($.NSString.alloc.initWithDataEncoding(data, 4).js);
    var out = [];
    function flag(n, x) { if (x.disabled) out.push(n + " (disabled)"); else if (x.deprecated) out.push(n + " (deprecated)"); }
    (o.formulae || []).forEach(function (f) { flag(f.name, f); });
    (o.casks || []).forEach(function (c) { flag(c.token, c); });
    out.join("\n");
  ' 2>/dev/null
}

# Run a command in the background with a live spinner (TTY only).
# Output goes to the log. Returns the command's exit status.
_bfu_run() {
  local label="$1"; shift
  "$@" < /dev/null >> "$BFU_LOG" 2>&1 &
  BFU_CHILD_PID=$!
  if [[ -t 1 ]]; then
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) n=1 t0=$SECONDS indent="${BFU_SPIN_INDENT:-10}"
    printf '\033[?25l'
    while kill -0 "$BFU_CHILD_PID" 2>/dev/null; do
      printf "\r%*s${accent_cyan}%s${reset} ${dim}%s... %ss${reset}\033[K" "$indent" "" "${frames[n]}" "$label" "$((SECONDS - t0))"
      n=$(( n % ${#frames} + 1 ))
      sleep 0.1
    done
    printf '\r\033[K\033[?25h'
  fi
  wait "$BFU_CHILD_PID" 2>/dev/null
  local rc=$?
  BFU_CHILD_PID=""
  return $rc
}

# Run a command with a spinner; if it fails, retry once.
# Sets BFU_RUN_SECS (total seconds) and BFU_RETRIED (1 if a retry happened).
_bfu_attempt() {
  local label="$1"; shift
  local start=$SECONDS rc
  BFU_RETRIED=""
  _bfu_log "$*"
  _bfu_run "$label" "$@"; rc=$?
  if (( rc != 0 )); then
    BFU_RETRIED=1
    _bfu_log "FAILED (exit $rc), retrying once: $*"
    printf "          ${accent_amber}↻ Failed, retrying once${reset}\n"
    _bfu_run "$label (retry)" "$@"; rc=$?
  fi
  BFU_RUN_SECS=$(( SECONDS - start ))
  return $rc
}

# " (12s)" or " (12s, retried)" for the result line.
_bfu_attempt_note() {
  if [[ -n "$BFU_RETRIED" ]]; then
    printf ' (%ss, retried)' "$BFU_RUN_SECS"
  else
    printf ' (%ss)' "$BFU_RUN_SECS"
  fi
}

# Record installed versions in the log before anything is upgraded, for rollback.
_bfu_snapshot() {
  _bfu_log "PRE-UPGRADE SNAPSHOT: formulae"
  brew list --formula --versions >> "$BFU_LOG" 2>&1
  _bfu_log "PRE-UPGRADE SNAPSHOT: casks"
  brew list --cask --versions >> "$BFU_LOG" 2>&1
}

# Stop the sudo keepalive loop and any running step (globals so traps can see them).
_bfu_cleanup() {
  [[ -n "$BFU_CHILD_PID" ]] && kill "$BFU_CHILD_PID" 2>/dev/null
  BFU_CHILD_PID=""
  [[ -t 1 ]] && printf '\033[?25h'
  [[ -n "$SUDO_PID" ]] && kill "$SUDO_PID" 2>/dev/null
  SUDO_PID=""
}

# ============================================================================
# MAIN
# ============================================================================

brew_full_update() {
  setopt localoptions no_monitor localtraps

  if ! command -v brew &> /dev/null; then
    printf "Error: Homebrew not found. Install at https://brew.sh\n"
    return 1
  fi

  # Stop the sudo keepalive and any running step on exit or interrupt.
  trap '_bfu_cleanup' EXIT
  trap '_bfu_cleanup; printf "\n"; return 130' INT TERM

  local DRY_RUN=false
  local OUTDATED_FORMULAE=""
  local OUTDATED_CASKS=""
  local PREFETCH_PID=""
  typeset -g SUDO_PID=""
  typeset -g BFU_FAILS=0 BFU_UPGRADED=0 BFU_CHILD_PID="" BFU_RETRIED="" BFU_RUN_SECS=0 BFU_SPIN_INDENT=""
  typeset -g BFU_STEP=0 BFU_STEP_T0=""
  typeset -ga BFU_SKIPPED_NAMES=() BFU_STEP_TITLES=() BFU_STEP_SECS=() BFU_STEP_NOTES=()
  _bfu_init_ui

  typeset -g BFU_LOG="$HOME/Library/Logs/brew-full-update.log"
  mkdir -p "${BFU_LOG:h}"
  # Keep the log bounded: start fresh once it passes 1 MB.
  [[ -f "$BFU_LOG" && $(stat -f %z "$BFU_LOG") -gt 1048576 ]] && : > "$BFU_LOG"
  _bfu_log "=== brew_full_update ${1:-} ==="

  case "$1" in
    --dry-run|-d)
      DRY_RUN=true
      ;;
  esac

  local global_start=$SECONDS

  print_top_banner "Brew Command Center"

  # Admin rights: some cask installers need them. Skipped for dry runs.
  if [[ "$DRY_RUN" != true ]]; then
    printf "\n  ${accent_cyan}›${reset} Admin password needed for some app installers\n"
    if ! sudo -v; then
      print_status "✗" "$accent_red" "Admin authentication failed. Aborting."
      return 1
    fi
    # Keep the sudo session alive until we are done.
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!
  fi

  if ! check_system_health; then
    printf "\n  ${accent_red}✗ Update aborted${reset} ${dim}· check your network connection${reset}\n\n"
    return 1
  fi

  if [[ "$DRY_RUN" != true && ( -n "$OUTDATED_FORMULAE" || -n "$OUTDATED_CASKS" ) ]]; then
    _bfu_snapshot
    print_status "·" "$dim" "${dim}Installed versions saved to the log (rollback reference)${reset}"
  fi

  update_formulae
  update_casks
  update_app_store
  sync_dev_environments
  optimize_storage

  print_summary "$(( SECONDS - global_start ))"
}
