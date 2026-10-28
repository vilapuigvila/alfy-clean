# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`alfy-clean` is a personal macOS command-line helper (Swift Package Manager executable) for
Apple/iOS development chores: cleaning Xcode & simulator caches and developer data. It has one
command, `Clean`, which is the default. Built on
[swift-argument-parser](https://github.com/apple/swift-argument-parser). Requires macOS 12+, swift-tools 5.5.

## Commands

```bash
swift build                                    # build
swift run alfy-clean [args]                    # run Clean, the default (e.g. swift run alfy-clean all)
swift test                                     # run all tests
swift test --filter alfyCleanTests/testExample # run a single test
```

## Architecture

Entry point is `Sources/alfy-clean/main.swift`: the root `AlfyClean` command registers its subcommands in
its `CommandConfiguration.subcommands` array (only `Clean`), sets `defaultSubcommand: Clean.self` so that
`alfy-clean` with no subcommand runs Clean, and calls `AlfyClean.main()`.

- **Subcommands** (`Sources/alfy-clean/Subcommands/`) — each is a `ParsableCommand` struct/class; `Clean` is the only one and the default:
  - `Clean` — deletes DerivedData (found at runtime by `Helpers/DerivedDataDiscovery.swift`: the default `~/Library/Developer/Xcode/DerivedData`, Xcode's `IDECustomDerivedDataLocation` if inside the home folder, and project-local `DerivedData` folders under the home folder — depth 7, pruning `Library`/`.Trash`/`.git`/`node_modules`/`Pods`/`Carthage`/`.build` — whose parent or grandparent holds a `*.xcodeproj`/`*.xcworkspace`; from the menu a picker lists each project folder of the default folder, biggest first, with orphans flagged, one "shared caches" row, and any project-local folder as a whole-folder row; nothing is ticked by default and only ticked rows are deleted; `-d 3` / `all` still delete the whole folders). After a cleanup `Clean` prints how much free disk space was gained (free space before/after, not `du`, since APFS clones overstate), archives, simulator data, keychains, etc. via shell `rm`. Options are indexed by the `OptionInput` enum; `isHiddenInMenu` options (all-except-DerivedData, Teams, Messages, Trash; Maestro when `~/.maestro/tests` is absent) stay in the code and in `-d <n>` / `all` but aren't offered in the menu; `Clean.run()` maps a numeric input (arg or interactive prompt) to an action.
- **Helpers** (`Sources/alfy-clean/Helpers/`):
  - `DerivedDataProjects.swift` — per-project DerivedData model: reads `WorkspacePath` from `info.plist`; orphan = that path no longer exists (missing/unreadable plist = unknown, NOT orphan); shared caches = `ModuleCache.noindex`, `CompilationCache.noindex`, `SDKExplicitPrecompiledModules` only; `deletable` keeps only direct non-symlink children of discovered DerivedData folders; freed-space maths (`freedBytes` may be zero/negative).
  - `DiskUsage.swift` — folder sizes via `du -sk`; `measureReclaimable` instead counts only APFS-private bytes (`ATTR_CMNEXT_PRIVATESIZE`) and is used for the clone folders (`XCTestDevices`/`XCPGDevices`), whose `du` size counts blocks shared with the source simulator once per clone (30 GB shown, ~0.1 GB freed).
  - `Global.swift` — `runProcess(_:_:)` runs an absolute-path executable with an argument array (no shell, fixed `PATH`) and returns stdout+stderr; `simctl(_:)` and `expandTilde(_:)` wrap the common cases; `keyboardInput()` reads a line.
  - `Print.swift` — ANSI-colored output (`Print.withColor`).
  - `CheckboxTable.swift` — rows and layout of the `alfy-clean clean` menu: a list on the left (sections Xcode & iOS / Caches / System & apps, biggest first inside each, a risk glyph per row) beside an inspector for the focused row (size, risk, what it does, deletes, comes back, asks first), plus a running total. `Prompt.checkboxTable` drives it; on a narrow terminal the inspector goes under the list, and on a short one the layout drops the storage banner, the section headings and then inspector detail.
  - `Prompt.swift` — interactive `ask`/`yesNo`/`options`. Its I/O goes through `customPrint`/`customReadline`, which can be swapped in tests via the global `TestablePrintFunction`/`TestableReadLineFunction` hooks.
  - `AlfyCleanTimer.swift` — CFRunLoop-based repeating "Wait…" spinner.
- **Extensions** (`Sources/alfy-clean/Extensions/`):
  - `String+Error.swift` — declares `extension String: Error {}`, so **string literals can be `throw`n directly** throughout the codebase (e.g. `throw "message"`).
  - `URL+FileManager.swift` — `subDirectories()` enumeration used by `Clean`.

## Conventions & gotchas

- **Adding a subcommand**: create a `ParsableCommand` in `Sources/alfy-clean/Subcommands/`, then add it to the `subcommands:` array in `main.swift`. It won't appear in the CLI otherwise. Adding one doesn't change the default: `defaultSubcommand` stays `Clean.self`.
- **Unknown words go to Clean**: a word that isn't a registered subcommand is read as Clean's first positional argument, `all`. Anything else there is rejected by Clean's guard (``Maybe you want to write `all` ?``) before anything is deleted.
- **Version bumps**: `Constant.App.version` in `main.swift` is asserted verbatim by `testExample` (checks `"alfy-clean version <x>\n"` from `--version`). Update the test when bumping.
