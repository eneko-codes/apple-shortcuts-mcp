import Foundation

/// Plain-text rendering of every tool result.
public struct Format: Sendable {

    public init() {}

    // MARK: Helpers

    static func pad(_ text: String, to width: Int) -> String {
        let shortfall = width - text.count
        return shortfall > 0 ? text + String(repeating: " ", count: shortfall) : text
    }

    static func block(_ rows: [(String, String?)]) -> String {
        let present = rows.compactMap { label, value -> (String, String)? in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return (label, value)
        }
        guard let width = present.map(\.0.count).max() else { return "" }
        let indent = String(repeating: " ", count: width + 3)
        return present.map { label, value in
            let wrapped = value.split(separator: "\n", omittingEmptySubsequences: false)
                .joined(separator: "\n" + indent)
            return "  \(pad(label, to: width)) \(wrapped)"
        }.joined(separator: "\n")
    }

    /// Collapses a multi-line value onto one line.
    ///
    /// A subtitle is free text and can contain newlines, which would otherwise break the
    /// one-line-per-result contract that makes a listing scannable.
    static func oneLine(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    // MARK: Tools

    public func shortcutList(_ page: [ShortcutRecord], total: Int, offset: Int) -> String {
        // Folders are the library's only grouping, so they are named even when the page
        // itself is empty: a caller cannot bound a search by something it cannot see.
        let folders = Set(page.compactMap(\.folder)).sorted()
        var header = "\(total) shortcut\(total == 1 ? "" : "s")"
        if !folders.isEmpty {
            header += "\nFolders on this page: " + folders.joined(separator: ", ")
        }

        guard !page.isEmpty else {
            return header
                + "\nNothing matched. Call again without 'query' or 'folder' to see the whole library."
        }

        let nameWidth = page.map(\.name.count).max() ?? 0
        let folderWidth = page.compactMap(\.folder).map(\.count).max() ?? 0

        var lines = [header]
        for shortcut in page {
            var line = Self.pad(shortcut.name, to: nameWidth)
            if folderWidth > 0 {
                line += "  " + Self.pad(shortcut.folder ?? "—", to: folderWidth)
            }
            line += "  " + Self.pad("\(shortcut.actionCount) actions", to: 12)
            line += shortcut.acceptsInput ? "  takes input" : "             "
            if let subtitle = shortcut.subtitle, !subtitle.isEmpty {
                line += "  " + Self.oneLine(subtitle)
            }
            lines.append(line + "  id=\(shortcut.id)")
        }

        let shown = offset + page.count
        if shown < total {
            lines.append("…\(total - shown) more · call again with offset=\(shown)")
        }
        return lines.joined(separator: "\n")
    }

    public func detail(_ shortcut: ShortcutRecord) -> String {
        let rows: [(String, String?)] = [
            ("folder", shortcut.folder ?? "(top level)"),
            ("subtitle", shortcut.subtitle),
            ("input", shortcut.acceptsInput ? "accepts input" : "takes no input"),
            ("actions", "\(shortcut.actionCount)"),
            ("id", shortcut.id),
        ]
        // Said on every record rather than only when it comes up, because the absence of
        // an action list reads like a gap in this server otherwise.
        let ceiling = """

            What the actions are cannot be read: macOS exposes no API for the contents of a
            shortcut. Open it in the Shortcuts app to see what it does.
            """
        return shortcut.name + "\n" + Self.block(rows) + "\n" + ceiling
    }

    /// A run has to say what happened even when nothing came back, because "no output" and
    /// "output this server could not render" and "it failed" are three different facts and
    /// only the first two reach here.
    public func runResult(_ shortcut: ShortcutRecord, run: ShortcutRun, resultLimit: Int)
        -> String
    {
        var text = "Ran '\(shortcut.name)'.\n"

        guard run.hasResult else {
            return text + "\nIt completed and returned no output."
        }
        guard run.resultIsText else {
            return text
                + """

                It completed and returned a value with no textual form — an image, a file or
                a media item. Apple events can carry it, but not into a conversation. Have
                the shortcut end with a text or JSON output if the contents are what matter.
                """
        }

        let truncated = run.result.count > resultLimit
        let body = truncated ? String(run.result.prefix(resultLimit)) : run.result
        text += "\nOutput:\n" + body
        if truncated {
            text += """


                …cut off at \(resultLimit) characters of \(run.result.count). The rest was
                not returned; narrow what the shortcut outputs, or raise the limit in Claude
                Desktop → Settings → Extensions.
                """
        }
        return text
    }

    public func status(
        _ availability: ShortcutsAvailability, binaryPath: String, configuration: Configuration
    ) -> String {
        let headline: String
        switch availability {
        case .ready: headline = "Shortcuts automation: GRANTED."
        case .notInstalled: headline = "Shortcuts automation: UNAVAILABLE — no Shortcuts Events."
        case .automationDenied: headline = "Shortcuts automation: DENIED."
        case .consentNotGranted: headline = "Shortcuts automation: not settled yet."
        }

        var text = headline + "\n\n"
        // The effective configuration, because a setting that silently failed to reach the
        // process is otherwise invisible: an unsubstituted manifest placeholder once became
        // the only allowed calendar in a sibling server, which hid every real one.
        text += Self.block([
            ("binary", binaryPath),
            ("target", "Shortcuts Events (com.apple.shortcuts.events)"),
            ("process", "pid \(ProcessInfo.processInfo.processIdentifier)"),
            ("shortcuts visible", "the whole library — gated only by run_shortcut's own permission switch in Claude Desktop"),
            ("run timeout", "\(configuration.timeoutSeconds) s"),
            ("result limit", "\(configuration.resultLimit) characters"),
        ])
        if availability != .ready {
            text += "\n\n" + ToolError.availabilityMessage(availability)
        }
        return text
    }
}
