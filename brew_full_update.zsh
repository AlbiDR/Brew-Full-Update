#!/usr/bin/env zsh

# ============================================================================
# BREW FULL UPDATE (v11.0.1)
# One command to update Homebrew formulae and casks, Mac App Store apps and
# language-runtime installs, then clean up and report what happened.
# ============================================================================

BFU_VERSION="11.0.1"
BFU_TOTAL_STEPS=6

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

# Where the app's Exclusions button saves names: the file path chosen with its
# Location button (stored in exclusions-location.txt), else the default file.
_bfu_exclusions_file() {
  local saved="$HOME/Library/Application Support/Brew Full Update/exclusions-location.txt"
  if [[ -s "$saved" ]]; then
    head -n 1 "$saved"
  else
    print -r -- "$HOME/Library/Application Support/Brew Full Update/exclusions.txt"
  fi
}

# Names added with the app's Exclusions button, one per line. Blank lines and
# lines starting with # are ignored. Appended to the list above on every run.
BFU_EXCLUSIONS_FILE="${BFU_EXCLUSIONS_FILE:-$(_bfu_exclusions_file)}"
if [[ -r "$BFU_EXCLUSIONS_FILE" ]]; then
  BFU_EXCLUDED_CASKS+=(${(f)"$(sed -n -E 's/^[[:space:]]*([^#[:space:]]+).*/\1/p' "$BFU_EXCLUSIONS_FILE")"})
fi

# ============================================================================
# STYLE
# ============================================================================
# Layout width and colours are (re)computed on every run by _bfu_init_ui, so
# piped output and NO_COLOR get plain text without affecting later runs.
# Set BFU_FORCE_COLOR=1 to keep colours when piping (e.g. into `less -R`).
typeset -g BFU_W=78
reset='' bold='' dim='' track='' accent_blue='' accent_cyan='' accent_green='' accent_amber='' accent_red=''
typeset -ga BFU_GRAD=(69 75 81 80 79 78)

# Per-run state used by the closing summary.
typeset -g BFU_STEP=0 BFU_STEP_T0="" BFU_PENDING=0
typeset -ga BFU_STEP_TITLES BFU_STEP_SECS BFU_STEP_NOTES

_bfu_init_ui() {
  # Box padding counts characters, so a UTF-8 locale is required (the app may launch us without one).
  [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]* ]] || export LC_CTYPE=en_US.UTF-8

  if [[ ( -t 1 || -n "${BFU_FORCE_COLOR:-}" ) && -z "${NO_COLOR:-}" ]]; then
    reset='\033[0m';  bold='\033[1m';  dim='\033[38;5;245m';  track='\033[38;5;238m'
    accent_blue='\033[38;5;75m';    accent_cyan='\033[38;5;80m'
    accent_green='\033[38;5;114m';  accent_amber='\033[38;5;179m'
    accent_red='\033[38;5;203m'
  else
    reset='' bold='' dim='' track='' accent_blue='' accent_cyan='' accent_green='' accent_amber='' accent_red=''
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

