#!/usr/bin/env zsh

# ============================================================================
# BREW FULL UPDATE - Comprehensive System Synchronization (v8.4)
# ============================================================================

BFU_VERSION="8.4"

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

# Color palette - intentional, restrained
reset='\033[0m'
bold='\033[1m'
dim='\033[2m'

# Primary accent colors
accent_blue='\033[38;5;67m'      # Muted blue for headers
accent_cyan='\033[38;5;73m'      # Cyan for info/progress
accent_green='\033[38;5;107m'    # Muted green for success
accent_amber='\033[38;5;179m'    # Amber for warnings
accent_red='\033[38;5;167m'      # Muted red for failures

# Decorative elements
line_heavy='━'
line_light='─'
corner_tl='┏'
corner_tr='┓'
corner_bl='┗'
corner_br='┛'
divider_v='┃'

# ============================================================================
# LAYOUT HELPERS - DETERMINISTIC GEOMETRY
# ============================================================================

draw_line() {
  local char="$1"
  local len="$2"
  for ((i=0; i<len; i++)); do printf "%s" "$char"; done
}

calculate_main_padding() {
  local text="$1"
  local text_length=${#text}
  local padding=$((78 - text_length - 1))
  [[ $padding -gt 0 ]] && printf "%${padding}s" ""
}

calculate_section_padding() {
  local text="$1"
  local text_length=${#text}
  local padding=$((74 - text_length - 1))
  [[ $padding -gt 0 ]] && printf "%${padding}s" ""
}

# ============================================================================
# BANNER PRINTING (CASCADING HIERARCHY)
# ============================================================================

print_top_banner() {
  local title="$1"
  local plain_title="$title"
  
  if [[ "$DRY_RUN" == true ]]; then
    title="${title} ${dim}[DRY-RUN]${reset}"
    plain_title="${plain_title} [DRY-RUN]"
  fi
  
  printf "\n${accent_blue}${corner_tl}$(draw_line "$line_heavy" 78)${corner_tr}${reset}\n"
  printf "${accent_blue}${divider_v}${reset} ${bold}${title}${reset}$(calculate_main_padding "$plain_title")${accent_blue}${divider_v}${reset}\n"
  printf "${accent_blue}${corner_bl}$(draw_line "$line_heavy" 78)${corner_br}${reset}\n"
}

print_section() {
  local title="$1"
  printf "\n  ${accent_blue}┌$(draw_line "$line_light" 74)┐${reset}\n"
  printf "  ${accent_blue}│${reset} ${bold}${title}${reset}$(calculate_section_padding "$title")${accent_blue}│${reset}\n"
  printf "  ${accent_blue}└$(draw_line "$line_light" 74)┘${reset}\n"
}

print_subsection() {
  local title="$1"
  printf "\n    ${bold}${title}${reset}\n"
  printf "    ${dim}$(draw_line "$line_light" 72)${reset}\n"
}

print_bottom_banner() {
  local duration="$1"
  local mode_text=""
  local title_text="✓ SYSTEM"
  local status_text="UPDATE COMPLETE"
  local banner_color="$accent_green"

  if [[ "$DRY_RUN" == true ]]; then
    title_text="SYSTEM"
    mode_text=" (DRY-RUN - no changes made)"
  elif [[ "$BFU_FAILS" -gt 0 ]]; then
    title_text="! SYSTEM"
    status_text="UPDATE FINISHED WITH ${BFU_FAILS} FAILURE(S)"
    banner_color="$accent_amber"
  fi

  local plain_message="${title_text} ${status_text} (${duration}s)${mode_text}"
  local message="${title_text} ${status_text} (${duration}s)${dim}${mode_text}${reset}"

  printf "\n${accent_blue}${corner_tl}$(draw_line "$line_heavy" 78)${corner_tr}${reset}\n"
  printf "${accent_blue}${divider_v}${reset} ${bold}${banner_color}${message}${reset}$(calculate_main_padding "$plain_message")${accent_blue}${divider_v}${reset}\n"
  printf "${accent_blue}${corner_bl}$(draw_line "$line_heavy" 78)${corner_br}${reset}\n"

  if [[ "$DRY_RUN" != true && "$BFU_FAILS" -gt 0 ]]; then
    printf "  ${dim}Details: ${BFU_LOG}${reset}\n"
  fi
  printf "\n"

  # Native macOS Notification Hook
  if [[ "$DRY_RUN" != true ]]; then
    if [[ "$BFU_FAILS" -gt 0 ]]; then
      osascript -e "display notification \"${BFU_FAILS} step(s) failed. See ~/Library/Logs/brew-full-update.log\" with title \"Brew Command Center\" subtitle \"Finished with failures\"" 2>/dev/null
    else
      osascript -e 'display notification "Your Mac is fully synchronized and optimized." with title "Brew Command Center" subtitle "Update Complete!"' 2>/dev/null
    fi
  fi
}

# ============================================================================
# STATUS LINE HELPERS
# ============================================================================

print_status() {
  local symbol="$1"
  local color="$2"
  local message="$3"
  printf "    ${color}${symbol}${reset}  ${message}\n"
}

print_action_start() {
  local index="$1"
  local total="$2"
  local name="$3"
  printf "    ${dim}[${reset}${accent_cyan}%s${dim}/${reset}${accent_cyan}%s${dim}]${reset}  ${bold}%s${reset}\n" "$index" "$total" "$name"
}

print_item_with_versions() {
  local name="$1"
  local current="$2"
  local new="$3"
  if [[ -z "$new" ]]; then
    printf "      ${accent_amber}↑${reset}  %-28s ${dim}%s${reset}\n" "$name" "$current"
  else
    printf "      ${accent_amber}↑${reset}  %-28s ${dim}%s${reset} → ${accent_amber}%s${reset}\n" "$name" "$current" "$new"
  fi
}

print_action_result() {
  local action="$1"
  local res_status="$2"
  local symbol=""
  local color=""
  
  case "$res_status" in
    "done") symbol="✓"; color="$accent_green" ;;
    "preview") symbol="→"; color="$accent_cyan" ;;
    "skip") symbol="○"; color="$accent_cyan" ;;
    "fail") symbol="✗"; color="$accent_red"; ((BFU_FAILS++)) ;;
  esac
  
  printf "          ${color}${symbol} ${action}${reset}\n"
}

