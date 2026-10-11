# Brew Full Update

**One command to bring a Mac fully up to date.**
Homebrew formulae and casks, Mac App Store apps, language-runtime sync, and cleanup, with a clear report at the end.

Written in zsh. Optionally wrapped in a small macOS app for one-click use.

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ BREW COMMAND CENTER                                                          ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ BINARY DEPLOYMENT                                                        │
  └──────────────────────────────────────────────────────────────────────────┘
    UPGRADE QUEUE
      ↑  wget                         1.25.0 → 1.26.0

    [1/1]  wget
          ✓ Installed and verified
```

## Features

- **Safe by default.** Stops cleanly when offline. Never upgrades an app that is currently running.
- **Dry run.** Preview everything first with `--dry-run`; nothing is installed or removed.
- **Honest reporting.** Every step is counted, and the final banner and notification tell you if anything failed.
- **Full log.** Complete output of each step is kept in `~/Library/Logs/brew-full-update.log`.
- **Excludable apps.** Keep chosen casks (Alfred, DaisyDisk, …) out of the upgrade with a one-line list.
- **Health check.** Flags missing dependencies and deprecated or disabled packages.

## Install

### As a shell command

Clone the repo, then source the script from your `~/.zshrc`:

```zsh
source /path/to/Brew-Full-Update/brew_full_update.zsh
alias brew-full-update='brew_full_update'
```

```zsh
brew-full-update              # run the update
brew-full-update --dry-run    # preview only
```

### As a Mac app

Download `Brew-Full-Update-v*.zip` from the [latest release](https://github.com/AlbiDR/Brew-Full-Update/releases/latest), unzip, and move the app anywhere you like.

The app is not notarized, so on first launch macOS will block it. Right-click it, choose **Open**, and confirm. Or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "Brew Full Update.app"
```

On launch it asks **Update**, **Dry Run** or **Cancel** (Update is chosen automatically after 10 seconds), then runs the same script in Terminal.

## What it does

| Step | Action |
| --- | --- |
| 1. Diagnostics | Checks connectivity, runs `brew update`, lists what is outdated, flags missing or deprecated packages |
| 2. Formulae | Upgrades outdated formulae one at a time |
| 3. Casks | Upgrades outdated casks, skipping excluded ones and any whose app is running |
| 4. App Store | Runs `mas upgrade` if [`mas`](https://github.com/mas-cli/mas) is installed |
| 5. Runtimes | `brew nodenv-sync`, `pyenv-sync` and `rbenv-sync` |
| 6. Cleanup | `brew autoremove` and `brew cleanup --prune=7` |

Admin rights are requested once at the start and kept alive for the run, because some cask installers need them. Dry runs never ask.

## Configuration

Casks whose name **starts with** an entry in `BFU_EXCLUDED_CASKS` are never upgraded. Edit the array at the top of `brew_full_update.zsh`, or define it yourself before sourcing the file:

```zsh
BFU_EXCLUDED_CASKS=(alfred daisydisk)
source /path/to/brew_full_update.zsh
```

## Development

```zsh
tests/run.sh      # tests against a fake brew; touches nothing real
./build-app.sh    # builds build/Brew Full Update.app
```

`build-app.sh` embeds `brew_full_update.zsh` into the app and verifies the embedded copy matches the source. Set `BFU_SIGN_ID` to sign with a real identity instead of ad-hoc; a stable identity lets macOS remember privacy approvals across rebuilds.

The app runs the script as a `.command` file, so Terminal starts a non-interactive shell and never reads `~/.zshrc`.

## Changelog

### 8.3
- Aborts (exit 1) when offline instead of reporting success.
- Real version numbers in the upgrade queue; exclusions match by name prefix.
- Running-app guard uses each cask's actual `.app` names.
- Sudo keep-alive is cleaned up reliably; Ctrl-C stops the run.
- Per-step logging, plus a failure count in the final banner and notification.
- Deprecated-package check reads `brew info --json=v2` instead of scraping `brew doctor`.
- `cleanup --prune=7` instead of `--prune=all`; removed the no-op `--greedy`.
- Exclusion list is configuration (`BFU_EXCLUDED_CASKS`).
- App: Update / Dry Run dialog, `.command` launch, reproducible build script.

### 8.2
- Initial hardened version.
