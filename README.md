# Brew Full Update

One command (or one double-click) to bring a Mac fully up to date: Homebrew formulae
and casks, Mac App Store apps, `nodenv`/`pyenv`/`rbenv` sync, and cleanup. Written in zsh,
optionally wrapped in a macOS app.

## Use

Shell function (sourced from `~/.zshrc` via `~/Documents/Backups/ZSH/*.zsh`, which is a
symlink to this repo's `brew_full_update.zsh`):

```zsh
brew-full-update              # alias for brew_full_update
brew-full-update --dry-run    # preview: nothing is installed or cleaned
```

App: `./build-app.sh` produces `build/Brew Full Update.app`. On launch it asks
**Update / Dry Run / Cancel** (defaults to Update after 10 s) and runs the same script in Terminal.

## What it does

1. Checks connectivity (aborts with exit 1 if offline), runs `brew update`, lists outdated items.
2. Flags missing dependencies and deprecated/disabled installed packages.
3. Upgrades formulae one by one, then casks (skipping any whose app is currently running).
4. `mas upgrade` if `mas` is installed.
5. `brew nodenv-sync`, `pyenv-sync`, `rbenv-sync`.
6. `brew autoremove` and `brew cleanup --prune=7`.

The final banner reports the failure count. Full output of every step goes to
`~/Library/Logs/brew-full-update.log` (reset when it passes 1 MB).

## Configuration

Edit the `BFU_EXCLUDED_CASKS` array at the top of `brew_full_update.zsh`: casks whose name
**starts with** an entry are never upgraded. To override without editing the file, define the
array before the file is sourced.

## Develop

```zsh
tests/run.sh      # fake-brew tests: parsers, exclusions, failure counter, abort, dry run
./build-app.sh    # build the app; verifies the embedded script equals the source
```

`BFU_SIGN_ID="Apple Development: ..." ./build-app.sh` signs with a real identity instead of
ad-hoc. A stable identity keeps macOS privacy approvals between rebuilds.

The app runs the script as a `.command` file so Terminal starts a non-interactive shell and
never reads `~/.zshrc` (which would touch `~/Documents`).

## Changelog

### 8.3
- Abort (exit 1) when offline instead of continuing to a "COMPLETE" banner.
- Real version numbers (`brew outdated --verbose`); anchored exclusion matching.
- Running-app guard uses each cask's real `.app` names.
- Sudo keepalive cleanup via global PID and function-local traps; Ctrl-C stops the run.
- Per-step logging, failure count in the final banner and notification.
- Deprecated check via `brew info --json=v2` instead of scraping `brew doctor`.
- `cleanup --prune=7` (was `all`); dropped the no-op `--greedy`.
- Exclusion list is configuration (`BFU_EXCLUDED_CASKS`).
- App: Update/Dry Run dialog, `.command` launch, reproducible `build-app.sh`.

### 8.2
- Initial hardened version.