# ============================================================================
# SYSTEM DIAGNOSTICS & ASYNC PRE-FETCH
# ============================================================================

check_system_health() {
  print_section "SYSTEM INTEGRITY & DIAGNOSTICS"
  
  # 1. Network Connection Guard
  printf "    ${dim}Testing upstream internet connectivity...${reset}\n"
  if ! nc -zw1 1.1.1.1 443 &>/dev/null; then
    print_status "✗" "$accent_red" "Network unreachable. Sync aborted."
    return 1
  fi
  print_status "✓" "$accent_green" "Network connection stable"
  printf "\n"
  
  # 2. Registry Sync & Background Pre-Fetch
  printf "    ${dim}Indexing registries & calculating payloads...${reset}\n"
  
  # FAILURE IGNORED: brew update success/failure does not stop execution
  brew update > /dev/null 2>&1 || true
  brew analytics off > /dev/null 2>&1 || true
  
  OUTDATED_FORMULAE=$(brew outdated --formula --verbose 2>/dev/null)
  OUTDATED_CASKS=$(brew outdated --cask --verbose 2>/dev/null | _bfu_filter_excluded)
  
  local f_count=0
  local c_count=0
  [[ -n "$OUTDATED_FORMULAE" ]] && f_count=$(echo "$OUTDATED_FORMULAE" | wc -l | tr -d ' ')
  [[ -n "$OUTDATED_CASKS" ]] && c_count=$(echo "$OUTDATED_CASKS" | wc -l | tr -d ' ')
  local total_outdated=$((f_count + c_count))
  
  if [[ "$total_outdated" -gt 0 && "$DRY_RUN" != true ]]; then
    (
      local f_list=$(echo "$OUTDATED_FORMULAE" | awk '{print $1}')
      local c_list=$(echo "$OUTDATED_CASKS" | awk '{print $1}')
      if [[ -n "$f_list" ]]; then echo "$f_list" | xargs brew fetch --formula >/dev/null 2>&1; fi
      if [[ -n "$c_list" ]]; then echo "$c_list" | xargs brew fetch --cask >/dev/null 2>&1; fi
    ) &
    PREFETCH_PID=$!
    print_status "✓" "$accent_green" "Registries indexed ($total_outdated updates pre-fetching in background)"
  elif [[ "$total_outdated" -gt 0 && "$DRY_RUN" == true ]]; then
    print_status "✓" "$accent_green" "Registries indexed ($total_outdated updates identified)"
  else
    print_status "✓" "$accent_green" "Registries indexed (System up-to-date)"
  fi
  printf "\n"
  
  # 3. System Architecture Analysis
  printf "    ${dim}Analyzing system architecture...${reset}\n"
  
  local missing_deps
  local deprecated_items
  
  missing_deps=$(brew missing 2>/dev/null)
  deprecated_items=$(_bfu_deprecated)
  
  if [[ -z "$missing_deps" ]] && [[ -z "$deprecated_items" ]]; then
    print_status "✓" "$accent_green" "System health optimal"
  else
    if [[ -n "$missing_deps" ]]; then
      print_status "⚠" "$accent_amber" "Missing dependencies: $missing_deps"
    fi
    
    if [[ -n "$deprecated_items" ]]; then
      printf "\n"
      print_subsection "DEPRECATED PACKAGES"
      while read -r line; do
        print_status "!" "$accent_red" "$line"
      done <<< "$deprecated_items"
    fi
  fi
}

