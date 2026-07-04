# Developer Folder Cleanup Guide

This guide explains what each cleanup option removes, the risk level, and whether data regenerates automatically.

**Disk usage snapshot (as of 2026-07-03):**
- CoreSimulator: 42G
- XCTestDevices: 11G
- iOS DeviceSupport: 11G
- XCPGDevices: 3.6G
- DocumentationCache: 1.5G
- Archives: 0B

**Total potential savings: ~69G** (if all deleted)

---

## Low-Risk Options (Safe to Delete)

### Option 1: Simulators Data & Keychains (`~/Library/Developer/CoreSimulator`)

**What it contains:**
- Downloaded iOS/iPadOS simulator runtime images
- Simulator device data (user defaults, documents, library caches)
- Cached dyld libraries (shared object cache)

**Safe to delete?** ✅ **YES — Low risk**

**What happens when deleted:**
- Xcode re-downloads simulator runtimes on next use (takes 10–30 minutes)
- All simulator data (like installed test apps) resets to factory state
- Next simulator launch is slower due to cache rebuild

**When to use:** When you need space and don't actively develop on simulators (or can afford the re-download time).

**Regeneration:** Automatic, ~15–30 minutes.

---

### Option 2: Cloned Simulators Data & UserDefaults (`~/Library/Developer/XCTestDevices` + `~/Library/Developer/XCPGDevices`)

**What it contains:**
- **XCTestDevices:** Temporary device clones created during UI test runs
- **XCPGDevices:** Temporary device clones created by Xcode Previews

**Safe to delete?** ✅ **YES — Low risk**

**What happens when deleted:**
- Next test run or Preview rebuild creates fresh clones automatically
- No loss of source code or build artifacts

**When to use:** When you're not actively running tests or Previews.

**Regeneration:** Automatic on next use, instant.

---

### Option 8: Documentation Cache (`~/Library/Developer/Xcode/DocumentationCache`)

**What it contains:**
- Downloaded QuickHelp documentation (Apple frameworks, installed packages)
- Documentation indexes and cross-references

**Safe to delete?** ✅ **YES — Low risk**

**What happens when deleted:**
- QuickHelp (Option+click on symbols) is slower the next time you access unfamiliar documentation
- Xcode re-downloads missing docs on first access
- No interruption to builds or running code

**When to use:** When you need space and can tolerate slower QuickHelp initially.

**Regeneration:** Automatic on-demand, slower (background download).

---

## Medium-Risk Options (Require Confirmation)

### Option 3: DerivedData (`~/Library/Developer/Xcode/DerivedData`)

**What it contains:**
- Build artifacts (.app, .o files, compiled modules)
- Build cache and indexes
- Debugger symbols

**Safe to delete?** ⚠️ **MEDIUM risk**

**What happens when deleted:**
- Your project rebuilds from scratch on next build (takes 2–5x longer initially)
- First build after deletion is slow; subsequent builds use incremental compilation

**When to use:** When builds are behaving oddly (corrupted cache) or you need maximum space and can rebuild.

**Regeneration:** Automatic on next build, ~5–15 minutes for clean build.

---

### Option 5: iOS DeviceSupport (`~/Library/Developer/Xcode/iOS\ DeviceSupport`)

**What it contains:**
- Device support files for physical iOS/iPadOS devices you've connected
- Firmware symbols, debugging tools, and compatibility shims
- Separate folders for each iOS version you've developed against

**Safe to delete?** ⚠️ **MEDIUM risk** (only if you don't actively use physical devices)

**What happens when deleted:**
- If you plug in a physical device, Xcode re-downloads support files from Apple's servers (~500MB–2GB depending on iOS version)
- This download happens automatically but can take 5–15 minutes
- Your source code and builds are unaffected

**When to use:** If you only develop on simulators, or can tolerate the re-download delay.

**Regeneration:** Automatic when you connect a device (slower, requires internet). If you don't connect devices, it never regenerates.

**⚠️ Caution:** If you're actively doing physical device testing or debugging, delete this option only during downtime.

---

### Option 4: Archives (`~/Library/Developer/Xcode/Archives`)

**What it contains:**
- Compiled .ipa files from past `Archive for Distribution` builds
- Associated dSYM files (debug symbols for crash reporting)

**Safe to delete?** ⚠️ **MEDIUM risk** (cannot be regenerated easily)

**What happens when deleted:**
- Old archives are permanently deleted
- You cannot re-sign or re-distribute an old build
- You cannot use old dSYMs to symbolicate crash reports from old builds
- Your source code is unaffected; you can rebuild if needed

**When to use:** Only if you're certain you don't need old builds for re-signing or debugging. Can free space if you've archived many production builds.

**Regeneration:** NOT automatic. You must rebuild from source to get a new archive.

**⚠️ Caution:** If you support older versions of your app or need crash symbolication, keep archives. If you use a CI system (e.g., Fastlane) that manages archives, this option may not apply.

---

## Option Selection Quick Reference

| Goal | Use | Options |
|------|-----|---------|
| Free max space, don't need simulators | `clean all` | 0, 1, 2, 3, 4, 5, 8 |
| Quick rebuild after cache corruption | Option 3 | DerivedData |
| Free space, keep recent archives | 0 without option 4 | All except Archives |
| Clean up after heavy testing | Option 2 | XCTestDevices + XCPGDevices |
| Just free easy space | Option 8 | DocumentationCache |

---

## Safety Summary

**Safe to delete anytime:**
- CoreSimulator (Option 1)
- XCPGDevices (Option 2)
- XCTestDevices (Option 2)
- DocumentationCache (Option 8)

**Delete with caution:**
- DerivedData (Option 3) — causes slow rebuild, not permanent loss
- iOS DeviceSupport (Option 5) — only if not using physical devices
- Archives (Option 4) — cannot regenerate; only if confident

