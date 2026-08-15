import Foundation

public enum ToolError: Error, Equatable {
    case notAvailable(ShortcutsAvailability)
    case missingArgument(String)
    case badArgument(name: String, reason: String)
    case referenceRequired
    case bothNameAndID
    case notFound(reference: String)
    case ambiguousName(name: String, ids: [String])
    case timedOut(seconds: Int)
    case storeFailure(String)

    public var message: String {
        switch self {
        case .notAvailable(let state):
            return Self.availabilityMessage(state)

        case .missingArgument(let name):
            return "Missing required argument '\(name)'."

        case .badArgument(let name, let reason):
            return "Argument '\(name)' is not valid: \(reason)"

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
                No shortcut matches '\(reference)'.

                Names are matched exactly first, then ignoring case. A shortcut can be
                renamed or deleted from the Shortcuts app at any moment, so call
                shortcuts_list again rather than reusing a name or id from earlier in the
                conversation.
                """

        case .ambiguousName(let name, let ids):
            return """
                More than one shortcut is named '\(name)', so this is not enough to say
                which one to run.

                Matching ids: \(ids.joined(separator: ", "))

                Call again with 'id' instead of 'name'. shortcut_get on each id shows the
                folder and action count, which is usually what tells them apart.
                """

        case .timedOut(let seconds):
            return """
                The shortcut did not finish within \(seconds) seconds, so the wait was
                abandoned.

                IT MAY STILL BE RUNNING. Only the wait was given up, not the shortcut —
                nothing here can stop one once Shortcuts has started it. Check the Shortcuts
                app before running it again, and do not assume it failed.

                A shortcut that regularly needs longer can have the limit raised in Claude
                Desktop → Settings → Extensions. A shortcut that waits for a person to tap
                something will never finish here: Shortcuts Events runs it with no interface
                to tap.
                """

        case .storeFailure(let detail):
            return "Shortcuts returned an error: \(detail)"
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
