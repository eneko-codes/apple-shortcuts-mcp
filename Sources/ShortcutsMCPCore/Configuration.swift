import Foundation

/// What is left of the settings the person installing the extension used to be able to
/// change, after the owner's plug-and-play rule removed the shortcut allow-list and the
/// name-prefix scope from the connector's settings entirely: the whole library is now
/// always visible and resolvable, and `run_shortcut`'s only gate is its own permission
/// switch in Claude Desktop, not a name check here.
///
/// These arrive as command-line arguments because that is how a Claude extension passes
/// `user_config`: the manifest substitutes `${user_config.key}` into `mcp_config.args`.
/// Parsing is hand-rolled rather than pulling in an argument-parsing package — the whole
/// surface is two settings, and every dependency in this repo has to earn its place.
public struct Configuration: Sendable, Equatable {
    /// Ceiling on how much of a shortcut's result is returned. A shortcut can output a
    /// whole file's contents, and an unbounded result would land in the conversation.
    public var resultLimit: Int = Configuration.defaultResultLimit

    /// How long to wait for a shortcut before giving up on the reply.
    ///
    /// Not a limit on the shortcut — nothing can stop it once started — but on the wait.
    /// Without one, a shortcut blocked on a dialog or an unreachable device would hang the
    /// server for the rest of the session with no diagnostic at all.
    ///
    /// Kept under the 60 seconds after which MCP clients abandon a request by default.
    /// Past that the client answers "Request timed out" on its own, so the server's report
    /// — that the shortcut may still be running — never reaches anyone.
    public var timeoutSeconds: Int = 50

    /// One sentence for each setting that was moved into its range when the flags were
    /// parsed, so `shortcuts_status` can say which value is in force and not the one that
    /// was asked for.
    public private(set) var adjustments: [String] = []

    public init() {}

    /// The most a result of this tool may carry is half the longest result, which leaves
    /// room for the lines around the output. It is also the most that can still be said
    /// to have been cut, since the rest of an output can never be read again.
    public static let resultLimitRange = 200...(ToolStandard.longestResult / 2)
    public static let defaultResultLimit = 4_000
    public static let timeoutRange = 5...50

    /// Bounds on `shortcuts_list`. Not configurable: a Shortcuts library is small enough
    /// that a fixed ceiling has never needed tuning, and a setting nobody changes is a
    /// setting that only adds a way to get it wrong.
    ///
    /// The maximum is the number of rows that fit `ToolStandard.longestResult` when every
    /// field of every row is as wide as its clip below allows. The default makes an
    /// ordinary page about `ToolStandard.usualPage`. `ShortcutsToolsTests` renders both.
    public static let listLimitRange = 1...100
    public static let defaultListLimit = 40
    public static let offsetRange = 0...10_000

    /// The widest a name, a folder and a subtitle get in a listing row. Each is free text
    /// the owner typed, and a listing row has to stay one line of ordinary width.
    /// `shortcut_get` reads one in full.
    public static let nameWidth = 80
    public static let folderWidth = 40
    public static let subtitleWidth = 120

    /// The window on one shortcut's record. Half the longest result, so that a window of
    /// ordinary text leaves room for the lines around it.
    public static let maxCharactersRange = 1...(ToolStandard.longestResult / 2)
    public static let defaultMaxCharacters = ToolStandard.usualPage
    public static let characterOffsetRange = 0...10_000_000

    /// The longest `input` a run accepts. It is refused when longer, never cut: a shortcut
    /// run on a part of what was meant would do the wrong thing without anyone knowing.
    public static let inputLimit = ToolStandard.longestResult

    /// How long reading the library may take, for one event and for the walk as a whole.
    /// Every shortcut costs several Apple events, so the time grows with the library.
    public static let scanBudgetSeconds = 30

    /// True when an argument is an unsubstituted manifest placeholder.
    ///
    /// Claude Desktop leaves `${user_config.key}` untouched when the person left that
    /// setting empty, so the literal text could otherwise arrive as an argument.
    /// `Int(value)` already rejects a placeholder for the numeric flags below — neither
    /// looks like a number — but checking explicitly keeps that guarantee on record
    /// instead of leaving it as an accident of how `Int` happens to parse.
    static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("${") && trimmed.hasSuffix("}")
    }

    /// Unknown flags are ignored rather than fatal. A server that will not launch is much
    /// harder to diagnose than one running on a default.
    public static func parse(_ arguments: [String]) -> Configuration {
        var configuration = Configuration()
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil

            func clamped(_ range: ClosedRange<Int>, argument: String) -> Int? {
                guard let value, !isPlaceholder(value), let number = Int(value) else {
                    return nil
                }
                return ToolStandard.clamp(
                    number, to: range, argument: argument, notices: &configuration.adjustments)
            }

            switch flag {
            case "--result-limit":
                if let number = clamped(resultLimitRange, argument: flag) {
                    configuration.resultLimit = number
                }
                index += 2

            case "--timeout-seconds":
                if let number = clamped(timeoutRange, argument: flag) {
                    configuration.timeoutSeconds = number
                }
                index += 2

            default:
                index += 1
            }
        }
        return configuration
    }
}
