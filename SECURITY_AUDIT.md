# avp security audit

Date: 2026-10-15 · Branch: `development` (working tree after the Pusher removal) · Scope: every file under
`Sources/`, `Tests/`, `Package.swift`, `Package.resolved`, `.gitignore`, `.claude/settings.local.json`, and the
full git history (all branches, pushed to the `origin` GitLab remote).

## Threat model

`avp` is a single-user macOS CLI that deletes files and runs shell commands as the user who launches it. There is
no network code left and no privilege elevation. So the realistic risks are:

1. **Deleting the wrong thing**: a bug, a misleading prompt, or a crafted path makes `avp` remove user data.
2. **Running the wrong program**: a command string or a `PATH` lookup gets subverted.
3. **Leaked secrets**: credentials in the repo or its history.
4. **Untrusted text**: file or simulator names shown in the terminal.
5. **An AI agent driving `avp`**: Claude Code permission rules stored in this repo.

Severity is rated for this context (personal tool on a single-user Mac). Nothing rates High.

## Summary

| ID | Severity | Finding | Fix effort |
|----|----------|---------|------------|
| M1 | Medium | ✅ Fixed 2026-10-15. Claude Code allow-rules in `.claude/settings.local.json` permit arbitrary commands without a prompt | 2 min |
| M2 | Medium | ✅ Fixed 2026-10-15. Irreversible deletions run without confirmation (`-d`) or behind a prompt that doesn't name them (`all`) | 30 min |
| M3 | Medium | ✅ Fixed 2026-10-15. Large-folder deletion checks the path text, not the resolved path (symlink swap between scan and delete) | 30 min |
| L1 | Low | ✅ Fixed 2026-10-15. Commands built as strings for `zsh -c`, and resolved through a `PATH` that has user-writable dirs first | 1 h |
| L2 | Low | ✅ Fixed 2026-10-15. AppleScript notification built by string interpolation | 10 min |
| L3 | Low | ✅ Fixed 2026-10-15. Untrusted names printed raw to the terminal (escape sequences, newlines) | 20 min |
| L4 | Low | Expired APNs tokens and client identifiers in git history (pushed to origin) | decision |
| L5 | Low | No guard against running as root | 5 min |
| L6 | Low | Dependency pinned to 2021 version and capped below 1.0 | 15 min |
| L7 | Low | ✅ Fixed 2026-10-15. `shell()` can hang on large output, and crashes if launch fails | 15 min |

---

## M1. Claude Code allow-rules allow arbitrary commands

**Status: fixed.** The allow list is now exact commands only: `swift --version`, `swift build`,
`swift build -c release`, `swift test`, `swift test --filter avpTests/testExample`, `swift run avp --version`, and the
read-only `du`. There are no wildcards and no awk, sort or head rules.

**Where:** `.claude/settings.local.json` lines 7–17 (untracked, but active for every Claude session in this folder).

**What:**
- `Bash(/usr/bin/awk '$1 >= 5242880 { *)` and `Bash(/usr/bin/awk 'BEGIN { FS=... } $1 >= 5242880 { *)` end in a
  wildcard inside the awk program. awk has `system("…")`, so a command matching that prefix can run any shell
  command without asking.
- `Bash(swift run *)` lets an agent run `swift run avp clean -d 9`, which empties the Trash with no prompt at all
  (see M2). It also allows `swift run --package-path <anywhere>`, which builds and runs code from another folder.
- `Bash(swift build *)` / `Bash(swift test *)` likewise accept `--package-path` to other packages.

**Impact:** text the agent reads (a web page, a file, a tool result) could steer it into running a destructive or
arbitrary command without a permission prompt.

**Fix:** delete the four awk rules and the `sort`/`head` rules (they are left over from an old scan threshold,
`5242880`, which the code no longer uses). Narrow `swift run *` to `swift run avp --version` or remove it, and keep
`swift build`/`swift test` without a trailing wildcard.

## M2. Irreversible deletions without a fitting confirmation

**Status: fixed.** Every option that deletes without its own per-item picker now asks first, including with `-d`
(`OptionInput.needsConfirmation`). The prompt lists what will be deleted. `all` and "all except DerivedData" list
every item, generated from the same `allCleanupOptions` list that runs, so the prompt can't fall out of sync with
the code. Archives and Teams are retitled to say they can't be recovered and that you'll be signed out. Archives and
Trash are still part of `all`; they're now named in its prompt.

