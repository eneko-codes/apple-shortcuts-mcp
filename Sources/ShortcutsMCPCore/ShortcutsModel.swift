import Foundation

/// One shortcut, with every field the Shortcuts Events dictionary makes readable.
///
/// There is no separate summary type because there is nothing extra to fetch: the
/// dictionary exposes these six properties and no more. In particular it exposes **no way
/// to read the actions inside a shortcut** — `actionCount` is the only thing said about
/// them — so `shortcut_get` cannot return more than `shortcuts_list` already knows.
public struct ShortcutRecord: Sendable, Equatable {
    /// Stable across renames, which is why `run_shortcut` resolves to one before running.
    public let id: String
    public let name: String
    /// The line Shortcuts shows under the name. Often empty.
    public let subtitle: String?
    /// nil when the shortcut sits at the top level of the library.
    public let folder: String?
    /// Whether the shortcut declares an input. Passing input to one that takes none is
    /// not an error — Shortcuts ignores it — so this is advice, not a gate.
    public let acceptsInput: Bool
    public let actionCount: Int

    public init(
        id: String, name: String, subtitle: String? = nil, folder: String? = nil,
        acceptsInput: Bool = false, actionCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.folder = folder
        self.acceptsInput = acceptsInput
        self.actionCount = actionCount
    }
}

/// What came back from a run.
///
/// A shortcut's result is typed `any` in the dictionary, so three outcomes have to be told
/// apart: it returned nothing, it returned text, or it returned something with no textual
/// form (an image, a file, a media item). Collapsing the last two into an empty string
/// would report a working shortcut as a silent one.
public struct ShortcutRun: Sendable, Equatable {
    public let hasResult: Bool
    public let resultIsText: Bool
    public let result: String

    public init(hasResult: Bool, resultIsText: Bool, result: String) {
        self.hasResult = hasResult
        self.resultIsText = resultIsText
        self.result = result
    }

    public static let empty = ShortcutRun(hasResult: false, resultIsText: false, result: "")

    public static func text(_ value: String) -> ShortcutRun {
        ShortcutRun(hasResult: true, resultIsText: true, result: value)
    }
}
