import Foundation
import MCP

/// Typed access to a `tools/call` argument bag.
///
/// Smaller than its siblings because nothing here is editable: no field is ever cleared,
/// so an absent key and an explicit `null` mean the same thing and there is no `FieldEdit`
/// to decode.
public struct Arguments {
    private let values: [String: Value]

    public init(_ values: [String: Value]?) {
        self.values = values ?? [:]
    }

    public func requiredString(_ name: String) throws -> String {
        guard let raw = values[name]?.stringValue else { throw ToolError.missingArgument(name) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.badArgument(name: name, reason: "it is empty")
        }
        return trimmed
    }

    public func optionalString(_ name: String) -> String? {
        guard let text = values[name]?.stringValue else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A shortcut's input, kept exactly as it was given.
    ///
    /// Not trimmed and not dropped when blank, unlike every other string here: leading
    /// whitespace can be meaningful to whatever the shortcut does with it, and " " is a
    /// legitimate thing to pass. Only a missing key means "no input".
    public func verbatimString(_ name: String) -> String? {
        values[name]?.stringValue
    }

    /// Clamps rather than rejects: a model asking for 500 results means "as many as you
    /// will give me".
    public func int(_ name: String, default fallback: Int, in range: ClosedRange<Int>) throws
        -> Int
    {
        guard let raw = values[name] else { return fallback }
        guard let number = raw.intValue else {
            throw ToolError.badArgument(name: name, reason: "an integer was expected")
        }
        return Swift.min(Swift.max(number, range.lowerBound), range.upperBound)
    }
}
