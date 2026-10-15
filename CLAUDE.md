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
  - `Clean` — deletes DerivedData, archives, simulator data, keychains, etc. via shell `rm`. Options are indexed by the `OptionInput` enum; `isHiddenInMenu` options (all-except-DerivedData, Maestro, Teams, Messages) stay in the code and in `-d <n>` / `all` but aren't offered in the menu; `Clean.run()` maps a numeric input (arg or interactive prompt) to an action.
  - `XcodeBuild` — **defined but NOT registered** in `main.swift`; its `run()` is a no-op stub. Wire it into the `subcommands` array to activate it.
- **Helpers** (`Sources/spm/Helpers/`):
  - `Global.swift` — `shell(_:)` runs a command through `/bin/zsh -c` and returns stdout+stderr; `keyboardInput()` reads a line.
  - `Print.swift` — ANSI-colored output (`Print.withColor`, `.h3`, `.h6`).
  - `CheckboxTable.swift` — rows and layout of the `avp clean` menu (size-ranked table, detail box for the focused row, running total); `Prompt.checkboxTable` drives it and shrinks the frame when the terminal is short.
  - `Prompt.swift` — interactive `ask`/`yesNo`/`options`. Its I/O goes through `customPrint`/`customReadline`, which can be swapped in tests via the global `TestablePrintFunction`/`TestableReadLineFunction` hooks.
  - `AVPTimer.swift` — CFRunLoop-based repeating "Wait…" spinner.
- **Extensions** (`Sources/spm/Extensions/`):
  - `String+Error.swift` — declares `extension String: Error {}`, so **string literals can be `throw`n directly** throughout the codebase (e.g. `throw "message"`).
  - `URL+FileManager.swift` — `subDirectories()` enumeration used by `Clean`.

## Conventions & gotchas

- **Adding a subcommand**: create a `ParsableCommand` in `Sources/spm/Subcommands/`, then add it to the `subcommands:` array in `main.swift`. It won't appear in the CLI otherwise.
- **Version bumps**: `Constant.App.version` in `main.swift` is asserted verbatim by `testExample` (checks `"avp version <x>\n"` from `--version`). Update the test when bumping.
- `buildWithTimingSummary.sh` under `Resources/Scripts/` is `exclude`d from the build target — it's a standalone reference script, not compiled or bundled.
