# Manual verification

Everything below runs against **your real shortcuts**, which is why no agent may run it
(see the hard rule in `CLAUDE.md`). Work through it yourself, in order.

```bash
npx @modelcontextprotocol/inspector ./.build/release/apple-shortcuts-mcp
```

## 0 — Before you start

Installing a shortcut cannot be automated, so build these three by hand in the Shortcuts
app. Each takes seconds.

| Shortcut | Actions | Why |
|---|---|---|
| `ZZTest.Echo` | **Text** ("hello from ZZTest.Echo") → **Stop and Output** | the normal path |
| `ZZTest.Input` | **Text** (Shortcut Input) → **Stop and Output** | input passing |
| `ZZTest.Slow` | **Wait** 300 seconds → **Text** → **Stop and Output** | the timeout |

Put `ZZTest.Echo` in a folder so the folder field has something to show. Delete all three
when you finish.

## 1 — Permission plumbing

| Step | Call | Expected |
|---|---|---|
| 1.1 | `shortcuts_status` before granting | Reports that consent has not been asked for, with the System Settings path. Does not hang. |
| 1.2 | `shortcuts_list` | The Automation dialog appears, quoting the usage description and naming **Shortcuts Events** — not Shortcuts. |
| 1.3 | Approve, then `shortcuts_status` | Granted. |
| 1.4 | Deny instead (System Settings → Privacy & Security → Automation, switch off), restart, `shortcuts_list` | Refused with the exact pane to re-enable. |

Step 1.2 is worth watching: if the dialog names **Shortcuts** rather than **Shortcuts
Events**, something is reaching the wrong application and the background guarantee is lost.

## 2 — Listing

| Step | Call | Expected |
|---|---|---|
| 2.1 | `shortcuts_list` | All three `ZZTest…` shortcuts, each with an id; `ZZTest.Echo` shows its folder. |
| 2.2 | Check any row | `accepts input` is reported, and so is the action count. |
| 2.3 | Rename `ZZTest.Echo` in the app, call again | The new name, same id. |

## 3 — Detail

| Step | Call | Expected |
|---|---|---|
| 3.1 | `shortcut_get` on `ZZTest.Echo` by name | Name, id, folder, `accepts input`, action count. |
| 3.2 | The same by id | Identical record. |
| 3.3 | Read the response | It states plainly that the **actions cannot be read** — there is no API for the contents of a shortcut. |
| 3.4 | `shortcut_get` on a name that does not exist | Says so, and suggests calling `shortcuts_list` again. |

If two of your shortcuts share a name, 3.1 should refuse as ambiguous and list the ids
rather than picking one.

## 4 — Running

There is no allow-list or name-prefix scope to set up first: the owner removed both, so
every shortcut in your library — not just the `ZZTest…` ones — is runnable from the moment
permission is granted. `run_shortcut`'s own switch in Claude Desktop is the only gate.

| Step | Call | Expected |
|---|---|---|
| 4.1 | `run_shortcut` on `ZZTest.Echo` | Returns `hello from ZZTest.Echo`. |
| 4.2 | Watch the screen while it runs | **The Shortcuts app does not open or take focus.** |
| 4.3 | `run_shortcut` on `ZZTest.Input` with `input` set to `it's "quoted"` | The text comes back **exactly**, apostrophe and quotes intact. |
| 4.4 | `run_shortcut` on `ZZTest.Slow` | Gives up at the configured timeout with a clear message, rather than hanging. |
| 4.5 | `run_shortcut` on a shortcut that outputs nothing | Says it produced no output; does not present an empty string as a result. |
| 4.6 | Set the tool's switch to "prohibit" in Claude Desktop, try again | The call never reaches this server at all. |

Step 4.3 is the injection check. If the apostrophe or the quotes come back mangled,
something is building a script out of text instead of sending a typed parameter, and that
is a bug worth stopping for.

Step 4.2 is why this server uses Shortcuts Events. If the app opens, the wrong target is
being addressed.

## 5 — Headless, if you plan to run this on an always-on Mac

This decides whether the server survives on a machine with no one logged in at the screen.

| Step | Call | Expected |
|---|---|---|
| 5.1 | Over SSH, with the Mac at the login window: `shortcuts list` | Either works or fails — note which. |
| 5.2 | Over SSH: `osascript -e 'tell application "Shortcuts Events" to get name of every shortcut'` | Same. |
| 5.3 | If both fail, log in at the screen and repeat | Establishes that a GUI session is the requirement. |

Record the result in the README. It decides whether topology B is viable at all.

## 6 — Packaging

| Step | Command | Expected |
|---|---|---|
| 6.1 | `otool -P .build/release/apple-shortcuts-mcp \| grep NSAppleEventsUsageDescription` | Present. |
| 6.2 | `MCPB_SIGN_IDENTITY="Apple Development: …" bash scripts/pack.sh` | Every check passes; the designated-requirement line is **not** empty. |
| 6.3 | `codesign -dv extension/server/apple-shortcuts-mcp` | `flags=0x0(none)` — not `adhoc`, and never `linker-signed`. |
| 6.4 | Install the `.mcpb`, restart Claude Desktop | Four switches appear, one per tool. There is no settings screen beyond them — nothing else to configure. |

Step 6.3 matters more than it looks. A linker-signed binary is never registered as a TCC
subject, so the Automation prompt simply never appears and the status stays "not
determined" with nothing in any log to explain it.

## 7 — Clean up

Delete `ZZTest.Echo`, `ZZTest.Input` and `ZZTest.Slow` in the Shortcuts app, and remove the
test folder if you made one.