# Text with a blue-to-teal gradient (plain text when colours are off).
_bfu_gradient() {
  local text="$1"
  if [[ -z "$reset" ]]; then printf '%s' "$text"; return; fi
  local out="" i n=${#text} idx
  for (( i = 1; i <= n; i++ )); do
    idx=$(( (i - 1) * ${#BFU_GRAD} / n + 1 ))
    out+="\033[38;5;${BFU_GRAD[idx]}m${text[i]}"
  done
  printf '%s' "${out}${reset}"
}

# Thin progress line: _bfu_bar DONE TOTAL [WIDTH]  ->  ━━━━────
_bfu_bar() {
  local done_=$1 total=$2 w=${3:-8} filled
  (( total > 0 )) || total=1
  filled=$(( done_ * w / total ))
  (( done_ > 0 && filled == 0 )) && filled=1
  (( filled > w )) && filled=$w
  printf '%b%s%b%s%b' "$accent_cyan" "$(draw_line ━ $filled)" "$track" "$(draw_line ─ $(( w - filled )))" "$reset"
}

# Window/tab title (TTY only).
_bfu_title() {
  [[ -t 1 ]] && printf '\033]0;%s\007' "$1"
  return 0
}

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
  _bfu_emit note "$1"
}

# Header banner: name and version, then machine context.
print_top_banner() {
  local title="◆ $1"
  local host macos brewv when sub max
  host=$(scutil --get ComputerName 2>/dev/null || hostname -s)
  macos=$(sw_vers -productVersion 2>/dev/null)
  brewv=$(brew --version 2>/dev/null | head -1 | sed -E 's/-[0-9]+-g[0-9a-f]+$//')
  # Without git (e.g. Command Line Tools missing) brew reports ">=x.y.z (shallow or no git repository)".
  brewv="${brewv%% [(]*}"
  [[ "$brewv" == *">="* || -z "$brewv" ]] && brewv="Homebrew"
  when=$(date '+%-d %b, %H:%M')
  sub="  ${host} · macOS ${macos} · ${brewv} · ${when}"
  max=$(( BFU_W - 5 ))
  (( ${#sub} > max )) && sub="${sub[1,max-1]}…"

  local right_plain="v${BFU_VERSION}" right_styled="${dim}v${BFU_VERSION}${reset}"
  if [[ "$DRY_RUN" == true ]]; then
    right_plain="dry run  v${BFU_VERSION}"
    right_styled="${bold}${accent_amber}dry run${reset}  ${dim}v${BFU_VERSION}${reset}"
  fi

  printf "\n"
  _bfu_box_top
  _bfu_box_row "$title" "${bold}$(_bfu_gradient "$title")${reset}" "$right_plain" "$right_styled"
  _bfu_box_row "$sub" "${dim}${sub}${reset}" "" ""
  _bfu_box_bottom
}

# Numbered section rule with a progress rail: "── 2 · Formulae ───────── ●●○○○○"
print_section() {
  _bfu_step_close
  BFU_STEP=$(( BFU_STEP + 1 ))
  BFU_STEP_TITLES[$BFU_STEP]="$1"
  BFU_STEP_T0=$SECONDS
  _bfu_emit step "$BFU_STEP" "$BFU_TOTAL_STEPS" "$1"

  local label="${BFU_STEP} · $1" i rail="" rail_plain=""
  for (( i = 1; i <= BFU_TOTAL_STEPS; i++ )); do
    rail_plain+="●"
    if (( i < BFU_STEP )); then rail+="${accent_blue}●${reset}"
    elif (( i == BFU_STEP )); then rail+="${bold}${accent_cyan}●${reset}"
    else rail+="${track}●${reset}"; fi
  done
  local fill=$(( BFU_W - ${#label} - ${#rail_plain} - 5 ))
  (( fill < 2 )) && fill=2
  printf "\n  ${accent_blue}──${reset} ${bold}%s${reset} ${accent_blue}%s${reset} %b\n\n" "$label" "$(draw_line ─ $fill)" "$rail"
  _bfu_title "Brew Full Update · ${BFU_STEP}/${BFU_TOTAL_STEPS} $1"
}

print_subsection() {
  printf "\n    ${bold}${accent_cyan}▸${reset} ${bold}%s${reset}\n" "$1"
}

# print_status SYMBOL COLOR MESSAGE
print_status() {
  printf "    ${2}${1}${reset}  ${3}\n"
}

# "2/5 ━━━━────  name  1.0 → 2.0": position, progress line, name, versions.
print_action_start() {
  local index="$1" total="$2" w=${#2}
  _bfu_emit item "$index" "$total" "$3" "$4"
  printf "    ${accent_cyan}%*s${dim}/%s${reset} %b  ${bold}%s${reset}  ${dim}%s${reset}\n" \
    "$w" "$index" "$total" "$(_bfu_bar "$index" "$total" 8)" "$3" "$4"
}

# major / minor / patch / update, from two version strings.
_bfu_bump() {
  local old="${1%%[, ]*}" new="${2%%[, ]*}"
  local -a o n
  o=("${(@s:.:)old}"); n=("${(@s:.:)new}")
  local i a b
  for (( i = 1; i <= ${#n}; i++ )); do
    a="${o[i]//[^0-9]/}"; b="${n[i]//[^0-9]/}"
    if [[ -z "$a" || -z "$b" ]]; then printf 'update'; return; fi
    if (( a != b )); then
      case $i in 1) printf 'major' ;; 2) printf 'minor' ;; *) printf 'patch' ;; esac
      return
    fi
  done
  printf 'update'
}

# Coloured tag for a bump kind.
_bfu_badge() {
  case "$1" in
    major)  printf '%b' "${bold}${accent_amber}major${reset}" ;;
    minor)  printf '%b' "${accent_cyan}minor${reset}" ;;
    patch)  printf '%b' "${dim}patch${reset}" ;;
    *)      printf '%b' "${dim}update${reset}" ;;
  esac
}

# Aligned upgrade-queue row: name, current -> new version, and a major/minor/patch tag.
print_item_with_versions() {
  local name="$1" current="$2" new="$3"
  if [[ -z "$new" ]]; then
    printf "      ${accent_amber}↑${reset}  %-*s  ${dim}%s${reset}\n" "${BFU_NAME_W:-28}" "$name" "$current"
    return
  fi
  local pad=$(( ${BFU_VER_W:-0} - ${#current} - ${#new} - 3 ))
  (( pad < 0 )) && pad=0
  printf "      ${accent_amber}↑${reset}  %-*s  ${dim}%s${reset} → ${accent_green}%s${reset}%*s  %b\n" \
    "${BFU_NAME_W:-28}" "$name" "$current" "$new" "$pad" "" "$(_bfu_badge "$(_bfu_bump "$current" "$new")")"
}

print_action_result() {
  local action="$1" res_status="$2" symbol="" color=""
  case "$res_status" in
    "done") symbol="✓"; color="$accent_green" ;;
    "skip") symbol="○"; color="$accent_cyan" ;;
    "fail") symbol="✗"; color="$accent_red"; BFU_FAILS=$(( BFU_FAILS + 1 )) ;;
  esac
  _bfu_emit result "$res_status" "$action"
  printf "          ${color}${symbol} ${action}${reset}\n"
}

# One-line suggestion for known failure messages.
_bfu_hint() {
  case "$1" in
    *"Command Line Tools"*|*CLT*) printf 'Reinstall the Command Line Tools: xcode-select --install' ;;
    *"Permission denied"*|*"not writable"*) printf 'Fix the permissions on that path, then run again' ;;
    *"Could not resolve host"*|*"Failed to connect"*|*"timed out"*) printf 'Looks like a network problem, run again in a moment' ;;
  esac
}

# Why the last step failed, in a red gutter under its result line.
print_failure_reason() {
  [[ -n "$BFU_LAST_ERROR" ]] || return 0
  _bfu_emit reason "$BFU_LAST_ERROR"
  local width=$(( BFU_W - 18 )) row hint
  while IFS= read -r row; do
    printf "          ${accent_red}┃${reset} ${dim}%s${reset}\n" "$row"
  done < <(printf '%s\n' "$BFU_LAST_ERROR" | fold -s -w "$width" | sed 's/[[:space:]]*$//')
  hint=$(_bfu_hint "$BFU_LAST_ERROR")
  [[ -n "$hint" ]] && printf "          ${accent_red}┃${reset} ${accent_amber}→ %s${reset}\n" "$hint"
  return 0
}

# Closing summary card: overall result, totals, one row per step with a time bar.
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

  _bfu_emit summary "$duration" "$BFU_UPGRADED" "${#BFU_SKIPPED_NAMES}" "$BFU_FAILS" "$DRY_RUN"
  local j
  for (( j = 1; j <= ${#BFU_STEP_TITLES}; j++ )); do
    _bfu_emit row "$j" "${BFU_STEP_TITLES[j]}" "${BFU_STEP_NOTES[j]:-done}" "${BFU_STEP_SECS[j]:-0}"
  done

  printf "\n"
  _bfu_box_top
  _bfu_box_row "$title_plain" "$title_styled" "${duration}s" "${dim}${duration}s${reset}"
  _bfu_box_divider

  # Totals
  local skipped=${#BFU_SKIPPED_NAMES} chips_plain chips_styled
  if [[ "$DRY_RUN" == true ]]; then
    chips_plain="● $(_bfu_count "$BFU_PENDING" update updates) would be installed"
    chips_styled="${accent_amber}●${reset} $(_bfu_count "$BFU_PENDING" update updates) would be installed"
  else
    local fail_dot="$track"
    (( BFU_FAILS > 0 )) && fail_dot="$accent_red"
    chips_plain="● ${BFU_UPGRADED} upgraded   ● ${skipped} skipped   ● ${BFU_FAILS} failed"
    chips_styled="${accent_green}●${reset} ${BFU_UPGRADED} upgraded   ${accent_cyan}●${reset} ${skipped} skipped   ${fail_dot}●${reset} ${BFU_FAILS} failed"
  fi
  _bfu_box_row "$chips_plain" "$chips_styled" "" ""
  _bfu_box_divider

  # One row per step: status icon, name, result, relative time bar, seconds.
  local i name note secs max=1 icon color
  for (( i = 1; i <= ${#BFU_STEP_TITLES}; i++ )); do
    (( ${BFU_STEP_SECS[i]:-0} > max )) && max=${BFU_STEP_SECS[i]}
  done
  for (( i = 1; i <= ${#BFU_STEP_TITLES}; i++ )); do
    name="${BFU_STEP_TITLES[i]}"
    note="${BFU_STEP_NOTES[i]:-done}"
    secs="${BFU_STEP_SECS[i]:-0}"
    (( ${#note} > BFU_W - 35 )) && note="${note[1,BFU_W-36]}…"
    case "$note" in
      *failed*) icon="✗"; color="$accent_red" ;;
      *skipped*|*"not installed"*|*"dry run"*|*"would"*) icon="○"; color="$accent_cyan" ;;
      *) icon="✓"; color="$accent_green" ;;
    esac
    local bar_plain="$(draw_line ─ 8)" timing="${(l:3:)secs}s"
    _bfu_box_row "${icon} ${(r:14:)name}${note}" "${color}${icon}${reset} ${dim}${(r:14:)name}${reset}${note}" \
      "${bar_plain}  ${timing}" "$(_bfu_bar "$secs" "$max" 8)  ${dim}${timing}${reset}"
  done
  _bfu_box_bottom

  if [[ "$DRY_RUN" != true ]]; then
    printf "\n"
    if (( skipped > 0 )); then
      printf "  ${accent_cyan}○${reset} ${dim}Still running, so not upgraded: ${(j:, :)BFU_SKIPPED_NAMES}. Quit and run again to update them.${reset}\n"
    fi
    printf "  ${dim}Log  ${BFU_LOG/#$HOME/~}${reset}\n"
  fi
  printf "\n"
  _bfu_title "Brew Full Update · done"

  # Native macOS notification
  if [[ "$DRY_RUN" != true ]]; then
    if (( BFU_FAILS > 0 )); then
      osascript -e "display notification \"${BFU_FAILS} step(s) failed. See ~/Library/Logs/brew-full-update.log\" with title \"Brew Command Center\" subtitle \"Finished with failures\"" 2>/dev/null
    else
      osascript -e "display notification \"${BFU_UPGRADED} upgraded, ${skipped} skipped\" with title \"Brew Command Center\" subtitle \"Update complete\"" 2>/dev/null
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
  BFU_PENDING=$total_outdated
  _bfu_emit pending "$total_outdated"

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

  # Homebrew's own checks. Informational only: a warning never counts as a failure.
  local doctor_warnings="" doctor_count=0
  doctor_warnings=$(brew doctor 2>&1 | _bfu_doctor_warnings)
  [[ -n "$doctor_warnings" ]] && doctor_count=$(print -r -- "$doctor_warnings" | wc -l | tr -d ' ')
  if (( doctor_count == 0 )); then
    print_status "✓" "$accent_green" "Homebrew doctor: no warnings"
  else
    print_status "!" "$accent_amber" "Homebrew doctor: $(_bfu_count "$doctor_count" warning warnings), informational only"
    local warning max=$(( BFU_W - 12 ))
    while read -r warning; do
      (( ${#warning} > max )) && warning="${warning[1,max-1]}…"
      printf "      ${dim}· %s${reset}\n" "$warning"
    done <<< "$doctor_warnings"
    printf "      ${dim}Run brew doctor for the full details.${reset}\n"
  fi
}

# ============================================================================
# SHARED UPGRADE HELPERS
# ============================================================================

# "1 formula" / "3 formulae"
_bfu_count() {
  if (( $1 == 1 )); then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi
}

# Column widths for an outdated list: longest name (capped) and longest "old → new".
_bfu_name_width() {
  local line name max=8
  while read -r line; do
    name="${line%% *}"
    (( ${#name} > max )) && max=${#name}
  done <<< "$1"
  (( max > 34 )) && max=34
  printf '%s' "$max"
}

_bfu_version_width() {
  local line cur new max=0 w
  while read -r line; do
    cur=$(_bfu_current_ver "$line"); new=$(_bfu_new_ver "$line")
    w=$(( ${#cur} + ${#new} + 3 ))
    (( w > max )) && max=$w
  done <<< "$1"
  printf '%s' "$max"
}

# Print an outdated list as an aligned queue.
_bfu_print_queue() {
  local list="$1" kind="${2:-formula}" line name cur new
  BFU_NAME_W=$(_bfu_name_width "$list")
  BFU_VER_W=$(_bfu_version_width "$list")
  while read -r line; do
    name="${line%% *}"
    cur=$(_bfu_current_ver "$line"); new=$(_bfu_new_ver "$line")
    _bfu_emit queued "$kind" "$name" "$cur" "$new" "$(_bfu_bump "$cur" "$new")"
    print_item_with_versions "$name" "$cur" "$new"
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
  _bfu_print_queue "$OUTDATED_FORMULAE" formula

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
      print_failure_reason
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
  _bfu_print_queue "$OUTDATED_CASKS" cask

  if [[ "$DRY_RUN" == true ]]; then
    printf "\n    ${dim}Dry run: nothing will be installed.${reset}\n"
    _bfu_step_note "$count would be upgraded"
    return
  fi

  if [[ "${ADMIN_OK:-true}" == false ]]; then
    printf "\n    ${dim}Skipped: no admin access.${reset}\n"
    _bfu_step_note "skipped, no admin access"
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
        print_failure_reason
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
  _bfu_update_mas
  _bfu_check_macos
}

# Mac App Store apps, through mas. Skipped when mas isn't installed.
_bfu_update_mas() {
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
    _bfu_emit queued store "$line" "" "" ""
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
    print_failure_reason
    _bfu_step_note "failed"
  fi
}

# macOS system updates. Report only: installing them restarts the Mac, so that stays in System Settings.
_bfu_check_macos() {
  print_subsection "macOS"
  local listing pending="" count
  listing=$(softwareupdate --list 2>&1)
  pending=$(print -r -- "$listing" | _bfu_macos_updates)
  if [[ -z "$pending" ]]; then
    if [[ "$listing" == *"No new software available"* ]]; then
      print_status "✓" "$accent_green" "macOS is up to date"
    else
      print_status "!" "$accent_amber" "Could not check for macOS updates"
    fi
    return
  fi
  count=$(print -r -- "$pending" | wc -l | tr -d ' ')
  print_status "›" "$accent_cyan" "$(_bfu_count "$count" update updates) pending, install in System Settings › General › Software Update"
  local line
  while read -r line; do
    _bfu_emit queued system "$line" "" "" ""
    printf "      ${accent_amber}↑${reset}  %s\n" "$line"
  done <<< "$pending"
}

# ============================================================================
# 5 · DEV RUNTIMES
# ============================================================================

# Global packages installed on top of the language managers. Each runs only when its tool is present.
_bfu_global_packages() {
  print_subsection "Global packages"
  local -a names=(npm pipx uv rustup)
  local -A cmds=(npm "npm update -g" pipx "pipx upgrade-all" uv "uv tool upgrade --all" rustup "rustup update")
  local tool present=0
  for tool in "${names[@]}"; do
    command -v "$tool" &> /dev/null || continue
    present=$(( present + 1 ))
    if [[ "$DRY_RUN" == true ]]; then
      print_status "·" "$dim" "$tool would be synced"
      continue
    fi
    if _bfu_attempt "Syncing $tool" ${(z)cmds[$tool]}; then
      print_action_result "$tool synced$(_bfu_attempt_note)" "done"
    else
      print_action_result "$tool failed$(_bfu_attempt_note)" "fail"
      print_failure_reason
    fi
  done
  (( present == 0 )) && print_status "·" "$dim" "No global package managers found"
}

# Oh My Zsh and the plugins and themes cloned into its custom folder. Fast-forward only,
# so local edits are never overwritten; a repo that can't fast-forward is skipped.
_bfu_shell_repos() {
  print_subsection "Shell plugins"
  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}" dir out
  local -a repos=()
  [[ -d "$HOME/.oh-my-zsh/.git" ]] && repos+=("$HOME/.oh-my-zsh")
  for dir in "$custom"/plugins/*(/N) "$custom"/themes/*(/N); do
    [[ -d "$dir/.git" ]] && repos+=("$dir")
  done
  if (( ${#repos} == 0 )); then
    print_status "·" "$dim" "No git-managed shell plugins found"
    return
  fi
  if [[ "$DRY_RUN" == true ]]; then
    print_status "·" "$dim" "$(_bfu_count "${#repos}" repository repositories) would be updated"
    return
  fi
  for dir in "${repos[@]}"; do
    if out=$(GIT_TERMINAL_PROMPT=0 git -C "$dir" pull --ff-only 2>&1); then
      if [[ "$out" == *"Already up to date"* ]]; then
        print_action_result "${dir:t} is up to date" "done"
      else
        print_action_result "${dir:t} updated" "done"
      fi
    else
      _bfu_log "git pull failed in $dir: $out"
      print_action_result "${dir:t} not updated (local changes or no network)" "skip"
    fi
  done
}

sync_dev_environments() {
  print_section "Dev runtimes"

  local note=""
  if [[ "$DRY_RUN" == true ]]; then
    print_status "·" "$dim" "${dim}Node, Python and Ruby environments would be synced${reset}"
    note="dry run"
  else
    local tool label
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
  fi

  _bfu_global_packages
  _bfu_shell_repos
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

  # What is left in the Homebrew cache, and how much disk this run gained overall.
  local cache_kb free_kb delta sign=""
  cache_kb=$(du -sk "$(brew --cache)" 2>/dev/null | awk '{ print $1 }')
  [[ -n "$cache_kb" ]] && print_status "·" "$dim" "Homebrew cache ${bold}$(_bfu_size "$cache_kb")${reset}"
  free_kb=$(_bfu_free_kb)
  delta=$(( free_kb - BFU_FREE_START ))
  (( delta >= 0 )) && sign="+"
  print_status "·" "$dim" "Disk ${bold}$(_bfu_size "$free_kb") free${reset} ${dim}(${sign}$(_bfu_size "$delta") this run)${reset}"
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

# Free space on the boot volume, in kilobytes.
_bfu_free_kb() {
  df -k / | awk 'NR == 2 { print $4 }'
}

# Kilobytes as a short size: 812.0 KB, 3.2 GB. Negative values keep their minus sign.
_bfu_size() {
  awk -v k="$1" 'BEGIN {
    sign = (k < 0) ? "-" : ""
    if (k < 0) k = -k
    split("KB MB GB TB", unit, " ")
    i = 1
    while (k >= 1024 && i < 4) { k /= 1024; i++ }
    printf "%s%.1f %s", sign, k, unit[i]
  }'
}

# Headline of each "Warning:" block in `brew doctor` output, one per line.
_bfu_doctor_warnings() {
  sed -nE 's/^Warning: +(.*[^[:space:]])[[:space:]]*$/\1/p'
}

# "Title (Version)" for each pending update in `softwareupdate --list` output.
_bfu_macos_updates() {
  sed -nE 's/^[[:space:]]*Title: ([^,]*), Version: ([^,]*),.*/\1 (\2)/p'
}

# Progress feed for the native window: with BFU_EVENTS=1, each call prints one
# "@@BFU kind|field|field" line. Terminal runs never set it, so they see nothing.
_bfu_emit() {
  [[ -n "${BFU_EVENTS:-}" ]] || return 0
  printf '@@BFU %s\n' "${(j:|:)@}"
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
# Sets BFU_RUN_SECS (total seconds), BFU_RETRIED (1 if a retry happened) and,
# on failure, BFU_LAST_ERROR (Homebrew's own error line).
_bfu_attempt() {
  local label="$1"; shift
  local start=$SECONDS rc offset
  BFU_RETRIED=""
  BFU_LAST_ERROR=""
  _bfu_log "$*"
  offset=$(stat -f %z "$BFU_LOG")
  _bfu_run "$label" "$@"; rc=$?
  if (( rc != 0 )); then
    BFU_RETRIED=1
    _bfu_log "FAILED (exit $rc), retrying once: $*"
    printf "          ${accent_amber}↻ Failed, retrying once${reset}\n"
    offset=$(stat -f %z "$BFU_LOG")
    _bfu_run "$label (retry)" "$@"; rc=$?
  fi
  BFU_RUN_SECS=$(( SECONDS - start ))
  (( rc != 0 )) && BFU_LAST_ERROR=$(_bfu_error_since "$offset")
  return $rc
}

# First "Error:" line the command wrote to the log after byte OFFSET, prefix removed.
_bfu_error_since() {
  local line
  line=$(tail -c +"$(( $1 + 1 ))" "$BFU_LOG" | grep -m1 -E '^(Error|error):')
  line="${line#*: }"
  (( ${#line} > 240 )) && line="${line[1,239]}…"
  printf '%s' "$line"
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

# Admin authentication. The native window sets SUDO_ASKPASS to its own password prompt;
# otherwise sudo asks in the terminal as before.
_bfu_sudo_auth() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A -v
  else
    sudo -v
  fi
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
  typeset -g BFU_FAILS=0 BFU_UPGRADED=0 BFU_PENDING=0 BFU_CHILD_PID="" BFU_RETRIED="" BFU_RUN_SECS=0 BFU_SPIN_INDENT="" BFU_LAST_ERROR=""
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
      # Dry runs wear amber instead of blue so a preview can't be mistaken for the real thing.
      [[ -n "$accent_amber" ]] && accent_blue="$accent_amber"
      ;;
  esac

  local global_start=$SECONDS
  typeset -g BFU_FREE_START=$(_bfu_free_kb)

  # Start from a clean screen so the run reads as one window, not a shell session.
  [[ -t 1 ]] && clear
  print_top_banner "Brew Command Center"

  if ! check_system_health; then
    printf "\n  ${accent_red}✗ Update aborted${reset} ${dim}· check your network connection${reset}\n\n"
    return 1
  fi

  if [[ "$DRY_RUN" != true && ( -n "$OUTDATED_FORMULAE" || -n "$OUTDATED_CASKS" ) ]]; then
    _bfu_snapshot
    print_status "·" "$dim" "${dim}Installed versions saved to the log (rollback reference)${reset}"
  fi

  # Admin rights are only requested when app (cask) installers will actually run,
  # so most runs never prompt for a password or Touch ID.
  local ADMIN_OK=true
  if [[ "$DRY_RUN" != true && -n "$OUTDATED_CASKS" ]]; then
    print_status "›" "$accent_cyan" "Admin access needed to install app updates"
    if _bfu_sudo_auth; then
      # Keep the sudo session alive until we are done (&! keeps it out of the job table).
      while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &!
      SUDO_PID=$!
    else
      ADMIN_OK=false
      print_status "!" "$accent_amber" "Admin authentication failed, app updates will be skipped"
    fi
  fi

  update_formulae
  update_casks
  update_app_store
  sync_dev_environments
  optimize_storage

  print_summary "$(( SECONDS - global_start ))"
}