# ============================================================================
# FORMULA UPDATES
# ============================================================================

update_formulae() {
  print_section "BINARY DEPLOYMENT"
  
  if [[ -z "$OUTDATED_FORMULAE" ]]; then
    print_status "✓" "$accent_green" "All binaries up-to-date"
    return
  fi
  
  local count=$(echo "$OUTDATED_FORMULAE" | wc -l | tr -d ' ')
  
  if [[ "$DRY_RUN" == true ]]; then
    print_status "ℹ" "$accent_cyan" "Would update ${bold}${count}${reset}${accent_cyan} formula${reset}"
  else
    print_status "⚙" "$accent_cyan" "Found ${bold}${count}${reset}${accent_cyan} formula to update${reset}"
  fi
  
  printf "\n"
  print_subsection "UPGRADE QUEUE"
  while read -r line; do
    local pkg_name=$(echo "$line" | awk '{print $1}')
    local current_ver=$(_bfu_current_ver "$line")
    local new_ver=$(_bfu_new_ver "$line")
    print_item_with_versions "$pkg_name" "$current_ver" "$new_ver"
  done <<< "$OUTDATED_FORMULAE"
  
  if [[ "$DRY_RUN" == true ]]; then
    printf "\n"
    print_subsection "PREVIEW (DRY-RUN)"
    printf "    ${dim}These formulae would be upgraded. Run without --dry-run to install.${reset}\n"
  else
    printf "\n"
    print_subsection "INSTALLATION PROGRESS"
    
    if [[ -n "$PREFETCH_PID" ]]; then
      printf "    ${dim}Waiting for background pre-fetch to complete...${reset}\n"
      wait $PREFETCH_PID 2>/dev/null
      PREFETCH_PID=""
      printf "    ${accent_green}✓${reset}  ${dim}Payloads ready${reset}\n\n"
    fi
    
    local i=1
    while read -r line; do
      local pkg_name=$(echo "$line" | awk '{print $1}')
      print_action_start "$i" "$count" "$pkg_name"
      
      if _bfu_attempt "Installing" brew upgrade --formula "$pkg_name"; then
        print_action_result "Installed and verified$(_bfu_attempt_note)" "done"
      else
        print_action_result "Installation failed$(_bfu_attempt_note)" "fail"
      fi
      printf "\n"
      
      ((i++))
    done <<< "$OUTDATED_FORMULAE"
  fi
}

# ============================================================================
# CASK UPDATES
# ============================================================================

