# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Data rule

Do not run an existing shortcut the owner made — a shortcut's contents cannot be inspected before running it, and running one is arbitrary code (it could send a message, delete files, buy something). Test shortcuts must be clearly named `TESTING: ...`, contain only harmless actions (e.g. Text / Stop and Output), and be removed when done — note that shortcuts cannot be created or installed programmatically, only run.

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
