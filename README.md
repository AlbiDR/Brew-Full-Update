<div align="center">

# Brew Full Update

**One command to bring a Mac fully up to date.**

Homebrew formulae and casks, Mac App Store apps, language-runtime sync and cleanup,
finished with a clear report of what worked and what didn't.

[![Latest release](https://img.shields.io/github/v/release/AlbiDR/Brew-Full-Update?style=flat-square&color=4f7aa8)](https://github.com/AlbiDR/Brew-Full-Update/releases/latest)
![macOS](https://img.shields.io/badge/macOS-Homebrew-4f7aa8?style=flat-square)
![zsh](https://img.shields.io/badge/shell-zsh-4f7aa8?style=flat-square)

[Install](#install) · [Usage](#usage) · [What it does](#what-it-does) · [Configuration](#configuration) · [Troubleshooting](#troubleshooting) · [Development](#development)

</div>

---

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ BREW COMMAND CENTER [DRY-RUN]                                                ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ SYSTEM INTEGRITY & DIAGNOSTICS                                           │
  └──────────────────────────────────────────────────────────────────────────┘
    ✓  Network connection stable
    ✓  Registries indexed (1 updates identified)
    ✓  System health optimal

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ BINARY DEPLOYMENT                                                        │
  └──────────────────────────────────────────────────────────────────────────┘
    UPGRADE QUEUE
    ────────────────────────────────────────────────────────────────────────
      ↑  supabase/tap/supabase        2.117.0 → 2.120.0

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ SYSTEM UPDATE COMPLETE (4s) (DRY-RUN - no changes made)                      ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

<sub>A real dry run, trimmed. Colour in the terminal.</sub>

## Why

Keeping a Mac current usually means `brew update`, `brew upgrade`, `brew upgrade --cask`, `mas upgrade`, a few cleanup commands, and hoping nothing failed quietly. This does all of it in one pass, refuses to upgrade apps you have open, skips the ones you don't want touched, and tells you plainly at the end how it went.

## Features

- **Preview first.** `--dry-run` shows every pending upgrade and changes nothing. It doesn't even ask for your password.
- **Respects what's open.** A cask is skipped if its app is currently running.
- **Honest reporting.** Each step is counted. The closing banner and notification say if anything failed, and where to look.
- **Full log.** Complete output of every step goes to `~/Library/Logs/brew-full-update.log`.
- **Opt-outs.** Keep chosen casks out of upgrades with a one-line list.
- **Health check.** Flags missing dependencies and deprecated or disabled packages.
- **Fails safe.** Offline? It stops with exit code 1 instead of pretending to succeed.

## Install

**Requirements:** macOS with [Homebrew](https://brew.sh) and zsh. Optional: [`mas`](https://github.com/mas-cli/mas) for App Store updates, and `nodenv`, `pyenv` or `rbenv` for runtime sync. Missing optional tools are skipped, not errors.

### Shell command

```zsh
git clone https://github.com/AlbiDR/Brew-Full-Update.git ~/Brew-Full-Update
```

Add to `~/.zshrc`:

```zsh
source ~/Brew-Full-Update/brew_full_update.zsh
alias brew-full-update='brew_full_update'
```

### Mac app

Download `Brew-Full-Update-v*.zip` from the [latest release](https://github.com/AlbiDR/Brew-Full-Update/releases/latest), unzip, and put the app anywhere.

The app is ad-hoc signed rather than notarized, so macOS blocks the first launch. Right-click it, choose **Open**, and confirm. Or clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine "Brew Full Update.app"
```

## Usage

```zsh
brew-full-update              # run the update
brew-full-update --dry-run    # preview only (-d also works)
```

The app asks **Update**, **Dry Run** or **Cancel** when it opens (Update is chosen automatically after 10 seconds), then runs the same script in Terminal.

## What it does

| # | Step | Action |
| - | --- | --- |
| 1 | Diagnostics | Checks connectivity, runs `brew update`, lists what is outdated, flags missing or deprecated packages |
| 2 | Formulae | Upgrades outdated formulae one at a time |
| 3 | Casks | Upgrades outdated casks, skipping excluded ones and any whose app is running |
| 4 | App Store | `mas upgrade`, if `mas` is installed |
| 5 | Runtimes | `brew nodenv-sync`, `pyenv-sync` and `rbenv-sync` |
| 6 | Cleanup | `brew autoremove` and `brew cleanup --prune=7` (downloads and old versions kept for a week) |

Admin rights are requested once at the start and kept alive for the run, because some cask installers need them.

## Configuration

Casks whose name **starts with** an entry in `BFU_EXCLUDED_CASKS` are never upgraded. The default list is at the top of `brew_full_update.zsh`. To use your own without editing the file, define the array before sourcing it:

```zsh
BFU_EXCLUDED_CASKS=(alfred daisydisk)
source ~/Brew-Full-Update/brew_full_update.zsh
```

| Item | Location |
| --- | --- |
| Run log | `~/Library/Logs/brew-full-update.log` (reset when it passes 1 MB) |
| Excluded casks | `BFU_EXCLUDED_CASKS` |

## Troubleshooting

**macOS says the app "can't be opened".** It isn't notarized. See [Mac app](#mac-app) for the right-click or `xattr` fix.

**A step shows ✗ failed.** Open the log: `open ~/Library/Logs/brew-full-update.log`. Each step has a timestamped header followed by the raw output.

**An app was skipped.** It was running. Quit it and run again.

**A cask I excluded still shows up.** Exclusions match the cask *name* from the start (`topaz` covers `topaz-photo-ai`). Check the exact name with `brew list --cask`.

**Sync steps say "skipped".** `nodenv`, `pyenv` or `rbenv` isn't installed. That's expected.

## Uninstall

Remove the two lines from `~/.zshrc`, delete the cloned folder or the app, and optionally delete `~/Library/Logs/brew-full-update.log`.

## Development

```
brew_full_update.zsh        the script (single source of truth)
launcher.applescript.in     app launcher template
build-app.sh                builds and verifies the .app
tests/run.sh                tests against a fake brew
assets/                     app icon
```

```zsh
tests/run.sh      # nothing on your system is touched
./build-app.sh    # produces build/Brew Full Update.app
```

`build-app.sh` embeds the script into the app and checks the copy is identical to the source. Set `BFU_SIGN_ID` to sign with a real identity instead of ad-hoc; a stable identity lets macOS remember privacy approvals across rebuilds.

The app writes a temporary `.command` file and opens it in Terminal, so the run uses a non-interactive shell and never reads `~/.zshrc`.

## Changelog

### 8.3
- Aborts (exit 1) when offline instead of reporting success.
- Real version numbers in the upgrade queue; exclusions match by name prefix.
- Running-app guard uses each cask's actual `.app` names.
- Sudo keep-alive is cleaned up reliably; Ctrl-C stops the run.
- Per-step logging, plus a failure count in the closing banner and notification.
- Deprecated-package check reads `brew info --json=v2` instead of scraping `brew doctor`.
- `cleanup --prune=7` instead of `--prune=all`; removed the no-op `--greedy`.
- Exclusion list is configuration (`BFU_EXCLUDED_CASKS`).
- App: Update / Dry Run dialog, `.command` launch, reproducible build script.

### 8.2
- Initial hardened version.