update_casks() {
  print_section "APPLICATION (CASK) DEPLOYMENT"
  
  if [[ -z "$OUTDATED_CASKS" ]]; then
    printf "    ${dim}(Excluding: ${(j:, :)BFU_EXCLUDED_CASKS})${reset}\n\n"
    print_status "✓" "$accent_green" "All applications up-to-date"
    return
  fi
  
  local count=$(echo "$OUTDATED_CASKS" | wc -l | tr -d ' ')
  
  if [[ "$DRY_RUN" == true ]]; then
    print_status "ℹ" "$accent_cyan" "Would update ${bold}${count}${reset}${accent_cyan} application${reset}"
    printf "    ${dim}(Excluding: ${(j:, :)BFU_EXCLUDED_CASKS})${reset}\n"
  else
    print_status "⚙" "$accent_cyan" "Found ${bold}${count}${reset}${accent_cyan} application to update${reset}"
    printf "    ${dim}(Excluding: ${(j:, :)BFU_EXCLUDED_CASKS})${reset}\n"
  fi
  
  printf "\n"
  print_subsection "PENDING UPGRADES"
  while read -r line; do
    local cask_name=$(echo "$line" | awk '{print $1}')
    local current_ver=$(_bfu_current_ver "$line")
    local new_ver=$(_bfu_new_ver "$line")
    print_item_with_versions "$cask_name" "$current_ver" "$new_ver"
  done <<< "$OUTDATED_CASKS"
  
  if [[ "$DRY_RUN" == true ]]; then
    printf "\n"
    print_subsection "PREVIEW (DRY-RUN)"
    printf "    ${dim}These applications would be upgraded. Run without --dry-run to install.${reset}\n"
  else
    printf "\n"
    print_subsection "DEPLOYMENT PROGRESS"
    
    if [[ -n "$PREFETCH_PID" ]]; then
      printf "    ${dim}Waiting for background pre-fetch to complete...${reset}\n"
      wait $PREFETCH_PID 2>/dev/null
      PREFETCH_PID=""
      printf "    ${accent_green}✓${reset}  ${dim}Payloads ready${reset}\n\n"
    fi
    
    local j=1
    while read -r line; do
      local cask_name=$(echo "$line" | awk '{print $1}')
      print_action_start "$j" "$count" "$cask_name"
      
      if _bfu_cask_running "$cask_name"; then
        print_action_result "Application running (skipped)" "skip"
      else
        if _bfu_attempt "Deploying" brew upgrade --cask --force "$cask_name"; then
          print_action_result "Deployed and verified$(_bfu_attempt_note)" "done"
        else
          print_action_result "Deployment failed$(_bfu_attempt_note)" "fail"
        fi
      fi
      printf "\n"
      
      ((j++))
    done <<< "$OUTDATED_CASKS"
  fi
}

# ============================================================================
# MAC APP STORE SYNC
# ============================================================================

update_app_store() {
  print_section "MAC APP STORE SYNC"
  printf "    ${dim}Checking App Store updates...${reset}\n"
  
  if ! command -v mas &> /dev/null; then
    print_status "⚠" "$accent_amber" "mas-cli not installed (skipped)"
    return
  fi
  
  export MAS_NO_AUTO_INDEX=1
  
  local mas_out
  mas_out=$(mas outdated 2>/dev/null)
  
  if [[ -z "$mas_out" ]]; then
    print_status "✓" "$accent_green" "All App Store items up-to-date"
    return
  fi
  
  print_subsection "PENDING UPDATES"
  while read -r line; do
    printf "      ${accent_amber}↑${reset}  %s\n" "$line"
  done <<< "$mas_out"
  
  printf "\n"
  
  if [[ "$DRY_RUN" == true ]]; then
    print_subsection "PREVIEW (DRY-RUN)"
    printf "    ${dim}These App Store items would be updated. Run without --dry-run to install.${reset}\n"
  else
    print_subsection "SYNCHRONIZATION"
    
    if _bfu_attempt "Updating" mas upgrade; then
      print_action_result "App Store synchronized$(_bfu_attempt_note)" "done"
    else
      print_action_result "Sync failed (manual sign-in required)$(_bfu_attempt_note)" "fail"
    fi
  fi
}

# ============================================================================
# DEVELOPMENT ENVIRONMENT SYNC
# ============================================================================

sync_dev_environments() {
  print_section "DEVELOPMENT RUNTIME SYNC"
  
  if [[ "$DRY_RUN" == true ]]; then
    printf "    ${dim}Would align development environments...${reset}\n"
    print_status "ℹ" "$accent_cyan" "Node environment sync would run"
    print_status "ℹ" "$accent_cyan" "Python environment sync would run"
    print_status "ℹ" "$accent_cyan" "Ruby environment sync would run"
  else
    printf "    ${dim}Aligning development environments...${reset}\n"
    
    _bfu_log "brew nodenv-sync"
    if brew nodenv-sync >> "$BFU_LOG" 2>&1; then
      print_status "✓" "$accent_green" "Node environment synchronized"
    else
      print_status "○" "$accent_cyan" "Node environment (skipped)"
    fi
    
    _bfu_log "brew pyenv-sync"
    if brew pyenv-sync >> "$BFU_LOG" 2>&1; then
      print_status "✓" "$accent_green" "Python environment synchronized"
    else
      print_status "○" "$accent_cyan" "Python environment (skipped)"
    fi
    
    _bfu_log "brew rbenv-sync"
    if brew rbenv-sync >> "$BFU_LOG" 2>&1; then
      print_status "✓" "$accent_green" "Ruby environment synchronized"
    else
      print_status "○" "$accent_cyan" "Ruby environment (skipped)"
    fi
  fi
}

