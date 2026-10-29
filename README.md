# alfy-clean

alfy-clean is a command-line helper for macOS that frees disk space used by Xcode and iOS development. Run with no arguments, it opens a checkbox menu that shows each cleanup with its size, its risk and what it deletes, and it reports how much free disk space the cleanup gained. It is written for developers who build apps with Xcode and the iOS simulator on their own Mac.

## Features

- Interactive checkbox menu. Nothing is ticked by default, and only ticked rows are deleted.
- Rows are grouped into Xcode & iOS, Caches and System & apps, biggest first within each group, with a size for each row.
- A risk glyph on each row: `●` safe (rebuilds itself), `◆` pick which (you choose items next), `▲` careful or can't undo, `○` look only (deletes nothing by itself).
- An inspector for the focused row shows what the option does, what it deletes, whether it comes back and whether it asks first. A running total shows what the current selection will free.
- Derived Data picker: lists each Xcode project's DerivedData folder, flags orphans (the project no longer exists) and finds project-local DerivedData folders under your home folder.
- Item pickers for simulators, iOS DeviceSupport versions, simulator runtimes, folders in `~/Library/Caches`, and a scan for large system folders.
- Free-space report after each cleanup, measured from the disk before and after.
- A yes/no prompt before every deletion. It names what will be removed.
- Non-interactive modes: `alfy-clean all` and `alfy-clean -d <n>`.
- macOS notifications when a cleanup step finishes. They use `terminal-notifier` if it is installed and `osascript` otherwise.

## Requirements

- macOS 12 or later.
- Swift 5.5 or later (the package declares `swift-tools-version:5.5`). The Swift toolchain that comes with Xcode or the Xcode command line tools is enough.
- Network access for the first build, so SwiftPM can fetch `swift-argument-parser`.

## Install

### With Homebrew (recommended)

```sh
brew tap vilapuigvila/tap
brew trust vilapuigvila/tap
brew install alfy-clean
```

Homebrew asks you to trust third-party taps before it loads their formulae, so `brew trust` is required once per tap. Without it, `brew install` stops with "Refusing to load formula".

Homebrew builds the tool from source, so you need Xcode 13 or later, or the Xcode command line tools. To update later, run `brew upgrade alfy-clean`. To remove it, run `brew uninstall alfy-clean` and then `brew untap vilapuigvila/tap`.

