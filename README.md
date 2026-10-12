# Brew Full Update

A zsh script that updates a Mac in one go: Homebrew formulae and casks, Mac App Store apps, `nodenv`/`pyenv`/`rbenv` sync, and cleanup. It reports what failed at the end instead of leaving you to scroll back through the output. There's also a small Mac app that runs the same script.

This is what `brew-full-update --dry-run` prints (a dry run changes nothing):

```
  ╭────────────────────────────────────────────────────────────────────────────╮
  │ ◆ Brew Command Center                                       dry run  v10.0 │
  │   MacBook Pro · macOS 27.2 · Homebrew 7.0.9 · 11 Oct, 14:02                │
  ╰────────────────────────────────────────────────────────────────────────────╯

  ── 1 · Diagnostics ──────────────────────────────────────────────────── ●●●●●●

    ✓  Network reachable
    ✓  Homebrew index refreshed (0s)
    ✓  1 update available (1 formula, 0 casks)
    ✓  No missing or deprecated packages

  ── 2 · Formulae ─────────────────────────────────────────────────────── ●●●●●●

    ›  1 formula to upgrade

    ▸ Upgrade queue
      ↑  supabase/tap/supabase  2.117.0 → 2.120.0  minor

    Dry run: nothing will be installed.

  ── 3 · Casks ────────────────────────────────────────────────────────── ●●●●●●

    Excluding: alfred, daisydisk, gemini, macdroid, topaz-gigapixel +3 more

    ✓  All applications are up to date

  ── 4 · App Store ────────────────────────────────────────────────────── ●●●●●●

    ✓  All App Store apps are up to date

  ── 5 · Dev runtimes ─────────────────────────────────────────────────── ●●●●●●

    ·  Node, Python and Ruby environments would be synced

  ── 6 · Cleanup ──────────────────────────────────────────────────────── ●●●●●●

    ·  Skipped in dry run

  ╭────────────────────────────────────────────────────────────────────────────╮
  │ Dry run complete · no changes made                                      3s │
  ├────────────────────────────────────────────────────────────────────────────┤
  │ ● 1 update would be installed                                              │
  ├────────────────────────────────────────────────────────────────────────────┤
  │ ✓ Diagnostics   1 update found                              ━━━━━━━━    3s │
  │ ○ Formulae      1 would be upgraded                         ────────    0s │
  │ ✓ Casks         up to date                                  ────────    0s │
  │ ✓ App Store     up to date                                  ────────    0s │
  │ ○ Dev runtimes  dry run                                     ────────    0s │
  │ ○ Cleanup       dry run                                     ────────    0s │
  ╰────────────────────────────────────────────────────────────────────────────╯
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

1. Checks the network (exits with code 1 if it's down), runs `brew update`, lists outdated packages, flags missing or deprecated ones, and shows `brew doctor` warnings as information only.
2. Upgrades formulae one by one, with a spinner and elapsed time for each. A failed upgrade is retried once.
3. Upgrades casks the same way. It skips excluded casks and any app that's currently running.
4. `mas upgrade`, if `mas` is installed. Then it lists pending macOS updates. It only reports them: install those in System Settings, since they can restart the Mac.
5. `brew nodenv-sync`, `pyenv-sync`, `rbenv-sync`. Then `npm update -g`, `pipx upgrade-all`, `uv tool upgrade --all` and `rustup update`, each only when that tool is installed. Then `git pull --ff-only` for Oh My Zsh and the plugins and themes in its custom folder. A repo with local changes is skipped, never overwritten.
6. `brew autoremove` and `brew cleanup --prune=7`, so downloads and old versions stick around for a week. Then it shows the Homebrew cache size and the free disk space, with the change made by this run.

It only asks for your admin password (or Touch ID) when app updates are actually pending, since cask installers can need it, and keeps the session alive until the script finishes. Runs with no app updates, and dry runs, never prompt.

Before the first upgrade, the versions you have installed are written to the log, so you can see what to roll back to if an update breaks something.

Output is plain text when piped to a file, or when `NO_COLOR` is set. To keep the colours in a pager, run it with `BFU_FORCE_COLOR=1` and pipe into `less -R`.

Every step's output goes to `~/Library/Logs/brew-full-update.log`, which resets once it passes 1 MB. If any step fails, the closing summary and the notification say so and point to that file.

## Excluding casks

Any cask whose name starts with an entry in `BFU_EXCLUDED_CASKS` is left alone, so `topaz-photo` also covers `topaz-photo-ai`. The default list is at the top of `brew_full_update.zsh`.

In the app, the **Exclusions** button adds a cask to the list. Names are saved to `~/Library/Application Support/Brew Full Update/exclusions.txt`, one per line, and the script reads that file on every run. The Update dialog then shows them under "Also excluded", and the "Excluding:" line in the output includes them. Edit the file by hand to remove a name.

To use your own list without editing the file, set it before sourcing:

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
assets/                   app icon (`icon.svg` is the source)
make-icon.sh              rebuilds assets/applet.icns from icon.svg
```

