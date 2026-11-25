import Foundation

public enum ShortcutsMCPServer {

    public static let name = "apple-shortcuts-mcp"
    public static let version = "1.1.0"

    /// Returned from `initialize`. It carries what per-tool descriptions cannot state
    /// once: the workflow, the two things this server genuinely cannot do, and where
    /// policy actually lives.
    public static let instructions = """
        Access to the macOS Shortcuts library through Shortcuts Events, the faceless helper \
        that runs a shortcut without opening the Shortcuts app.

        Workflow: shortcuts_list first, then use the name or id it returns. Prefer the id — \
        it survives a rename. The library changes whenever the owner edits it, so look a \
        shortcut up again rather than reusing a name or id from earlier in the conversation.

        LISTS COME IN PAGES. shortcuts_list returns \(Configuration.defaultListLimit) \
        shortcuts to a page, at most \(Configuration.listLimitRange.upperBound), ordered by \
        name and then id. When shortcuts exist that a result does not hold, its first lines \
        say how many there are and the offset of the next page: pass limit and offset. Names, \
        folders and subtitles are clipped in a row, and the result says so; shortcut_get reads \
        one in full, in windows of character_offset and max_characters when it is long. A \
        size or a count outside its range is moved to the nearest allowed value, and the \
        first lines say which one was used.

        EVERY CALL IS BOUNDED. A call not finished after \
        \(ShortcutsTools.defaultTimeout.components.seconds) seconds is abandoned and answered \
        with an error. Reading the library gives up after \(Configuration.scanBudgetSeconds) \
        seconds and fails; it never lists part of it.

        THE ACTIONS INSIDE A SHORTCUT CANNOT BE READ. macOS exposes no API for them — not \
        Shortcuts Events, not the command line, not any framework. The action count is all \
        there is. If what a shortcut does matters, say that it has to be opened in the \
        Shortcuts app; do not guess from its name.

        A SHORTCUT CANNOT BE CREATED OR INSTALLED FROM HERE, by this server or by anything \
        else. Generating and signing a .shortcut file works, but there is no supported way \
        to add one to the library: the only route is a person opening the file and choosing \
        Add Shortcut. Say so rather than offering to build one.

        run_shortcut runs a program the owner wrote. This server cannot know what it does, \
        cannot undo it, and cannot stop it once it has started — a shortcut may send \
        messages, change files or control devices. Say what you are about to run and why \
        before running it. A shortcut that waits for someone to tap something will never \
        finish, because it runs with no interface. Its output is returned up to a limit and \
        the rest of a longer one cannot be read again, because asking again runs the \
        shortcut again; its input is refused, not cut, when longer than \
        \(Configuration.inputLimit) characters.

        The whole Shortcuts library is visible and runnable — there is no allow-list or \
        name-prefix scope here any more. What run_shortcut may actually do is controlled \
        only by its own allow/ask/prohibit switch in Claude Desktop.
        """

    /// The store is a parameter so the whole server can be driven by a double. Nothing in
    /// this function sends an Apple event by itself.
    public static func run(
        store: any ShortcutsStore = ScriptingBridgeShortcutsStore(),
        configuration: Configuration = Configuration()
    ) async {
        Diagnostics.started(version: version)
        await serveStandardStreams(
            handler: handler(
                tools: ShortcutsTools(store: store, configuration: configuration),
                configuration: configuration))
    }

    public static func handler(
        tools: ShortcutsTools, configuration: Configuration = Configuration()
    ) -> MCPHandler {
        MCPHandler(
            name: name, version: version, instructions: instructions,
            catalog: ToolCatalog.all(configuration), tools: tools)
    }
}
