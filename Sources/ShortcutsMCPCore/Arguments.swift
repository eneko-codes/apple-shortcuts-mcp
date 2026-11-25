import Foundation

/// Typed access to a `tools/call` argument bag.
///
/// A class, not a struct, so that reading a number can also record that it was moved into
/// its range without every reader having to be `mutating`. One instance serves one call and
/// never leaves it. The tool puts `notices` before the data.
///
/// Smaller than its siblings because nothing here is editable: no field is ever cleared,
/// so an absent key and an explicit `null` mean the same and there is no `FieldEdit` to
/// decode.
public final class Arguments {
    private let values: [String: Value]

    /// One sentence for each number that was moved into its range, in the order read.
    public private(set) var notices: [String] = []

    public init(_ values: [String: Value]?) {
        self.values = values ?? [:]
    }

    /// `nil` when the argument is absent or null, which mean the same: not given.
    private func given(_ name: String) -> Value? {
        guard let raw = values[name], !raw.isNull else { return nil }
        return raw
    }

    /// Text, trimmed; blank text is not given. `nil` when not given.
    public func optionalString(_ name: String) throws -> String? {
        guard let raw = given(name) else { return nil }
        guard let text = raw.stringValue else {
            throw ToolError.badArgument(name: name, reason: "text was expected")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A shortcut's input, kept exactly as it was given.
    ///
    /// Not trimmed and not dropped when blank, unlike every other string here: leading
    /// whitespace can be meaningful to whatever the shortcut does with it, and " " is a
    /// legitimate thing to pass. Only a missing key means "no input".
    ///
    /// Longer than `limit` is refused, never cut: a shortcut run on a part of what was
    /// meant would do the wrong thing, and nothing would say so.
    public func verbatimString(_ name: String, limit: Int) throws -> String? {
        guard let raw = given(name) else { return nil }
        guard let text = raw.stringValue else {
            throw ToolError.badArgument(name: name, reason: "text was expected")
        }
        // Code points, as the schema's `maxLength` counts them, so the two never disagree.
        let length = text.unicodeScalars.count
        guard length <= limit else {
            throw ToolError.inputTooLong(characters: length, limit: limit)
        }
        return text
    }

    /// A quantity: a size, a count or an offset. Outside its range it is moved to the
    /// nearest allowed value, and `notices` gains the sentence that says which value was
    /// used. This server takes no identifier that is a number: ids are text.
    public func int(_ name: String, default fallback: Int, in range: ClosedRange<Int>) throws
        -> Int
    {
        guard let raw = given(name) else { return fallback }
        guard let number = raw.intValue else {
            throw ToolError.badArgument(name: name, reason: "a whole number was expected")
        }
        return ToolStandard.clamp(number, to: range, argument: name, notices: &notices)
    }

    /// The `limit` and `offset` of a listing, read the same way by every tool that pages.
    public func page(defaultLimit: Int, limits: ClosedRange<Int>) throws -> (limit: Int, offset: Int) {
        (
            try int("limit", default: defaultLimit, in: limits),
            try int("offset", default: 0, in: Configuration.offsetRange)
        )
    }

    /// The `character_offset` and `max_characters` of a window on one long text.
    public func window() throws -> (characterOffset: Int, maxCharacters: Int) {
        (
            try int("character_offset", default: 0, in: Configuration.characterOffsetRange),
            try int(
                "max_characters", default: Configuration.defaultMaxCharacters,
                in: Configuration.maxCharactersRange)
        )
    }
}
