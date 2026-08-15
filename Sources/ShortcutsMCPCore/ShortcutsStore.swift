import Foundation

/// Whether Shortcuts can be driven at all, and if not, why.
///
/// There is no `authorizationStatus` for Apple events the way there is for Contacts or
/// EventKit, so this collapses several distinct causes into one value the tools can act
/// on.
///
/// Note what is missing: there is no `.notRunning`. Shortcuts Events is a faceless helper
/// with no windows and no state, launched on demand precisely so a shortcut can run
/// without the Shortcuts app opening. Refusing to start it — the rule the sibling mail
/// server holds for Mail.app — would mean refusing to work at all.
public enum ShortcutsAvailability: Sendable, Equatable {
    case ready
    /// Shortcuts Events ships with macOS, so this means the install is unusual rather
    /// than that anything can be enabled.
    case notInstalled
    case automationDenied
    /// macOS has not asked yet. The first real Apple event raises the dialog.
    case consentNotGranted

    /// Whether a tool call must be refused outright.
    ///
    /// `.consentNotGranted` deliberately does **not** block, which is why "may a call
    /// proceed" is a different question from "is Shortcuts ready". macOS only shows the
    /// Automation dialog when a real Apple event is sent, so refusing here would mean the
    /// dialog never appears and the permission could never be granted at all. If consent
    /// is then refused, the event fails and the error path reports it.
    public var blocksCalls: Bool {
        switch self {
        case .ready, .consentNotGranted: return false
        case .notInstalled, .automationDenied: return true
        }
    }
}

/// The seam between the tool layer and Shortcuts.
///
/// Nothing above this protocol sends an Apple event, which is what lets the tests drive
/// every branch against an in-memory double — with nothing run and nothing in the owner's
/// library touched. Everything that decides *what may happen* — how a name resolves to an
/// id, where a result is cut — lives above it.
public protocol ShortcutsStore: Sendable {
    func availability() -> ShortcutsAvailability

    /// The whole library, unfiltered.
    ///
    /// There is nothing to push a filter into even if a store wanted to: the dictionary
    /// offers elements and properties, and no query language at all. Narrowing by `query`
    /// or `folder` happens in the tool layer, once, against what this returns.
    func shortcuts() async throws -> [ShortcutRecord]

    /// Runs one shortcut, addressed by id.
    ///
    /// By id rather than by name because a name can change between the moment a caller
    /// read it and the moment this runs, and because two shortcuts may carry the same one.
    ///
    /// `timeoutSeconds` is passed per call rather than held by the store so that the value
    /// enforced here and the value `shortcuts_status` reports cannot be two different
    /// numbers.
    ///
    /// Irreversible in the general case: nothing here can know what the shortcut does.
    func run(id: String, input: String?, timeoutSeconds: Int) async throws -> ShortcutRun
}
