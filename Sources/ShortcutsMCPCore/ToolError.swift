import Foundation

public enum ToolError: Error, Equatable {
    case notAvailable(ShortcutsAvailability)
    case missingArgument(String)
    case badArgument(name: String, reason: String)
    case unknownTool(String)
    case unknownArgument(name: String, tool: String, taken: [String])
    case inputTooLong(characters: Int, limit: Int)
    case referenceRequired
    case bothNameAndID
    case notFound(reference: String)
    case ambiguousName(name: String, ids: [String])
    case timedOut(seconds: Int)
    case libraryNotRead(seconds: Int)
    case callTimedOut(seconds: Int, tool: String)
    case shortcutFailed(detail: String)
    case storeFailure(String)

    /// Candidate ids an error names; the count of the rest follows.
    static let candidatesShown = 5

    /// How much of another program's error text an error repeats. It is wider than
    /// `ToolStandard.echoWidth` because it is the reason for the failure, not a caller's
    /// text, but it is still bounded: a shortcut's own message has no length limit.
    static let detailWidth = 500

    static func clipped(_ detail: String) -> String {
        detail.count > detailWidth ? String(detail.prefix(detailWidth)) + "…" : detail
    }

    public var message: String {
        switch self {
        case .notAvailable(let state):
            return Self.availabilityMessage(state)

        case .missingArgument(let name):
            return "Missing required argument '\(name)'."

        case .badArgument(let name, let reason):
            return "Argument '\(name)' is not valid: \(reason)"

        case .unknownTool(let name):
            return "'\(ToolStandard.echo(name))' is not a tool of this server."

        case .unknownArgument(let name, let tool, let taken):
            let list = taken.isEmpty ? "It takes no arguments." : "It takes: \(taken.joined(separator: ", "))."
            return "'\(ToolStandard.echo(name))' is not an argument of \(tool). \(list)"

        case .inputTooLong(let characters, let limit):
            return """
                Argument 'input' is \(characters) characters long; the most a run accepts is \
                \(limit).

                The shortcut was not run. Input is never cut, because a shortcut run on part of \
                what was meant would do the wrong thing without anyone knowing. Pass less of it, \
                or have the shortcut read the rest itself.
                """

        case .referenceRequired:
            return """
                Say which shortcut you mean: pass 'name' or 'id'.

                Call shortcuts_list to see the library. Names come from there, and so do
                ids — an id is the safer of the two, because a shortcut keeps it when it is
                renamed.
                """

        case .bothNameAndID:
            return """
                Pass 'name' or 'id', not both.

                If they disagree there is no right answer, and guessing one would run
                something nobody asked for. Use 'id' when you have it.
                """

        case .notFound(let reference):
            return """
                No shortcut matches '\(ToolStandard.echo(reference))'.

                Names are matched exactly first, then ignoring case. A shortcut can be
                renamed or deleted from the Shortcuts app at any moment, so call
                shortcuts_list again rather than reusing a name or id from earlier in the
                conversation.
                """

        case .ambiguousName(let name, let ids):
            let shown = ids.sorted().prefix(Self.candidatesShown)
            let others = ids.count - shown.count
            let more = others > 0 ? " and \(others) more" : ""
            return """
                More than one shortcut is named '\(ToolStandard.echo(name))', so this is not \
                enough to say which one to run.

                \(ids.count) match. Ids: \(shown.joined(separator: ", "))\(more)

                Call again with 'id' instead of 'name'. shortcuts_list with 'query' lists every \
                match, and shortcut_get on an id shows the folder and action count, which is \
                usually what tells them apart.
                """

        case .timedOut(let seconds):
            return """
                The shortcut did not finish within \(seconds) seconds, so the wait was
                abandoned.

                IT MAY STILL BE RUNNING. Only the wait was given up, not the shortcut —
                nothing here can stop one once Shortcuts has started it. Check the Shortcuts
                app before running it again, and do not assume it failed.

                The limit cannot be raised from here: the client itself abandons a request
                after about a minute. A shortcut that needs longer has to be run from the
                Shortcuts app to see how it ends. One that waits for a person to tap something will never
                finish here: Shortcuts Events runs it with no interface to tap.
                """

        case .libraryNotRead(let seconds):
            return """
                The library was not read within \(seconds) seconds, so nothing is listed.

                Nothing was changed and nothing was run. Shortcuts Events may be busy or \
                waiting on a dialog; every shortcut costs several Apple events, so a very \
                large library is slow. No argument makes this cheaper, because the whole \
                library is read before it is narrowed. Try again, and open the Shortcuts \
                app if it keeps failing.
                """

        case .callTimedOut(let seconds, let tool):
            guard tool == ToolCatalog.runName else {
                return """
                    The call did not finish within \(seconds) seconds and was abandoned. This \
                    tool only reads, so nothing was changed.

                    Shortcuts Events may be busy or not answering. Try again; shortcuts_status \
                    says whether this server may still reach it.
                    """
            }
            return """
                The call did not finish within \(seconds) seconds and was abandoned.

                THE SHORTCUT MAY HAVE RUN, OR STILL BE RUNNING. Only the wait was given up, and \
                nothing here can stop a shortcut or tell how far it got. Check the Shortcuts app \
                before running it again, and do not assume it failed.
                """

        case .shortcutFailed(let detail):
            return """
                The shortcut started and then stopped with an error: \(Self.clipped(detail))

                IT MAY HAVE DONE PART OF ITS WORK. Its actions run in order and nothing is
                undone when one fails, so whatever came before the failing action has
                already happened. Check the Shortcuts app before running it again.

                A shortcut that expects a file, an image or a choice made on screen can fail
                this way when it is given text or run with no interface.
                """

        case .storeFailure(let detail):
            return "Shortcuts returned an error: \(Self.clipped(detail))"
        }
    }

    static func availabilityMessage(_ state: ShortcutsAvailability) -> String {
        switch state {
        case .ready:
            return "Shortcuts is reachable."

        case .notInstalled:
            return """
                Shortcuts Events is not installed on this Mac.

                It ships with macOS at /System/Library/CoreServices/Shortcuts Events.app,
                so this is unusual and there is nothing to enable — the automation route
                this server needs does not exist on this machine.
                """

        case .automationDenied:
            return """
                No permission to control Shortcuts: it is denied.

                Grant it in:
                  System Settings → Privacy & Security → Automation → apple-shortcuts-mcp →
                  enable "Shortcuts Events"
                  (Spanish UI: Ajustes del Sistema → Privacidad y seguridad → Automatización)

                Then restart Claude Desktop: the permission is resolved when the process
                starts.

                If no "apple-shortcuts-mcp" entry appears there at all, macOS never asked.
                Check that the binary still carries its embedded Info.plist:
                  otool -P .build/release/apple-shortcuts-mcp | grep NSAppleEvents
                """

        case .consentNotGranted:
            return """
                Permission to control Shortcuts is not settled yet.

                Two things look identical from here: macOS has never asked, or Shortcuts
                Events is simply not running and so cannot be asked about. Either way the
                first real Apple event settles it — call shortcuts_list and answer the
                dialog if one appears. Nothing is run by that call; it reads the library
                and nothing else.
                """
        }
    }
}
