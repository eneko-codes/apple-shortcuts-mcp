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
    public var resultLimit: Int = 4_000

    /// How long to wait for a shortcut before giving up on the reply.
    ///
    /// Not a limit on the shortcut — nothing can stop it once started — but on the wait.
    /// Without one, a shortcut blocked on a dialog or an unreachable device would hang the
    /// server for the rest of the session with no diagnostic at all.
    public var timeoutSeconds: Int = 120

    public init() {}

    public static let resultLimitRange = 200...100_000
    public static let timeoutRange = 5...600

    /// Bounds on `shortcuts_list`. Not configurable: a Shortcuts library is small enough
    /// that a fixed ceiling has never needed tuning, and a setting nobody changes is a
    /// setting that only adds a way to get it wrong.
    public static let listLimitRange = 1...500
    public static let defaultListLimit = 100
    public static let offsetRange = 0...10_000

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

            func clamped(_ range: ClosedRange<Int>) -> Int? {
                guard let value, !isPlaceholder(value), let number = Int(value) else {
                    return nil
                }
                return min(max(number, range.lowerBound), range.upperBound)
            }

            switch flag {
            case "--result-limit":
                if let number = clamped(resultLimitRange) { configuration.resultLimit = number }
                index += 2

            case "--timeout-seconds":
                if let number = clamped(timeoutRange) { configuration.timeoutSeconds = number }
                index += 2

            default:
                index += 1
            }
        }
        return configuration
    }
}