`tests/run.sh` doesn't touch your system. `./build-app.sh` writes `build/Brew Full Update.app` and checks that the script embedded in it is identical to the source. Set `BFU_SIGN_ID` to sign with a real certificate; the default is an ad-hoc signature, which means macOS may ask for privacy approvals again after a rebuild.

The app saves a temporary `.command` file and opens it in Terminal, so the script runs in a non-interactive shell and never reads `~/.zshrc`.

## Changelog

**10.1**
- Exclusions: the app's Exclusions button adds casks to leave out of upgrades. Names are saved to a file the script reads on every run, and the dialog and output show them.
- Location: choose where that exclusions file lives, by typing a path or browsing to one. A new file is created if the path doesn't exist yet.
- The main dialog has three buttons (Exclusions, Dry Run, Update), the most macOS allows. Update stays the default and still starts after the 15-second timeout. Cancel is gone; press Ctrl-C in Terminal to stop a run.
- Global packages: `npm update -g`, `pipx upgrade-all`, `uv tool upgrade --all` and `rustup update`, each only when installed.
- Shell plugins: Oh My Zsh and its plugins and themes are updated with `git pull --ff-only`. Repos with local changes are skipped.
- macOS updates are listed in the App Store section, for information only. Install them in System Settings.
- `brew doctor` warnings are shown in Diagnostics, for information only.
- Cleanup shows the Homebrew cache size and the free disk space, with the change made by this run.

**10.0**
- Redesigned output: gradient header, numbered sections with a six-dot progress rail, a progress line on every package, and dry runs drawn in amber so a preview never looks like the real thing.
- Upgrade queues tag each update as major, minor or patch, with major updates highlighted.
- Failures show Homebrew's own error in a red gutter, plus a suggested fix for known problems such as outdated Command Line Tools.
- Summary card: totals, a status icon and a time bar for every step, and the log path.
- Terminal tab title follows progress (`Brew Full Update Â· 3/6 Casks`).
- New app icon, and a clearer Update / Dry Run dialog.
- `BFU_FORCE_COLOR=1` keeps colours when piping.

**9.1**
- Admin access is requested only when cask upgrades are pending, so most runs no longer prompt for a password or Touch ID.
- A failed step now shows Homebrew's own error message under the ✗ line, wrapped to fit.
- No stray `[1] + terminated` job message at the end of a run in an interactive shell.

**9.0**
- New look: rounded header with machine info, numbered section rules, aligned upgrade queues with the new version highlighted, and per-package version changes.
- Closing summary card: one row per step (what happened and how long it took), plus totals and any apps skipped because they were running.
- Spinner while the Homebrew index refreshes and while cleanup runs; cleanup now reports how much space it freed.
- Dry runs no longer show repeated "preview" blocks; each section ends with a single line.

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