**Where:** `Clean.swift:146-151` (`shouldConfirmDelete`), `Clean.swift:89` (`all` prompt), `Clean.swift:133-136`
(`-d`), `Clean.swift:662-681` (commands).

**What:**
- With `-d <n>` there is no interactive selection, and only options 0, 2, 3 and 4 ask for confirmation. These run
  immediately: **9 System Trash** (`rm -rf` of everything in `~/.Trash`), **7 Teams**
  (`rm -rf ~/Library/Application Support/Microsoft/Teams`, which is the whole app-data folder, not only its
  cache: settings and sign-in included), 5 Previews, 8 Documentation cache, 10 Homebrew, 11 Maestro,
  12 Claude jobs tmp.
- `avp clean all` asks once: *"This will erase simulator data, keychains, and caches."* It then also deletes
  **Archives** (your `.xcarchive`s, including the dSYMs needed to symbolicate crash reports for shipped
  builds) and **empties the Trash**. Neither is mentioned, and neither can be undone.

**Impact:** a typo in `-d` (for example `9` instead of `8`) or a quick "y" deletes data that cannot be recovered.
An agent allowed to run `swift run *` (M1) can do the same with no prompt.

**Fix:** have `shouldConfirmDelete` cover every option except the info-only ones, or at least `trash`,
`microsoftTeamsCache` and `archives`. Make the `all` prompt list what it will delete, Archives and Trash by name.
Consider leaving Archives and Trash out of `all` (`runsInAllCleanup`), as already done for runtimes and
DeviceSupport. Narrow Teams to its cache subfolders, or retitle the option "Teams app data".

## M3. Large-folder deletion trusts the path text, not where it resolves

**Status: fixed.** `SystemScanner.isSafeToDeleteNow` runs right before each delete and when the checklist is built.
It requires the allowlist match, `realpath(path) == path` (so no component is a symlink and the folder still
exists), and, under `/private/tmp/claude-<uid>/`, that the root is a directory owned by you and not group- or
world-writable. Covered by `Tests/spmTests/SecurityChecksTests.swift`.

Not changed:
- A window of microseconds remains between the check and `removeItem`. Closing it fully needs `openat`/`unlinkat`
  with `O_NOFOLLOW`, which isn't worth it now that only your own processes can write in the allowed folders.
- The broad DerivedData rule: any folder named `DerivedData` in your home is still offered.

**Where:** `SystemScanner.swift:130-153` (`safeDeleteNote`), `Clean.swift:380-394` (`deleteSafeLargeFolders`).

**What:** the allowlist is a string check: under `$HOME` with a `DerivedData` component, the CoreDevice deltas
folder, or `/private/tmp/claude-<uid>/`. It rejects `..`, but symlinks are not resolved. `removeItem(atPath:)`
follows symlinks in the *middle* of a path. The re-check before deleting is also a string check. Between the scan
and the delete there's a long window while you pick folders and confirm.

**Scenario:** anyone who can write inside an allowed folder creates `.../claude-501/x/Documents` (>5 GB). After the
scan lists it and you tick it, they replace `x` with a symlink to `/Users/albert`. Then
`removeItem("/private/tmp/claude-501/x/Documents")` deletes `~/Documents`.

On this Mac, `/private/tmp/claude-501` is owned by you with mode 700, so today only processes running as you can do
this, and those could delete your files anyway. It becomes a real cross-user hole if another account pre-creates
that folder in the world-writable `/private/tmp`. The `DerivedData` rule is also broad: any folder named
`DerivedData` anywhere in your home counts as safe to delete.

**Fix:** right before deleting, resolve the path (`URL(fileURLWithPath:).resolvingSymlinksInPath()`) and require
that it still equals the listed path, so no component is a symlink. For the Claude temp rule, also require the
`claude-<uid>` folder to be owned by `getuid()` and not group- or world-writable (`lstat`). Optionally tighten the
DerivedData rule to known parents (`~/Library/Developer/Xcode/DerivedData/` and project roots).

## L1. Shell strings and PATH lookup