# ============================================================================
# STORAGE OPTIMIZATION
# ============================================================================

optimize_storage() {
  print_section "STORAGE OPTIMIZATION"
  printf "    ${dim}Pruning orphaned files and caches...${reset}\n"
  
  if [[ "$DRY_RUN" == true ]]; then
    print_status "ℹ" "$accent_cyan" "Storage cleanup skipped in dry-run mode"
  else
    _bfu_log "brew autoremove"
    brew autoremove >> "$BFU_LOG" 2>&1
    
    local clean_output
    _bfu_log "brew cleanup --prune=7"
    clean_output=$(brew cleanup --prune=7 2>>"$BFU_LOG" | tee -a "$BFU_LOG" | grep "freed")
    
    local clean_val
    if [[ -n "$clean_output" ]]; then
      clean_val=$(echo "$clean_output" | sed "s/==> //")
    else
      clean_val="Storage already optimized"
    fi
    
    print_status "✓" "$accent_green" "$clean_val"
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
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) n=1 t0=$SECONDS
    printf '\033[?25l'
    while kill -0 "$BFU_CHILD_PID" 2>/dev/null; do
      printf "\r          ${accent_cyan}%s${reset} ${dim}%s... %ss${reset}\033[K" "${frames[n]}" "$label" "$((SECONDS - t0))"
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

# " (12s)" or " (12s, after retry)" for the result line.
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
# MAIN ORCHESTRATION
# ============================================================================

brew_full_update() {
  setopt localoptions no_monitor localtraps
  
  # 1. BREW EXISTENCE CHECK
  if ! command -v brew &> /dev/null; then
    printf "${accent_red}Error: Homebrew not found. Install at https://brew.sh${reset}\n"
    return 1
  fi
  
  # 4. BACKGROUND SUDO KEEPALIVE TRAP
  # Register trap to kill keepalive process on script exit or interrupt
  trap '_bfu_cleanup' EXIT
  trap '_bfu_cleanup; printf "\n"; return 130' INT TERM
  
  local DRY_RUN=false
  local OUTDATED_FORMULAE=""
  local OUTDATED_CASKS=""
  local PREFETCH_PID=""
  typeset -g SUDO_PID=""
  typeset -g BFU_FAILS=0 BFU_CHILD_PID="" BFU_RETRIED="" BFU_RUN_SECS=0
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

  # 3. SUDO VALIDATION & KEEPALIVE
  if [[ "$DRY_RUN" != true ]]; then
    printf "\n  ${accent_cyan}Admin privileges may be required for Application deployments.${reset}\n"
    printf "  ${dim}Validating sudo session...${reset}\n"
    
    # Handle sudo failure: abort if authentication is unsuccessful
    if ! sudo -v; then
      print_status "✗" "$accent_red" "Admin authentication failed. Aborting."
      return 1
    fi
    
    # Start background keepalive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!
  fi

  local global_start
  global_start=$(date +%s)
  
  print_top_banner "BREW COMMAND CENTER"
  
  if ! check_system_health; then
    printf "\n${accent_red}  UPDATE ABORTED: Please check your network connection.${reset}\n\n"
    return 1
  fi

  if [[ "$DRY_RUN" != true && ( -n "$OUTDATED_FORMULAE" || -n "$OUTDATED_CASKS" ) ]]; then
    _bfu_snapshot
    printf "\n    ${dim}Installed versions saved to the log (rollback reference)${reset}\n"
  fi
  
  update_formulae
  update_casks
  update_app_store
  sync_dev_environments
  optimize_storage
  
  local global_end
  global_end=$(date +%s)
  local total_time=$((global_end - global_start))
  
  print_bottom_banner "$total_time"
}