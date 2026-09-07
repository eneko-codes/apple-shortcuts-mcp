# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Data rule

Do not run an existing shortcut the owner made — its contents cannot be inspected before running it, and running one is arbitrary code (it could send a message, delete files, buy something).

**Tests run against fakes** — in-memory doubles, fixtures, data invented for the test. Never the owner's real Shortcuts library, and never out of convenience: the suite exists to catch breaking changes and does not need real data to do that.

**Debugging against live data is legitimate, but it is the owner's call, not yours.** Never decide it alone. Ask in chat as an explicit choice they can pick — not a remark inside a longer message — saying exactly what you will run, exactly which live data it would touch, and what it would create, change or delete and whether that is undoable. A yes covers that run only; a wider or different check needs a fresh question.

**Running anything from the real library needs the ask above, every time.** There is no gentle route around it: a shortcut cannot be created or installed programmatically, only run. A test shortcut the owner makes for you must be named `TESTING: ...`, contain only harmless actions (e.g. Text / Stop and Output), and be removed when done.

## What this is

A local MCP server (Swift 6, stdio transport) that lists and runs the shortcuts already installed on this Mac, via Shortcuts Events. No network, no credential, no cloud API, gated by TCC consent for Apple events.

## Commands

```bash
swift build
swift build -c release
swift test
```

```bash
otool -P .build/release/apple-shortcuts-mcp | grep NSAppleEventsUsageDescription
```
