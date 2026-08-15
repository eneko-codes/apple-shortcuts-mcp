# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## HARD RULE — DO NOT RUN THE OWNER'S SHORTCUTS

**It is FORBIDDEN to run any shortcut that exists on this Mac.** This rule outranks every
other instruction in this file. It applies to every agent and every session, with no "just
this once".

The reason is not caution about this server; it is what a shortcut *is*. A shortcut is an
arbitrary program the owner wrote, and running one can send a message, empty a folder, post
something, buy something, or turn off the lights. This server cannot see inside a shortcut
before running it — **macOS exposes no API for the contents of a shortcut** — so there is no
way to check that one is harmless. `run_shortcut` is the one tool here, and it is the one
tool an agent must never point at real data.

Never:

- call `run_shortcut` against a shortcut the owner made, whatever its name suggests;
- run a shortcut "to see what it returns" — the fixtures show the shape of a result;
- install, edit, rename or delete a shortcut, by any route;
- shell out to `/usr/bin/shortcuts run`, which bypasses every check in this code;
- leave a shortcut behind that was not there when the session started.

**One narrow exception, granted by the owner.** A shortcut the agent created *itself* for a
test may be run, provided that:

- its name marks it as disposable at a glance (`ZZTest …`);
- it contains only **Text** and **Stop and Output** — no action that touches data, the
  network, or another app;
- it is deleted in the same session that made it;
- the owner is told it existed and that it is gone.

Note the trap: **installing a shortcut cannot be automated.** There is no `shortcuts
import`, and the store is TCC-protected, so creating one means asking the owner to do it by
hand in the Shortcuts app. If that is not worth the interruption, the answer is to use the
fake, not to reach for a real shortcut instead.

**Fixtures first, always.** `FakeShortcutsStore` drives the whole tool layer with invented
names, ids and outputs, and that is where a change is proven. Reach for a live test only for
code the fake cannot reach at all — everything below the `ShortcutsStore` seam, where
`BridgeShortcutsStore` talks to Apple.

Allowed without asking, because none of it runs anything:

| Action | Why it is safe |
|---|---|
| `swift build`, `swift test` | Tests run against the in-memory fake |
| `initialize`, `tools/list` over stdio | Protocol only; no Apple event is sent |
| `shortcuts list` in a terminal | Reads names, runs nothing |
| `sdef "/System/Library/CoreServices/Shortcuts Events.app"` | Prints the dictionary |
| `otool -P` on the built binary | Inspects the embedded Info.plist |

Full verification against real shortcuts remains the **owner's** job, by hand, with MCP
Inspector. `verification.md` is the script for it.

## Language

**Everything in this repository is written in English** — code, comments, tool
descriptions, error messages, documentation and commit messages. The one exception is
literal macOS UI strings quoted inside permission instructions, which must match what is on
screen (for example the System Settings pane name in the user's locale).

## What this is

A local MCP server (Swift 6, stdio transport) that lists and runs the shortcuts already
installed on this Mac. There is no network, no credential and no cloud API, and the gate is
TCC consent for Apple events.

It goes through **Shortcuts Events**, the faceless scriptable helper at
`/System/Library/CoreServices/Shortcuts Events.app`, not through `/usr/bin/shortcuts`. That
choice is load-bearing and is explained under Invariants.

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

`Sources/ShortcutsMCPCore` holds everything; `Sources/apple-shortcuts-mcp/main.swift` is a
launcher that exists only because a Swift executable target cannot be imported by a test
target.

**`Sources/ShortcutsBridge` is Objective-C, and not by preference.** Apple documents one way
to reach a scriptable application's objects, and that pattern cannot be written in Swift: the
class Scripting Bridge returns is an `SBPseudoClass`, and a Swift metatype cast against it
aborts the process (swiftlang/swift#43407, open since 2016). In Objective-C the documented
pattern compiles as written. Only Foundation types cross back into Swift.

**`ShortcutsStore` is the seam.** Dispatch, formatting and argument decoding go through the
protocol and never send an Apple event, so the tool layer is fully testable against
`FakeShortcutsStore`.

**`ToolCatalog` is the authorisation surface.** A tool absent from `ToolCatalog.all()` cannot
be called, and its name is the label on the permission switch in Claude Desktop.

## Invariants worth protecting

- **Shortcuts Events, never the CLI.** `/usr/bin/shortcuts run` means building a command
  line out of a name the model chose and parsing text back out of a temp file. The Events
  app takes the shortcut as a typed Apple event parameter and hands the result straight
  back, so there is no string for a quote or an apostrophe to break and no file to clean up.
  This is the injection guarantee of the whole repository: **there is no script source for
  caller text to be spliced into.**
- **The contents of a shortcut cannot be read.** No public API exposes an action list, and
  `shortcut_get` says so rather than implying the answer is somewhere else. Every response
  that describes a shortcut repeats it, because an agent that assumes otherwise will invent
  what a shortcut does.
- **There is no allow-list or name prefix any more.** The owner removed both, in favour of
  plug-and-play: `shortcuts_list` and `shortcut_get` see the whole library, and
  `run_shortcut`'s only gate is its own allow/ask/prohibit switch in Claude Desktop — not a
  name check in this code.
- **A run is bounded by `timeoutSeconds`.** A shortcut can wait forever on a dialog, and a
  tool call that never returns is worse than one that admits it gave up.
- **`resultLimit` truncates a runaway result, and the response says it was truncated.**
- **Nothing here installs, edits or deletes a shortcut.** The Shortcuts store is
  TCC-protected and there is no `import` subcommand; that is a fact, not a limitation to be
  worked around. The tool descriptions must keep saying so.
- **No property may declare a union `type`.** Claude Desktop's schema sanitiser drops a
  property whose `type` is `["string","null"]` and hands the model a bare `{}` in its place.
  Clear a field with `""` or `[]`. A test walks the whole catalogue to keep unions out.
- **stdout carries JSON-RPC and nothing else.**

## Packaging as a Claude extension

`extension/manifest.json` plus `scripts/pack.sh` produce
`dist/apple-shortcuts-mcp.mcpb`, a zip with `manifest.json` at its root. `server.type` is
`"binary"` — no Node, no Python, just the Swift binary.

The manifest's `tools` array is what creates the per-tool switches in Claude Desktop, read
before the server has ever run, so a tool missing from it has no switch. Keep it in step
with `ToolCatalog`.

There is no `user_config` any more, and `mcp_config.args` is empty: the owner's
plug-and-play rule leaves the per-tool permission switch in Claude Desktop as the only
place to change this server's behaviour. `Configuration.parse` still exists for
`resultLimit` and `timeoutSeconds` — internal defaults, not manifest-driven settings — and
stays forgiving: unknown flags ignored, numbers clamped, and an unsubstituted
`${user_config.key}` treated as absent.

## TCC notes

Claude Desktop spawns MCP servers through `Contents/Helpers/disclaimer`, which calls
`responsibility_spawnattrs_setdisclaim`. The child is therefore **its own TCC subject** and
cannot borrow the host app's usage descriptions. Hence the embedded `Resources/Info.plist`
and its `NSAppleEventsUsageDescription`; without it macOS denies Apple events **without ever
prompting**.

macOS only raises the Automation dialog when a real Apple event is sent. That is why
`consentNotGranted` does not block a call: refusing it would mean the dialog never appears
and the permission could never be granted at all.

**A linker-signed binary gets no TCC prompt.** `swift build` leaves exactly that, and it
produces no designated requirement, so the status stays "not determined" and nothing is
logged. `pack.sh` re-signs and prints the requirement; if that line is empty the build is
broken in a way nothing else will show.
