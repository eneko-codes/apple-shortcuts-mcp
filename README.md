<p align="center">
  <img src="extension/icon.png" width="128" height="128" alt="apple-shortcuts-mcp icon">
</p>

# apple-shortcuts-mcp

A local MCP server, written in Swift, exposing the macOS **Shortcuts** library to
Claude through **Shortcuts Events**, the faceless helper app macOS ships for exactly
this. It ships as a Claude extension.

No network, no credential, no cloud API — everything happens over Apple events sent
to a process already on the machine, and the gate is macOS **Automation** consent, not
authentication.

Not affiliated with or endorsed by Apple Inc.

## Requirements

- macOS 15 or later
- Swift 6.0 or later (Xcode 26 ships it)
- A code signing identity. Ad-hoc works, but every rebuild then asks for permission
  again — see [Signing](#signing-and-why-it-is-not-optional).

## Tools

| Tool | Kind | What it does |
|---|---|---|
| `shortcuts_status` | read | Reports whether this server may control Shortcuts, and exactly what to enable if not. Asks macOS directly, without sending an Apple event, so it answers even when access is denied. |
| `shortcuts_list` | read | Every shortcut this server can see: folder, whether it accepts input, action count. Filterable by `query` (name/subtitle) and `folder`, paged with `limit`/`offset`. |
| `shortcut_get` | read | Full record for one shortcut, by `name` or `id`: name, id, subtitle, folder, whether it accepts input, action count. |
| `run_shortcut` | **irreversible** | Runs one shortcut through Shortcuts Events, in the background, and returns whatever it outputs. |

## Frameworks and APIs

Everything here is an Apple event sent to `com.apple.shortcuts.events`, the faceless helper
that runs a shortcut without opening the Shortcuts app.

| Used | For | Reference |
|---|---|---|
| ScriptingBridge — `SBApplication`, `SBElementArray` | Every read and write | [ScriptingBridge](https://developer.apple.com/documentation/scriptingbridge) |
| `AEDeterminePermissionToAutomateTarget` | Checking Automation consent without sending an event | [Apple Events](https://developer.apple.com/documentation/coreservices/apple_events) |
| `NSAppleEventsUsageDescription` | The consent string macOS shows | [Information Property List](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription) |

The Shortcuts Events dictionary is two classes — `folder` and `shortcut` — and one command,
`run`. That is the entire surface: there is no command to read a shortcut's actions, and none
to create or install one, which is why this server cannot do either.

## The rules worth knowing before you use it

**The contents of a shortcut cannot be read.** No API exposes the actions inside one —
not Shortcuts Events, not the command line, not any framework — so `shortcut_get`
reports the action count and says plainly that this is all there is. To know what a
shortcut does, open it in the Shortcuts app; nothing here can tell you.

**A shortcut cannot be created or installed from here**, by this server or by anything
else. There is no `shortcuts import` subcommand, and the Shortcuts store is
TCC-protected. The only route macOS offers is a person opening a `.shortcut` file by
hand and choosing "Add Shortcut".

**`run_shortcut` cannot know what a shortcut does, cannot undo it, and cannot stop it
once it has started.** A shortcut is a program the owner wrote — running one can send a
message, change a file, or control a device — and this server has no way to inspect it
first or intervene once it is running. A shortcut that waits for someone to tap
something will never finish, because it runs with no interface.

**There is no allow-list or name-prefix scope.** The whole library is listable and
runnable the moment permission is granted; the only gate on what `run_shortcut` may
actually do is its own allow/ask/prohibit switch in Claude Desktop, not a name check in
this code.

**Shortcuts Events, never `/usr/bin/shortcuts`.** The CLI would mean building a command
line out of a name the model chose and parsing text back out of a temp file — a script
for caller text to be spliced into. Shortcuts Events instead takes the shortcut name
and input as typed Apple event parameters and hands the result straight back, so there
is no string for a quote or an apostrophe to break and no file to clean up.

**A run is bounded by a timeout, fixed at 120 seconds.** That bounds the wait, not the
shortcut: nothing here can stop one once it has started, so giving up on a hung reply is
the only option when a shortcut is blocked on a dialog or an unreachable device.

**Output is text, capped at 4,000 characters, and truncation is reported.** A shortcut
whose result is an image or a file says that it produced one rather than pretending its
contents fit in text. Only text can be sent as `input`, too — a file or an image cannot
be passed in.

**Prefer `id` over `name`.** An id survives a rename; a name does not. `shortcut_get`
and `run_shortcut` take either but not both — if they disagree there is no right guess.
A name matching more than one shortcut is refused as ambiguous, with the ids listed,
rather than silently picking the first match.

**A pending consent does not block a call.** macOS only raises the Automation dialog
when a real Apple event is sent, so refusing a call while consent is merely
`.consentNotGranted` would mean the dialog never appears and permission could never be
granted at all. Only an actual denial or a missing Shortcuts Events installation blocks
a call outright.

## Implementation note: why the Apple events are in Objective-C

Every Apple event this project sends lives in the `ShortcutsBridge` target, written in
Objective-C. Scripting Bridge builds its classes at runtime, so their metadata symbols
do not exist at link time, and a Swift metatype cast against one aborts the process
(swiftlang/swift#43407, open since 2016). In Objective-C a cast to a protocol is a
compile-time annotation and nothing has to be bridged at all. Only Foundation types
cross back into `ScriptingBridgeShortcutsStore` in Swift — no Scripting Bridge object
escapes the bridge target.

## Install

### 1. Build the bundle

```bash
MCPB_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/pack.sh
```

That builds a universal (arm64 + x86_64) release binary, signs it, checks the embedded
`Info.plist` survived both linking and signing, prints the designated requirement, and
writes `dist/apple-shortcuts-mcp.mcpb`. It fails loudly rather than shipping a bundle
that would silently refuse to work.

```bash
security find-identity -v -p codesigning
```

### 2. Install it

Open `dist/apple-shortcuts-mcp.mcpb` with Claude. Then **quit Claude Desktop
completely and reopen it** — reinstalling does not replace a server process that is
already running, and the old one keeps answering with the old binary.

### 3. Grant the permission

Call `shortcuts_status` first; it reports the permission state without sending an
Apple event, so it is safe to call even when access is denied. Then call
`shortcuts_list` — macOS raises *"apple-shortcuts-mcp wants to control Shortcuts
Events"*. If the dialog names **Shortcuts** rather than **Shortcuts Events**, something
is reaching the wrong application. Approve it, and the grant appears under System
Settings → Privacy & Security → Automation
(Spanish UI: Ajustes del Sistema → Privacidad y seguridad → Automatización).

The binary is **its own privacy subject**: Claude Desktop launches MCP servers through
`Contents/Helpers/disclaimer`, which calls `responsibility_spawnattrs_setdisclaim`, so
the child cannot inherit the host app's permissions. Hence the embedded
`Resources/Info.plist` and its `NSAppleEventsUsageDescription`.

If no dialog ever appears:

```bash
otool -P extension/server/apple-shortcuts-mcp | grep NSAppleEventsUsageDescription
```

### Signing, and why it is not optional

`swift build` leaves a signature the linker generated, flagged `linker-signed`. macOS
treats that as signed by nobody: it produces **no designated requirement**, so there is
nothing to anchor a permission to except the binary's cdhash — and every rebuild
changes that. Worse, a linker-signed binary never gets a consent dialog at all; the
request returns with the status still "not determined".

Signing with a real certificate produces a requirement anchored to the bundle
identifier and the certificate instead:

```
designated => identifier "codes.eneko.apple-shortcuts-mcp" and anchor apple generic
              and certificate leaf[subject.CN] = "Apple Development: …"
```

That survives rebuilds. `pack.sh` prints the requirement on every build, so a silent
regression to ad-hoc is visible immediately.

**Changing certificate re-prompts once.** The requirement quotes the certificate, so
moving between ad-hoc, Apple Development and Developer ID each costs one fresh round of
consent.

### Preparing something to distribute

```bash
MCPB_HARDENED=1 MCPB_SIGN_IDENTITY="Developer ID Application: …" ./scripts/pack.sh
```

That adds the hardened runtime and a secure timestamp, which notarisation requires.
The hardened runtime blocks Apple events outright unless
`com.apple.security.automation.apple-events` is granted via
`Resources/entitlements.plist` — `pack.sh` applies that file automatically **if it
exists**, but this repository does not currently ship one. Add it before shipping a
hardened build, or Shortcuts Events becomes unreachable.

## Tool switches

Plug and play: there is nothing to configure. Every tool can be turned on and off
individually, because the bundle declares them all in its manifest — that is where
policy lives, not in this code. Turning off `run_shortcut` leaves a strictly read-only
server that can list and describe shortcuts but never run one.

**Reinstalling may reset the switches.** Check them after every install.

## Manual registration instead

```json
{
  "mcpServers": {
    "Apple Shortcuts": {
      "command": "/absolute/path/to/apple-shortcuts-mcp/.build/release/apple-shortcuts-mcp"
    }
  }
}
```

You lose the per-tool switches — including the one that disables running shortcuts. Do
not do both at once: two registrations under the same display name collide, and
`shortcuts_status` prints the binary path precisely so you can tell which one answered.

## Known limits

- **The action list inside a shortcut cannot be read**, by this server or by anything
  else short of opening it in the Shortcuts app. This is a missing macOS API, not a
  choice made here.
- **Shortcuts cannot be created, installed or edited from here.** Generating and
  signing a `.shortcut` file is possible outside this server, but adding it to the
  library still requires a person to open it and choose "Add Shortcut" by hand.
- **`run_shortcut` cannot stop a shortcut once it has started**, and cannot undo
  anything it did. A shortcut waiting on user interaction runs with no interface and
  will simply hang until the timeout gives up on the wait.
- **Only text can be passed as input**, and only text is returned. A shortcut that
  produces an image or a file reports that it did, not the contents.
- **`shortcuts_list`'s `query` only matches name and subtitle** — there is nothing
  deeper to search, since a shortcut's internals are not readable in the first place.
- **The internal timeout (120s) and result limit (4,000 characters) are fixed in this
  packaging.** `Configuration` still accepts `--result-limit` and `--timeout-seconds`
  flags, but the extension's `mcp_config.args` is empty, so they only apply if you run
  the binary yourself with your own arguments — see
  [Manual registration](#manual-registration-instead).
- **Whether this works with nobody logged in at the screen has not been recorded
  here.** Check it by hand — Shortcuts Events over SSH at the login window — before
  relying on this on an always-on Mac.

## Development

```bash
swift build
swift test
```

38 tests across two suites (`ShortcutsToolsTests`, `ConfigurationTests`), all against
an in-memory fake — nothing is run and nothing in the real Shortcuts library is
touched. See `CLAUDE.md`, whose first section is the hard rule that makes that
non-negotiable: no agent may run a shortcut that exists on this Mac.

Manual verification against the real Shortcuts library is the owner's job, by hand,
with MCP Inspector.

## Licence

MIT.
