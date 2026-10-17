# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`avp` is a personal macOS command-line helper (Swift Package Manager executable) for
Apple/iOS development chores: cleaning Xcode & simulator caches, and listing developer-folder
disk usage. Built on
[swift-argument-parser](https://github.com/apple/swift-argument-parser). Requires macOS 12+, swift-tools 5.5.

## Commands

```bash
swift build                              # build
swift run avp <subcommand> [args]        # run (e.g. swift run avp clean all)
swift test                               # run all tests
swift test --filter avpTests/testExample # run a single test
```

Note the **name mismatch**: the product/binary and test target are `avp`, but the source
directories are `Sources/spm` and `Tests/spmTests` (declared explicitly via `path:` in
`Package.swift`). Always use `avp` for `swift run`/`swift test --filter`, never `spm`.

## Architecture

Entry point is `Sources/spm/main.swift`: the root `Avp` command registers subcommands in
its `CommandConfiguration.subcommands` array and calls `Avp.main()`.

- **Subcommands** (`Sources/spm/Subcommands/`) — each is a `ParsableCommand` struct/class:
  - `Cache` — lists disk usage (`du -hs`) of Xcode/developer folders; has a nested `List` subcommand.
  - `Clean` — deletes DerivedData (found at runtime by `Helpers/DerivedDataDiscovery.swift`: the default `~/Library/Developer/Xcode/DerivedData`, Xcode's `IDECustomDerivedDataLocation` if inside the home folder, and project-local `DerivedData` folders under the home folder — depth 7, pruning `Library`/`.Trash`/`.git`/`node_modules`/`Pods`/`Carthage`/`.build` — whose parent or grandparent holds a `*.xcodeproj`/`*.xcworkspace`; from the menu a picker lists each project folder of the default folder, biggest first, with orphans flagged, one "shared caches" row, and any project-local folder as a whole-folder row; nothing is ticked by default and only ticked rows are deleted; `-d 3` / `all` still delete the whole folders). After a cleanup `Clean` prints how much free disk space was gained (free space before/after, not `du`, since APFS clones overstate), archives, simulator data, keychains, etc. via shell `rm`. Options are indexed by the `OptionInput` enum; `isHiddenInMenu` options (all-except-DerivedData, Teams, Messages, Trash; Maestro when `~/.maestro/tests` is absent) stay in the code and in `-d <n>` / `all` but aren't offered in the menu; `Clean.run()` maps a numeric input (arg or interactive prompt) to an action.
  - `WorktreeClean` — `avp worktree-clean <path> [--yes]`: deletes the DerivedData project folders whose `WorkspacePath` (from their `info.plist`) is inside `<path>` (whole path components: `/a/wt` does not match `/a/wt-other`); lists them and asks yes/no unless `--yes`; prints freed space. Simulators are not touched.
  - `XcodeBuild` — **defined but NOT registered** in `main.swift`; its `run()` is a no-op stub. Wire it into the `subcommands` array to activate it.
- **Helpers** (`Sources/spm/Helpers/`):
  - `DerivedDataProjects.swift` — per-project DerivedData model: reads `WorkspacePath` from `info.plist`; orphan = that path no longer exists (missing/unreadable plist = unknown, NOT orphan); shared caches = `ModuleCache.noindex`, `CompilationCache.noindex`, `SDKExplicitPrecompiledModules` only; `deletable` keeps only direct non-symlink children of discovered DerivedData folders; freed-space maths (`freedBytes` may be zero/negative).
  - `Global.swift` — `runProcess(_:_:)` runs an absolute-path executable with an argument array (no shell, fixed `PATH`) and returns stdout+stderr; `simctl(_:)` and `expandTilde(_:)` wrap the common cases; `keyboardInput()` reads a line.
  - `Print.swift` — ANSI-colored output (`Print.withColor`, `.h3`, `.h6`).
  - `CheckboxTable.swift` — rows and layout of the `avp clean` menu: a list on the left (sections Xcode & iOS / Caches / System & apps, biggest first inside each, a risk glyph per row) beside an inspector for the focused row (size, risk, what it does, deletes, comes back, asks first), plus a running total. `Prompt.checkboxTable` drives it; on a narrow terminal the inspector goes under the list, and on a short one the layout drops the storage banner, the section headings and then inspector detail.
  - `Prompt.swift` — interactive `ask`/`yesNo`/`options`. Its I/O goes through `customPrint`/`customReadline`, which can be swapped in tests via the global `TestablePrintFunction`/`TestableReadLineFunction` hooks.
  - `AVPTimer.swift` — CFRunLoop-based repeating "Wait…" spinner.
- **Extensions** (`Sources/spm/Extensions/`):
  - `String+Error.swift` — declares `extension String: Error {}`, so **string literals can be `throw`n directly** throughout the codebase (e.g. `throw "message"`).
  - `URL+FileManager.swift` — `subDirectories()` enumeration used by `Clean`.

## Conventions & gotchas

- **Adding a subcommand**: create a `ParsableCommand` in `Sources/spm/Subcommands/`, then add it to the `subcommands:` array in `main.swift`. It won't appear in the CLI otherwise.
- **Version bumps**: `Constant.App.version` in `main.swift` is asserted verbatim by `testExample` (checks `"avp version <x>\n"` from `--version`). Update the test when bumping.
