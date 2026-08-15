import Foundation
import MCP

/// The catalogue is the authorisation surface: a tool that is not listed here cannot be
/// called, and the name it is listed under is the label on the permission switch in Claude
/// Desktop. Reads carry no verb prefix; the one tool that acts starts with a verb, so it
/// cannot be mistaken for one of them at a glance.
public enum ToolCatalog {

    /// Names are constants rather than being read back off a `Tool`, because a tool whose
    /// schema depends on the configuration has to be built as a function and its name
    /// would then have nowhere stable to live.
    public static let statusName = "shortcuts_status"
    public static let listName = "shortcuts_list"
    public static let getName = "shortcut_get"
    public static let runName = "run_shortcut"

    /// Built from the live configuration so a description never states a limit the running
    /// server does not actually enforce.
    public static func all(_ configuration: Configuration = Configuration()) -> [Tool] {
        [status, list, get, run(configuration)]
    }

    // MARK: Schema helpers

    private static func object(properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        schema["additionalProperties"] = .bool(false)
        return .object(schema)
    }

    /// `type` is always the single string `"string"`, never `["string", "null"]`. Claude
    /// Desktop's schema sanitiser drops a property outright when its `type` is a union and
    /// hands the model a bare `{}` in its place, which makes the argument unusable. An
    /// optional field is expressed by leaving it out of `required` and nothing else.
    private static func string(_ description: String) -> Value {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func integer(_ description: String, minimum: Int, maximum: Int, default def: Int)
        -> Value
    {
        .object([
            "type": .string("integer"), "description": .string(description),
            "minimum": .int(minimum), "maximum": .int(maximum), "default": .int(def),
        ])
    }

    private static let referenceHelp = """
        Give either 'name' or 'id', not both. Both come from shortcuts_list; 'id' is the \
        safer one, because a shortcut keeps it when it is renamed.
        """

    private static let nameProperty = string(
        "Exact name of the shortcut, as shortcuts_list shows it. Matched exactly first, "
            + "then ignoring case.")

    private static let idProperty = string(
        "Identifier returned by shortcuts_list. Survives a rename; a name does not.")

    // MARK: Reads

    static let status = Tool(
        name: statusName,
        title: "Shortcuts permission status",
        description: """
            Reports whether this server may control Shortcuts. Says exactly what to enable \
            and where if permission is missing.

            Reads no shortcuts and runs nothing — it asks macOS about the permission \
            without sending an Apple event, so it answers even when access is denied.

            Use it when another tool fails on permissions, or when setting the server up.
            """,
        inputSchema: object(properties: [:]),
        annotations: .init(
            readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    )

    static let list = Tool(
        name: listName,
        title: "List shortcuts",
        description: """
            Lists the shortcuts this server can see, with their folder, whether they take \
            input, and how many actions each contains. Folders are named in the header, \
            since they are the only grouping the library has.

            Shows the whole Shortcuts library — there is no separate allow-list or name \
            filter here. What run_shortcut may actually run is decided by its own \
            permission switch in Claude Desktop, not by anything this tool withholds.

            This is the only source of names and ids. Call it before shortcut_get or \
            run_shortcut rather than reusing either from earlier in the conversation — the \
            library changes whenever the owner edits it.
            """,
        inputSchema: object(properties: [
            "query": string(
                "Optional text to match against the name and subtitle, ignoring case."),
            "folder": string(
                "Optional folder name. Only shortcuts in that folder are returned."),
            "limit": integer(
                "Maximum number of shortcuts to return.",
                minimum: Configuration.listLimitRange.lowerBound,
                maximum: Configuration.listLimitRange.upperBound,
                default: Configuration.defaultListLimit),
            "offset": integer(
                "Skip this many matches; use it to page.",
                minimum: Configuration.offsetRange.lowerBound,
                maximum: Configuration.offsetRange.upperBound, default: 0),
        ]),
        annotations: .init(
            readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    )

    static let get = Tool(
        name: getName,
        title: "Full shortcut record",
        description: """
            Returns everything stored about one shortcut: name, id, subtitle, folder, \
            whether it accepts input, and how many actions it has.

            It CANNOT show what the shortcut does. macOS exposes no API for reading the \
            actions inside a shortcut — not Shortcuts Events, not the command line, not \
            any framework — so the action count is all there is. To know what one does, \
            open it in the Shortcuts app.

            \(referenceHelp)
            """,
        inputSchema: object(properties: [
            "name": nameProperty,
            "id": idProperty,
        ]),
        annotations: .init(
            readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    )

    // MARK: The one tool that acts

    static func run(_ configuration: Configuration) -> Tool {
        Tool(
            name: runName,
            title: "Run a shortcut",
            description: """
                Runs one shortcut through Shortcuts Events — in the background, without \
                opening the Shortcuts app — and returns whatever it outputs.

                THIS SERVER CANNOT KNOW WHAT A SHORTCUT DOES and cannot undo it. A shortcut \
                is a program the owner wrote; it may send messages, change files, or \
                control devices. The whole library can be run — there is no name allow-list \
                — so this tool's own permission switch in Claude Desktop is the only \
                boundary. Say what you are about to run and why before running it.

                Gives up waiting after \(configuration.timeoutSeconds) seconds. The shortcut \
                is not stopped by that: nothing here can stop one once it has started. A \
                shortcut that waits for someone to tap something will never finish, because \
                it runs with no interface.

                Output is returned as text and cut off at \(configuration.resultLimit) \
                characters. A shortcut whose result is an image or a file reports that it \
                produced one rather than its contents.

                \(referenceHelp)
                """,
            inputSchema: object(properties: [
                "name": nameProperty,
                "id": idProperty,
                "input": string(
                    """
                    Optional text passed to the shortcut as its input. Only text: a file or \
                    an image cannot be sent from here. A shortcut that takes no input \
                    ignores it.
                    """),
            ]),
            annotations: .init(
                readOnlyHint: false,
                // Honest rather than reassuring. The server has no way to tell a shortcut
                // that turns on a lamp from one that empties a folder.
                destructiveHint: true,
                idempotentHint: false,
                // A shortcut can reach anything on the machine and anything off it.
                openWorldHint: true)
        )
    }
}
