# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Data rule

Do not run an existing shortcut the owner made — its contents cannot be inspected before running it, and running one is arbitrary code (it could send a message, delete files, buy something).

**Tests run against fakes** — in-memory doubles, fixtures, data invented for the test. Never the owner's real Shortcuts library, and never out of convenience: the suite exists to catch breaking changes and does not need real data to do that.

**Debugging against live data is legitimate, but it is the owner's call, not yours.** Never decide it alone. Ask in chat as an explicit choice they can pick — not a remark inside a longer message — saying exactly what you will run, exactly which live data it would touch, and what it would create, change or delete and whether that is undoable. A yes covers that run only; a wider or different check needs a fresh question.

**Running anything from the real library needs the ask above, every time.** There is no gentle route around it: a shortcut cannot be created or installed programmatically, only run. A test shortcut the owner makes for you must be named `TESTING: ...`, contain only harmless actions (e.g. Text / Stop and Output), and be removed when done.

## What this is

A local MCP server (Swift 6, stdio transport) that lists and runs the shortcuts already installed on this Mac, via Shortcuts Events. No network, no credential, no cloud API, gated by TCC consent for Apple events, **no third-party dependency**: `Package.swift` lists none, and the MCP protocol (JSON-RPC over stdio) is `MCPServer.swift` over Foundation. Adding a package needs the owner's say-so.

**`MCPServer.swift`, `Value.swift`, `ToolStandard.swift` and the tests `MCPProtocolTests.swift` and `ToolStandardTests.swift` are copied unchanged into every one of the owner's MCP servers** (the test files differ only in their `@testable import`). A change to one is made to every copy in the same piece of work; never let a copy drift.

`ToolStandard.swift` holds what every tool here must keep to: the longest result, description and error, the time a call may take, the fixed wording of each notice that says what a result left out (`Notice`), and the guard `MCPServer.swift` passes every result through. A tool bounds its own result and says how to get the rest; the guard only catches the one that forgot. `Deadline.swift` is the reference's `Deadline` enum, unchanged, until the shared file has it.

**How a tool keeps to the tool standard here.** Sizes are constants in `Configuration`, and the schemas, descriptions and instructions quote them by interpolation. `Arguments.int` moves a quantity into its range and collects the sentence that says so; an argument a tool does not take is refused in `Dispatch`. `shortcuts_list` sorts by name then id and goes through `ToolStandard.page`; `shortcut_get` windows the record with `ToolStandard.window`; `run_shortcut` cuts another program's output with the one sentence `Format.unrepeatableCut`, because it can never be asked for again. The whole library is read or the call fails, never a part of it. `BoundsTests` holds every bound, notice and length to this, and the README's figures to the constants.

## Apple technology

Everything is an Apple event to `com.apple.shortcuts.events`, the faceless helper that runs a shortcut without opening the Shortcuts app. [ScriptingBridge](https://developer.apple.com/documentation/scriptingbridge) — `SBApplication`, `SBElementArray` — for every read and write; `AEDeterminePermissionToAutomateTarget` ([Apple Events](https://developer.apple.com/documentation/coreservices/apple_events)) to check consent without sending an event; [AppKit](https://developer.apple.com/documentation/appkit) `NSWorkspace`/`NSRunningApplication` to see whether the app is there and running. Consent key: [`NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription).

## Native surface not used

`sdef "/System/Library/CoreServices/Shortcuts Events.app"` is the authority, and it is small: two classes, `folder` and `shortcut`, and one command, `run`.

- There is no command to read a shortcut's actions. The action count is all there is — never infer what a shortcut does from its name.
- There is no command to create or install a shortcut. Only a person can add one, by opening the file.
- `/usr/bin/shortcuts` is a separate route this server deliberately does not take.

## Commands

```bash
swift build
swift build -c release
swift test
```

```bash
otool -P .build/release/apple-shortcuts-mcp | grep NSAppleEventsUsageDescription
```

## Architecture

**Apple silicon only, deliberately.** `scripts/pack.sh` builds for arm64 alone — a plain `swift build -c release`, no `--arch` flags — and fails if the binary
holds any other architecture. A universal build doubles the bundle for an architecture
macOS 26 is the last release to support. Do not add an x86_64 slice back.

## Diagnostics

Logs go to stderr through `Diagnostics`, which the host captures (Claude Desktop writes it to `~/Library/Logs/Claude/mcp-server-<name>.log`). stdout is the JSON-RPC stream: never `print`. The API takes no free-form text on purpose. Do not add one, and do not log an argument, a result, an error's `localizedDescription` or an identifier; log a fixed event, the tool name, the error's kind and a duration.
