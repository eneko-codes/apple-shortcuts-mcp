import Foundation

@testable import ShortcutsMCPCore

/// In-memory `ShortcutsStore` for the tests.
///
/// Every fixture here is invented and nothing is ever run. The test suite must never reach
/// the owner's real library: see the hard rule in CLAUDE.md.
final class FakeShortcutsStore: ShortcutsStore, @unchecked Sendable {
    var state: ShortcutsAvailability
    var library: [ShortcutRecord]
    /// What `run` answers with. A closure rather than a value so a test can make one
    /// specific shortcut time out without inventing a second fake.
    var outcome: @Sendable (String) throws -> ShortcutRun
    /// Every run this fake was asked for, which is how a test proves that a refusal
    /// happened *before* anything ran rather than after.
    private(set) var runs: [(id: String, input: String?, timeoutSeconds: Int)] = []

    init(
        state: ShortcutsAvailability = .ready,
        library: [ShortcutRecord] = Fixtures.library,
        outcome: @escaping @Sendable (String) throws -> ShortcutRun = { _ in
            .text("fixture output")
        }
    ) {
        self.state = state
        self.library = library
        self.outcome = outcome
    }

    func availability() -> ShortcutsAvailability { state }

    func shortcuts() async throws -> [ShortcutRecord] { library }

    func run(id: String, input: String?, timeoutSeconds: Int) async throws -> ShortcutRun {
        runs.append((id, input, timeoutSeconds))
        return try outcome(id)
    }
}

enum Fixtures {
    static func shortcut(
        id: String,
        name: String,
        subtitle: String? = nil,
        folder: String? = nil,
        acceptsInput: Bool = false,
        actionCount: Int = 3
    ) -> ShortcutRecord {
        ShortcutRecord(
            id: id, name: name, subtitle: subtitle, folder: folder,
            acceptsInput: acceptsInput, actionCount: actionCount)
    }

    /// A library holding one of every case the tool layer has to tell apart: a mix of
    /// naming styles, a shortcut in a folder and one at the top level, a duplicated name,
    /// and a pair differing only in case.
    static let library: [ShortcutRecord] = [
        shortcut(
            id: "sc-lights", name: "MCP.Lights.On", subtitle: "Living room",
            folder: "Automation", actionCount: 2),
        shortcut(
            id: "sc-weather", name: "MCP.Weather", subtitle: "Today's forecast as JSON",
            folder: "Automation", acceptsInput: true, actionCount: 7),
        shortcut(id: "sc-archive", name: "Archive Downloads", actionCount: 12),
        shortcut(id: "sc-notes-upper", name: "Notes", folder: "Personal", actionCount: 4),
        shortcut(id: "sc-notes-lower", name: "notes", actionCount: 1),
        shortcut(id: "sc-twin-a", name: "Daily Report", folder: "Work", actionCount: 9),
        shortcut(id: "sc-twin-b", name: "Daily Report", folder: "Personal", actionCount: 5),
    ]
}
