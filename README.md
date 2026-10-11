# Brew Full Update

A zsh script that updates a Mac in one go: Homebrew formulae and casks, Mac App Store apps, `nodenv`/`pyenv`/`rbenv` sync, and cleanup. It reports what failed at the end instead of leaving you to scroll back through the output. There's also a small Mac app that runs the same script.

This is what `brew-full-update --dry-run` prints (a dry run changes nothing):

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ BREW COMMAND CENTER  v8.5  [DRY-RUN]                                         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ SYSTEM INTEGRITY & DIAGNOSTICS                                           │
  └──────────────────────────────────────────────────────────────────────────┘
    Testing upstream internet connectivity...
    ✓  Network connection stable

    Indexing registries & calculating payloads...
    ✓  Registries indexed (1 updates identified)

    Analyzing system architecture...
    ✓  System health optimal

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ BINARY DEPLOYMENT                                                        │
  └──────────────────────────────────────────────────────────────────────────┘
    ·  Would update 1 formula

    UPGRADE QUEUE
    ────────────────────────────────────────────────────────────────────────
      ↑  supabase/tap/supabase        2.117.0 → 2.120.0

    PREVIEW (DRY-RUN)
    ────────────────────────────────────────────────────────────────────────
    These formulae would be upgraded. Run without --dry-run to install.

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ APPLICATION (CASK) DEPLOYMENT                                            │
  └──────────────────────────────────────────────────────────────────────────┘
    (Excluding: alfred, daisydisk, gemini, macdroid, topaz-gigapixel +3 more)

    ✓  All applications up-to-date

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ MAC APP STORE SYNC                                                       │
  └──────────────────────────────────────────────────────────────────────────┘
    Checking App Store updates...
    ✓  All App Store items up-to-date

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ DEVELOPMENT RUNTIME SYNC                                                 │
  └──────────────────────────────────────────────────────────────────────────┘
    Would align development environments...
    ·  Node environment sync would run
    ·  Python environment sync would run
    ·  Ruby environment sync would run

  ┌──────────────────────────────────────────────────────────────────────────┐
  │ STORAGE OPTIMIZATION                                                     │
  └──────────────────────────────────────────────────────────────────────────┘
    Pruning orphaned files and caches...
    ·  Storage cleanup skipped in dry-run mode

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ SYSTEM UPDATE COMPLETE · 4s · dry run, no changes made                       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

## Install

You need macOS, Homebrew and zsh. [`mas`](https://github.com/mas-cli/mas) and the `*env` tools are optional; the script skips whatever isn't installed.

**Shell command**

```zsh
git clone https://github.com/AlbiDR/Brew-Full-Update.git ~/Brew-Full-Update
```

then add to `~/.zshrc`:

```zsh
source ~/Brew-Full-Update/brew_full_update.zsh
alias brew-full-update='brew_full_update'
```

**Mac app**

Grab the zip from the [latest release](https://github.com/AlbiDR/Brew-Full-Update/releases/latest) and unzip it. The app isn't notarized, so macOS blocks the first launch: right-click it, choose Open, confirm. Or run this once:

```bash
xattr -dr com.apple.quarantine "Brew Full Update.app"
```

## Usage

```zsh
brew-full-update              # update everything
brew-full-update --dry-run    # preview only; also -d
```

The app asks Update, Dry Run or Cancel when you open it, and picks Update after 10 seconds. Then it runs the script in Terminal.

## What it runs

1. Checks the network (exits with code 1 if it's down), runs `brew update`, lists outdated packages, and flags missing or deprecated ones.
2. Upgrades formulae one by one, with a spinner and elapsed time for each. A failed upgrade is retried once.
3. Upgrades casks the same way. It skips excluded casks and any app that's currently running.
4. `mas upgrade`, if `mas` is installed.
5. `brew nodenv-sync`, `pyenv-sync`, `rbenv-sync`.
6. `brew autoremove` and `brew cleanup --prune=7`, so downloads and old versions stick around for a week.

A real run asks for your admin password once at the start, since some cask installers need it, and keeps it alive until the script finishes. A dry run doesn't ask.

Before the first upgrade, the versions you have installed are written to the log, so you can see what to roll back to if an update breaks something.

Output is plain text when piped to a file, or when `NO_COLOR` is set.

Every step's output goes to `~/Library/Logs/brew-full-update.log`, which resets once it passes 1 MB. If any step fails, the closing banner and the notification say so and point to that file.

## Excluding casks

Any cask whose name starts with an entry in `BFU_EXCLUDED_CASKS` is left alone, so `topaz-photo` also covers `topaz-photo-ai`. The default list is at the top of `brew_full_update.zsh`. To use your own without editing the file, set it before sourcing:

```zsh
BFU_EXCLUDED_CASKS=(alfred daisydisk)
source ~/Brew-Full-Update/brew_full_update.zsh
```

## When something goes wrong

- **A step shows ✗.** Check the log; every step has a timestamped header with its raw output.
- **An app was skipped.** It was running. Quit it and run again.
- **"skipped" next to Node, Python or Ruby.** That tool isn't installed. Nothing to fix.
- **An excluded cask still gets upgraded.** Exclusions match from the start of the cask name, so check the exact name with `brew list --cask`.

To uninstall, remove the two lines from `~/.zshrc` and delete the folder or the app.

## Development

```
brew_full_update.zsh      the script
launcher.applescript.in   app launcher template
build-app.sh              builds and verifies the app
tests/run.sh              tests against a fake brew
assets/                   app icon
```

`tests/run.sh` doesn't touch your system. `./build-app.sh` writes `build/Brew Full Update.app` and checks that the script embedded in it is identical to the source. Set `BFU_SIGN_ID` to sign with a real certificate; the default is an ad-hoc signature, which means macOS may ask for privacy approvals again after a rebuild.

The app saves a temporary `.command` file and opens it in Terminal, so the script runs in a non-interactive shell and never reads `~/.zshrc`.

## Changelog

**8.5**
- Each package line shows its version change: `[2/3] wget 1.25.0 → 1.26.0`.
- Closing summary: upgraded, skipped and failed counts, plus which running apps were skipped.
- Header shows the version; layout adapts to narrow terminals.
- Plain output (no colour codes) when piped or when `NO_COLOR` is set.
- Consistent single-width symbols; removed doubled blank lines; long exclusion list shortened to `+N more`.
- App: the Update / Dry Run dialog shows the app icon.

**8.4**
- Live spinner with elapsed time for each upgrade instead of a silent wait.
- A failed formula, cask or App Store upgrade is retried once; the result line says if it was.
- Installed versions are saved to the log before upgrading, as a rollback reference.

**8.3**
- Exits with code 1 when offline instead of finishing with a success banner.
- Shows real version numbers in the upgrade queue.
- Exclusions match by name prefix.
- Skips casks whose app is running, using the app names Homebrew reports.
- Cleans up the sudo keep-alive; Ctrl-C now stops the run.
- Logs every step and counts failures.
- Finds deprecated packages through `brew info --json=v2` instead of parsing `brew doctor`.
- `cleanup --prune=7` replaces `--prune=all`; dropped `--greedy`, which did nothing here.
- Exclusion list is now `BFU_EXCLUDED_CASKS`.
- App: Update / Dry Run dialog, `.command` launch, `build-app.sh`.

**8.2**
- First hardened version.