The tap formula is in [vilapuigvila/homebrew-tap](https://github.com/vilapuigvila/homebrew-tap).

### From source

Clone the repository, then build and install from it.

```sh
git clone https://github.com/vilapuigvila/alfy-clean.git
cd alfy-clean
```

#### With make

```sh
make install
```

This runs `swift build -c release` and copies the binary to `~/.local/bin/alfy-clean`. To install somewhere else, set `BIN_DIR`:

```sh
make install BIN_DIR=/usr/local/bin
```

You may need `sudo` for a directory you do not own.

If `~/.local/bin` is not already on your `PATH`, add it, for example in `~/.zshrc`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

#### With swift build

```sh
swift build -c release
```

The binary is at `.build/release/alfy-clean`. Run it from there, or copy it to a folder on your `PATH`.

## Usage

```sh
alfy-clean              # interactive menu (the default)
alfy-clean all          # run the "all" cleanup after one confirmation
alfy-clean -d 3         # run one option by number (3 = Derived Data)
alfy-clean --version    # prints: alfy-clean version 0.0.2
alfy-clean --help
```

Any other word after the command is rejected with `Maybe you want to write 'all' ?`, and nothing is deleted.

### Interactive menu

Running `alfy-clean` with no arguments opens the menu.

- `↑`/`↓` or `j`/`k` move, `space` ticks a row, `Enter` confirms, `q` cancels.
- Ticking **Derived Data** opens a second picker. Tick the projects or shared caches you want to delete.
- Confirming asks one yes/no question that lists everything that will be deleted. Answer no to cancel that job.
- A "will free" total is shown for the selection. It reads "up to" when a selected row asks you to pick items next, so the total is then a maximum.
- When a job finishes, the menu returns. Leave it empty (`Enter` with nothing ticked, or `q`) to exit.

The inspector sits beside the list on terminals 93 columns or wider. On narrower terminals it is shown under the list.

### `alfy-clean all`

Shows one yes/no prompt that lists what it will delete, then runs without the menu. It:

- shuts down and erases all simulators, and clears the CoreSimulator caches;
- deletes the cloned simulators in `XCTestDevices` and `XCPGDevices`;
- deletes every Derived Data folder it finds, Archives, Previews, the QuickHelp documentation cache, the Teams (classic) app data, the System Trash, the SwiftPM cache, and Maestro test output if that folder exists;
- opens the Messages Attachments folder in Finder. It deletes nothing there.

It does not touch iOS DeviceSupport, simulator runtimes, the Homebrew cache, Claude Code job folders, the folders in `~/Library/Caches`, or the large-folder scan.

### `alfy-clean -d <n>`

Runs the option with number `n` once, without the menu. Options that delete ask for one yes/no first, as in the menu. For Derived Data, `-d 3` deletes every Derived Data folder found, not a chosen subset. A number outside 0 to 18 stops the program with an error.

### Options

| No. | Option | What it deletes | In menu |
|----:|--------|-----------------|---------|
| 0 | All, derived data excluded | Everything in `all` except Derived Data, plus the whole iOS DeviceSupport folder | Hidden |
| 1 | Erase simulators content | The simulators you tick: apps, data, logins, keychains and settings. Running ones are shut down first. Devices stay installed. | Yes |
| 2 | Delete cloned simulators | `~/Library/Developer/XCTestDevices` and `XCPGDevices` (clones made for parallel tests and Playgrounds) | Yes |
| 3 | Derived Data | Xcode DerivedData folders: the ones you tick in the menu, or all found with `-d 3` | Yes |
| 4 | Archives | `~/Library/Developer/Xcode/Archives` (`.xcarchive` and dSYMs) | Yes |
| 5 | Previews | `~/Library/Developer/Xcode/UserData/Previews` | Yes |
| 6 | Messages attachments | Nothing. It opens `~/Library/Messages/Attachments` in Finder | Hidden |
| 7 | Teams (classic) data | `~/Library/Application Support/Microsoft/Teams`. You will be signed out | Hidden |
| 8 | Documentation cache | `~/Library/Developer/Xcode/DocumentationCache` | Yes |
| 9 | System Trash | Everything in `~/.Trash` | Hidden |
| 10 | Homebrew cache | Runs `brew cleanup --prune=all` | Yes |
| 11 | Maestro test output | `~/.maestro/tests` | Only when `~/.maestro/tests` exists |
| 12 | Claude Code jobs tmp | The `tmp` folder inside each `~/.claude/jobs/<job>` | Yes |
| 13 | iOS DeviceSupport versions | The versions you tick in `~/Library/Developer/Xcode/iOS DeviceSupport` | Yes |
| 14 | Simulator runtimes | The runtimes you tick, removed with `simctl` | Yes |
| 15 | Scan for folders over a size you choose | Nothing by itself. You pick 2, 5 or 10 GB (5 GB by default), it scans for folders bigger than that, then lets you tick folders from a fixed list of safe locations | Yes |
| 16 | SwiftPM cache | `~/Library/Caches/org.swift.swiftpm` | Yes |
| 17 | Big folders in `~/Library/Caches` | The folders over 1 GB directly inside `~/Library/Caches` that you tick | Yes |
| 18 | Delete simulators | The simulators you tick, removed for good with `simctl delete`. Running ones are shut down first. They must be created again to be used. | Yes |

<img width="1108" height="637" alt="image" src="https://github.com/user-attachments/assets/3f13e403-9b94-4ac5-80ba-d8c2a7e0ea5d" />


Notes:

- Options 1, 13, 14, 15 and 17 ask about each item they delete. Option 6 only opens a folder.
- Option 15 first asks for the size to scan for: 2, 5 or 10 GB, with 5 GB pre-selected. `-d 15` skips the question and uses 5 GB.
- `--help` also lists `-v, --verbose` and a second positional word `ndd`. The code does not read either, so they have no effect.

## What gets deleted and what is safe

Every cleanup deletes permanently. Files are removed with `rm -rf`, `find -exec rm`, `simctl`, `brew cleanup` or the file manager. None of them moves anything to the Trash.

**Recreated by Xcode, apps or the system.** These cost time, a download, or a sign-in:

- Derived Data: the next build is slow, because it starts from scratch.
- Cloned simulators, the Previews cache, Maestro output and Claude Code job tmp folders: recreated on next use.
- Documentation, Homebrew and SwiftPM caches: downloaded again when needed.
- iOS DeviceSupport: copied again when you connect a device running that iOS version.
- Simulator runtimes: download again from Xcode > Settings > Components. Simulators that use them are unavailable until then.
- Folders in `~/Library/Caches`: the apps rebuild them. Some apps may sign you out or download data again.
- Teams (classic) data: you sign in again.

**Not recreated:**

- Archives (`.xcarchive` and dSYMs). You can only get them back by archiving again from source. dSYMs are needed to symbolicate crash reports from old builds.
- The System Trash.
- Data inside erased simulators: apps, app data, logins, keychains and settings. The simulator devices themselves stay installed.

**Back up first if you might need them:**

- Archives you may re-sign, re-distribute, or use for crash symbolication. Copy the `.xcarchive` and its dSYMs somewhere else.
- Anything in the Trash.
- Simulator data you have not set up again: test data, signed-in accounts, keychain items.
- Maestro test output you want to keep, such as screenshots and recordings.

**Safeguards in the code:**

- Nothing is ticked by default.
- A prompt that receives end-of-input stops the program. It is never read as yes.
- Derived Data folders must be named exactly `DerivedData`. A project-local one is included only when an `.xcodeproj` or `.xcworkspace` sits in its parent or grandparent folder.
- The large-folder scan only offers folders from a fixed list (under your home folder's `DerivedData`, the CoreDevice deltas folder, or your own Claude temp folder). Each one is checked again just before deletion.
- If `~/.Trash` cannot be read, the Trash option stops with a message. Grant Full Disk Access to your terminal app and try again.

The repository's `SECURITY_AUDIT.md` records a review of the deletion code, dated 2026-10-15.

## Development

Build and test:

```sh
swift build              # debug build
swift build -c release   # release build, as used by make install
swift test               # run the unit tests
```

Releases are tagged `vX.Y.Z` on GitHub. The version in `main.swift` and the one asserted by `testExample` must match the tag. The Homebrew formula in `vilapuigvila/homebrew-tap` points at the tag's archive and needs its `url` and `sha256` updated for each new release.

Project layout:

```
Package.swift                       package, platform (macOS 12) and tools version (5.5)
Makefile                            build and install targets
Sources/alfy-clean/
  main.swift                        entry point, version constant, command setup
  Subcommands/Clean.swift           the Clean command: options, menu flow, every cleanup
  Helpers/                          Derived Data discovery and projects, disk usage,
                                    menu table, prompts, process runner, simulators,
                                    notifications and other helpers
  Extensions/                       String+Error, URL+FileManager
Tests/alfy-cleanTests/              unit tests
```

Adding a subcommand, the version bump rule and the other conventions are in [CLAUDE.md](CLAUDE.md). Read it before changing the code.

## License

TBD
