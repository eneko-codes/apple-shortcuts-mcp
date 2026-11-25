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

    static func actionCount(_ count: Int) -> String {
        count == 1 ? "1 action" : "\(count) actions"
    }

    /// The subtitle, unless it only restates the action count.
    ///
    /// Shortcuts Events reports "39 actions" as the subtitle of a shortcut that has none of
    /// its own. It is matched as the count followed by a single word rather than as English
    /// text, because the word is the system's and follows its language.
    static func subtitle(of shortcut: ShortcutRecord) -> String? {
        guard let subtitle = shortcut.subtitle else { return nil }
        let words = subtitle.split(whereSeparator: \.isWhitespace)
        let restatesCount = words.count == 2 && Int(words[0]) == shortcut.actionCount
        return restatesCount ? nil : subtitle
    }

    // MARK: Tools

    /// `text` as one line of a listing row: at most `width` characters, the last of them
    /// an ellipsis when it was cut. `clipped` is set when it was.
    static func clip(_ text: String, to width: Int, clipped: inout Bool) -> String {
        guard text.count > width else { return text }
        clipped = true
        return String(text.prefix(width - 1)) + "…"
    }

    /// The rows of one page of a listing, with the sentences about what the rows had to
    /// lose first. `total` is the number of shortcuts that matched, not the page.
    ///
    /// Name, folder and subtitle are free text and are clipped to a width in every row;
    /// the id is never clipped, because a clipped id names nothing.
    public func shortcutList(_ page: [ShortcutRecord], total: Int, filtered: Bool) -> String {
        var nameClipped = false
        var folderClipped = false
        var subtitleClipped = false
        func name(_ shortcut: ShortcutRecord) -> String {
            Self.clip(Self.oneLine(shortcut.name), to: Configuration.nameWidth, clipped: &nameClipped)
        }
        func folder(_ shortcut: ShortcutRecord) -> String? {
            shortcut.folder.map {
                Self.clip(Self.oneLine($0), to: Configuration.folderWidth, clipped: &folderClipped)
            }
        }

        let rows = page.map { (shortcut: $0, name: name($0), folder: folder($0)) }

        // Folders are the library's only grouping, so they are named even when the page
        // itself is empty: a caller cannot bound a search by something it cannot see.
        let folders = Set(rows.compactMap(\.folder)).sorted()
        var header = "\(total) shortcut\(total == 1 ? "" : "s"), ordered by name (ignoring case), then id."
        if !folders.isEmpty {
            header += "\nFolders on this page: " + folders.joined(separator: ", ")
        }

        var lines = [header]
        if rows.isEmpty {
            if total == 0 {
                lines.append(
                    filtered
                        ? "Nothing matched. Call again without 'query' or 'folder' to see the whole library."
                        : "The library holds no shortcuts.")
            }
            return lines.joined(separator: "\n")
        }

        let nameWidth = rows.map(\.name.count).max() ?? 0
        let folderWidth = rows.compactMap(\.folder).map(\.count).max() ?? 0
        var notices: [String] = []
        for row in rows {
            var line = Self.pad(row.name, to: nameWidth)
            if folderWidth > 0 {
                line += "  " + Self.pad(row.folder ?? "—", to: folderWidth)
            }
            line += "  " + Self.pad(Self.actionCount(row.shortcut.actionCount), to: 12)
            line += row.shortcut.acceptsInput ? "  takes input" : "             "
            if let subtitle = Self.subtitle(of: row.shortcut), !subtitle.isEmpty {
                line += "  " + Self.clip(
                    Self.oneLine(subtitle), to: Configuration.subtitleWidth, clipped: &subtitleClipped)
            }
            lines.append(line + "  id=\(row.shortcut.id)")
        }
        // Said once per field, and only when a row on this page was in fact clipped.
        if nameClipped {
            notices.append(
                Notice.clipped(field: "Name", width: Configuration.nameWidth, tool: ToolCatalog.getName))
        }
        if folderClipped {
            notices.append(
                Notice.clipped(field: "Folder", width: Configuration.folderWidth, tool: ToolCatalog.getName))
        }
        if subtitleClipped {
            notices.append(
                Notice.clipped(field: "Subtitle", width: Configuration.subtitleWidth, tool: ToolCatalog.getName))
        }
        return ToolStandard.withNotices(notices, lines.joined(separator: "\n"))
    }

    /// One shortcut's record, whole. The caller windows it.
    public func detail(_ shortcut: ShortcutRecord) -> String {
        let rows: [(String, String?)] = [
            ("folder", shortcut.folder ?? "(top level)"),
            ("subtitle", Self.subtitle(of: shortcut)),
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

    /// The sentence for output that was cut and can never be read again, because asking
    /// again would run the shortcut again. `Notice` has no form for this yet; this is its
    /// fixed wording, to be replaced by one.
    static func unrepeatableCut(limit: Int, total: Int) -> String {
        "Cut at \(limit) of \(total) characters; the rest cannot be read again."
    }

    /// A run has to say what happened even when nothing came back, because "no output" and
    /// "output this server could not render" and "it failed" are three different facts and
    /// only the first two reach here.
    public func runResult(_ shortcut: ShortcutRecord, run: ShortcutRun, resultLimit: Int)
        -> String
    {
        let title = "Ran '\(ToolStandard.echo(shortcut.name))'.\n"

        guard run.hasResult else {
            return title + "\nIt completed and returned no output."
        }
        guard run.resultIsText else {
            return title
                + """

                It completed and returned a value with no textual form — an image, a file or
                a media item. Apple events can carry it, but not into a conversation. Have
                the shortcut end with a text or JSON output if the contents are what matter.
                """
        }

        // Rendered through `fitting`: an output of characters that take several UTF-16
        // units each can still be too long at the configured limit.
        let total = run.result.count
        return ToolStandard.fitting(resultLimit) { size in
            guard total > size else { return title + "\nOutput:\n" + run.result }
            return ToolStandard.withNotices(
                [Self.unrepeatableCut(limit: size, total: total)],
                title + "\nOutput:\n" + String(run.result.prefix(size)))
        }
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

        var text = ToolStandard.withNotices(configuration.adjustments, headline + "\n\n")
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