**Status: fixed.** `shell()` is gone. Everything goes through `runProcess(executable, arguments)` in `Global.swift`:
an absolute `executableURL` (`/bin/rm`, `/usr/bin/find`, `/usr/bin/xcrun`, `/usr/bin/open`, `/usr/bin/du`,
`/usr/bin/awk`, `/usr/bin/osascript`, and `brew` by absolute path), an argument array, and a child `PATH` of
`/usr/bin:/bin:/usr/sbin:/sbin` (Homebrew's folders are added only for `brew`). `~` is expanded in Swift. The large-folder
scan no longer uses a shell pipeline: `du`, then `awk` fed through stdin, then the sort and top-50 cut in Swift
(output compared with the old pipeline on this machine: identical apart from one live simulator folder that grew
0.1 GB between runs). Tests: `ProcessRunnerTests.swift`.

**Where:** `Global.swift:17-31` (`shell`), `SimulatorDevices.swift:53,56`, `SimulatorRuntimes.swift:56`,
`Clean.swift:405,412,419,438,450,667-676`.

**What:**
- `shell(_:)` runs `/bin/zsh -c "<string>"`. Values are interpolated into the string: simulator UDIDs and runtime
  identifiers from `simctl` JSON. Today those come from Apple's tool and are UUID-shaped, so they aren't
  exploitable. But any future value that contains a space, `;`, `$(…)` or a quote becomes shell syntax.
- `rm`, `find`, `xcrun`, `open` and `brew` are found through the inherited `PATH`. Yours puts user-writable folders
  first (`~/.local/bin`, `/opt/homebrew/...`, the node and rbenv shims). Any tool that drops an `rm` or `xcrun`
  there gets run by every `avp` cleanup. zsh also sources `/etc/zshenv` and `~/.zshenv` on every `-c` call (you
  have no `~/.zshenv` today).

**Fix:** follow the pattern `DiskUsage.measure` already uses: `Process` with an absolute `executableURL`
(`/bin/rm`, `/usr/bin/find`, `/usr/bin/xcrun`, `/usr/bin/open`) and an `arguments` array. No shell, no quoting,
no PATH. Where a shell is truly needed, use `/bin/zsh -f -c` and absolute paths. Expand `~` in Swift
(`expandingTildeInPath`) instead of in the shell.

## L2. AppleScript built by interpolation

**Status: fixed.** The message is now an argument to the script (`item 1 of argv`), never part of its source.
Checked with a message containing quotes, a backslash and `do shell script`: it's shown as text.

**Where:** `Clean.swift:507`.

**What:** the `osascript` fallback builds `display notification "\(message)" …`. Today `message` is always a fixed
title, so this is safe. A future message that includes a folder or simulator name with a `"` would break out of
the string, and AppleScript can run `do shell script`.

**Fix:** pass the text as an argument instead:
`osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "avp" sound name "Glass"' -e 'end run' <message>`.

## L3. Untrusted names printed raw

**Status: fixed.** `String.terminalSafe` (in `Print.swift`) replaces C0, DEL and C1 control characters with `?`. It
is applied to simulator and runtime names when they're read, to DeviceSupport folder names, to every line of the
scan output, and to large-folder paths in the checklist, confirmation and result messages. Paths are still deleted
using the original string. A folder name containing a newline can still split the scan's text output into an
extra line. That line now has to pass the on-disk check, so at worst it shows a wrong size for a real, allowlisted
folder you own.

**Where:** `Clean.swift:200-205` (simulator names), `Clean.swift:257` (DeviceSupport folder names),
`Clean.swift:345,363,374` (scan output and paths), `SystemScanner.swift:118-125` (parsing).

**What:** simulator names (user-editable) and folder names (including anything under the world-writable
`/private/tmp`) are printed as-is. A name containing ESC sequences can move the cursor or recolor text, so the
confirmation screen can show a different path from the one that will be deleted. OSC sequences can do more in
some terminals (title, clipboard). The scan result is also parsed line by line, so a folder name containing a
newline adds a fake line to the parsed list. That fake line still has to pass the allowlist, but combined with M3
it can aim at a chosen path.

**Fix:** strip control characters (C0, DEL, C1) from every label before printing. Ideally return the scan as
structured data (path and size from the awk step, split on `\t` or `\0`) instead of parsing the display text.

## L4. Secrets and client data in git history

**Where:** commits `e94b8c4` (2024-10-10, "start pusher") and `b7b0499` (2024-10-11). Both are reachable from
`origin/development` and `origin/main` on GitLab. Anonymous access to the GitLab project returns 404, so the repo
is private.

**What is in history:** two APNs provider JWTs (expired, issued October 2024), the Apple Team ID and APNs Key ID,
two device tokens, the client app's bundle ID, and a marketing deep link with campaign IDs. **The `.p8` private key
was never committed.**

**Impact:** the JWTs expired long ago and can't be reused without the private key. Team and Key IDs aren't secret
on their own. The real issue is client (Mango) identifiers kept in a personal GitLab repo, which may conflict with
your client or employer policy.

**Fix (your decision):**
1. In the Apple Developer portal, revoke the APNs key referenced in history if it's no longer used. This is the
   step that actually removes risk.
2. Only if policy requires it: rewrite history (`git filter-repo` to drop `Pusher.swift`'s history) and
   force-push both branches. That is destructive and changes every commit hash, so it needs your go-ahead.

No cached token is left in `defaults` (checked: no `authToken` key in the `avp` domain).

## L5. No guard against running as root

**Where:** `main.swift` / `Clean.run()`.

**What:** under `sudo`, `~`, `NSHomeDirectory()` and `getuid()` refer to root or a mix of root and you, depending
on how sudo sets `HOME`. Then `rm -rf ~/…` and the allowlist base point at different trees, and
`simctl erase all` runs as root.

**Fix:** at startup, `guard getuid() != 0 else { throw "Don't run avp with sudo" }`.

## L6. Old, capped dependency

**Where:** `Package.swift:12`, `Package.resolved`.

**What:** `swift-argument-parser` resolves to **0.5.0** (2021). `from: "0.3.0"` means `0.3.0 ..< 1.0.0`, so it will
never move to 1.x and its fixes. No known advisories affect it, but it's well behind. `Package.resolved` is
tracked (good, it pins the revision) while `.gitignore` lists it as ignored, which is contradictory.

**Fix:** `.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")`, rebuild, re-run tests,
and remove `Package.resolved` / `*.resolved` from `.gitignore` so the pin stays deliberate.

## L7. `shell()` robustness

**Status: fixed.** `runProcess` uses `try task.run()` (a launch failure is exit code 127 with a message, not a crash)
and reads the pipe before `waitUntilExit()`. Input, when given, is written on a background thread so a large input
and a large output can't deadlock. Tests cover 300 KB of output and 500 KB of input.

**Where:** `Global.swift:24-28`.

**What:** it calls `waitUntilExit()` *before* reading the pipe. If a command writes more than the pipe buffer
(64 KB), the child blocks and `avp` hangs forever. `simctl list devices -j` is 12 KB here, so about five times more
simulators would trigger it. The deprecated `launch()` also raises an Objective-C exception (crash) instead of a
Swift error if the launch fails.

**Fix:** use `try task.run()` and read the pipe *before* `waitUntilExit()`, as `DiskUsage.measure` already does.

---

## Checked and fine

- **No secrets in the current tree.** No network code remains after removing Pusher.
- **`.claude/settings.local.json` and `/specs` are untracked**, so they're not pushed.
- **`DiskUsage` temp file** is in the per-user `$TMPDIR` with a UUID name, so it's not predictable or shared.
- **DeviceSupport deletion** uses names from a directory listing and `removeItem`, which deletes a symlink itself,
  not its target. Hidden entries are skipped.
- **Claude jobs tmp cleanup** uses `find … -type d` with depth limits, so it never matches a symlink named `tmp`,
  and `rm -rf` doesn't follow symlinks inside.
- **Trash cleanup** limits `find` to depth 1 inside `~/.Trash`.
- **Large-folder scan** uses absolute tool paths (`/usr/bin/du`, `/usr/bin/awk`, …) and suppresses `du` errors.
  Excluded folders (`/System`, `/private/var`, …) are dropped before the allowlist is consulted.
- **Prompts fail closed:** EOF on stdin ends in `fatalError`, so piping empty input never confirms a deletion.
- **`-d` range** is validated (`didSet`), and out-of-range values stop the program.
- **`buildWithTimingSummary.sh`** is excluded from the build and never run. Its shebang is broken (`! /bin/bash`),
  which is harmless.

## Outside the repo (seen while checking)

- `~/Desktop/AuthKey_*.p8`, a different Apple private key from the one in history, sits on a Desktop that
  appears to be synced to iCloud Drive, with mode `644`. Your Desktop folder is `700`, so other local users can't
  read it, but the key is in your iCloud. Move it to a password manager or a non-synced folder, and `chmod 600` it.

## Suggested order

1. **M1**: remove the wildcard awk rules and `swift run *` (2 minutes, closes the agent path).
2. **L4 step 1**: revoke the old APNs key if unused.
3. **M2**: confirm Trash, Teams and Archives everywhere, and name them in the `all` prompt.
4. **M3 + L3**: resolve symlinks and strip control characters before deleting from the scan list.
5. **L1 + L7**: replace `shell()` string commands with `Process` and argument arrays, reading output before waiting.
6. **L5, L6, L2**: small hardening.
