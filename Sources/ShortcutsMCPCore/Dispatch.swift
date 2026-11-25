import Foundation

/// Routes a `tools/call` to the store and renders the answer.
///
/// Never sends an Apple event — everything goes through `ShortcutsStore`, which is what
/// lets the tests drive every branch below against an in-memory double with nothing run
/// and nothing in the owner's library touched.
///
/// This is also where a `name` or `id` argument resolves to one shortcut. A store
/// implementation only walks the whole library; matching a name, picking between two
/// shortcuts that share one, and running by id are answered once, here.
public struct ShortcutsTools: ToolHandler {
    private let store: any ShortcutsStore
    private let configuration: Configuration
    private let format: Format
    private let timeout: Duration

    /// How long any call may take before it is abandoned. It is longer than a read of the
    /// library (`Configuration.scanBudgetSeconds`) plus a run's own wait
    /// (`Configuration.timeoutRange`), so that the more specific report of either wins, and
    /// it is inside `ToolStandard.timeLimit`.
    public static let defaultTimeout = Duration.seconds(120)

    public init(
        store: any ShortcutsStore, configuration: Configuration = Configuration(),
        timeout: Duration = ShortcutsTools.defaultTimeout
    ) {
        self.store = store
        self.configuration = configuration
        self.format = Format()
        self.timeout = timeout
    }

    public func handle(_ parameters: ToolCall) async -> ToolOutput {
        let started = ContinuousClock.now
        let outcome = await Deadline.run(within: timeout) {
            do {
                return Result<String, any Error>.success(try await run(parameters))
            } catch {
                return .failure(error)
            }
        }
        switch outcome {
        case .success(let text)?:
            Diagnostics.toolSucceeded(parameters.name, since: started)
            return ToolOutput(text: text, isError: false)
        case .failure(let error)?:
            return failure(error, tool: parameters.name, since: started)
        case nil:
            return failure(
                ToolError.callTimedOut(
                    seconds: Int(timeout.components.seconds), tool: parameters.name),
                tool: parameters.name, since: started)
        }
    }

    private func failure(
        _ error: any Error, tool: String, since started: ContinuousClock.Instant
    ) -> ToolOutput {
        Diagnostics.toolFailed(tool, error: error, since: started)
        let known = error as? ToolError ?? .storeFailure(error.localizedDescription)
        return ToolOutput(text: known.message, isError: true)
    }

    private func run(_ parameters: ToolCall) async throws -> String {
        let arguments = Arguments(parameters.arguments)

        // Checked before access is asked for, so a mistyped name never raises the consent
        // dialog.
        guard let tool = ToolCatalog.all(configuration).first(where: { $0.name == parameters.name })
        else { throw ToolError.unknownTool(parameters.name) }
        // An argument the tool does not take is refused, not ignored: a call that still
        // uses a name from an earlier version would otherwise run without it.
        let taken = (tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:]).keys.sorted()
        if let stray = (parameters.arguments ?? [:]).keys.sorted().first(where: { !taken.contains($0) }) {
            throw ToolError.unknownArgument(name: stray, tool: tool.name, taken: taken)
        }

        if parameters.name == ToolCatalog.statusName {
            return format.status(
                store.availability(), binaryPath: Self.binaryPath, configuration: configuration)
        }

        try requireAvailable()

        switch parameters.name {
        case ToolCatalog.listName:
            return try await list(arguments)

        case ToolCatalog.getName:
            return try await get(arguments)

        case ToolCatalog.runName:
            return try await runShortcut(arguments)

        default:
            throw ToolError.unknownTool(parameters.name)
        }
    }

    private func requireAvailable() throws {
        let state = store.availability()
        guard !state.blocksCalls else { throw ToolError.notAvailable(state) }
    }

    private func library() async throws -> [ShortcutRecord] {
        try await store.shortcuts(timeBudgetSeconds: Configuration.scanBudgetSeconds)
    }

    // MARK: Tools

    private func list(_ arguments: Arguments) async throws -> String {
        let folder = try arguments.optionalString("folder")
        let needle = try arguments.optionalString("query")
        let (limit, offset) = try arguments.page(
            defaultLimit: Configuration.defaultListLimit, limits: Configuration.listLimitRange)

        var matches = try await library()
        if let folder {
            matches = matches.filter {
                $0.folder?.localizedCaseInsensitiveCompare(folder) == .orderedSame
            }
        }
        if let needle {
            matches = matches.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                    || ($0.subtitle ?? "").localizedCaseInsensitiveContains(needle)
            }
        }
        // Name, then id: ids are unique, so no two rows tie and a page never repeats or
        // skips a row between calls.
        matches.sort {
            switch $0.name.localizedCaseInsensitiveCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.id < $1.id
            }
        }

        let filtered = folder != nil || needle != nil
        return ToolStandard.page(
            of: matches, limit: limit, offset: offset, things: "shortcuts",
            notices: arguments.notices
        ) { rows in
            format.shortcutList(rows, total: matches.count, filtered: filtered)
        }
    }

    private func get(_ arguments: Arguments) async throws -> String {
        let (characterOffset, maxCharacters) = try arguments.window()
        let reference = try reference(arguments)
        let record = format.detail(try await resolve(reference))
        return ToolStandard.fitting(maxCharacters) { size in
            let window = ToolStandard.window(
                of: record, characterOffset: characterOffset, maxCharacters: size)
            return ToolStandard.withNotices(
                arguments.notices + [window.notice].compactMap { $0 }, window.text)
        }
    }

    private func runShortcut(_ arguments: Arguments) async throws -> String {
        // Both read before anything is looked up or run, so a refusal never follows an
        // Apple event.
        let input = try arguments.verbatimString("input", limit: Configuration.inputLimit)
        let reference = try reference(arguments)
        let shortcut = try await resolve(reference)
        let result = try await store.run(
            id: shortcut.id, input: input, timeoutSeconds: configuration.timeoutSeconds)
        return format.runResult(
            shortcut, run: result, resultLimit: configuration.resultLimit)
    }

    // MARK: Resolution

    private enum Reference {
        case name(String)
        case id(String)
    }

    /// Reads `name` or `id`. The two are exclusive rather than one falling back to the
    /// other: if they disagree there is no right answer, and picking either would run
    /// something nobody asked for.
    private func reference(_ arguments: Arguments) throws -> Reference {
        switch (try arguments.optionalString("name"), try arguments.optionalString("id")) {
        case (nil, nil): throw ToolError.referenceRequired
        case (.some, .some): throw ToolError.bothNameAndID
        case (.some(let name), nil): return .name(name)
        case (nil, .some(let identifier)): return .id(identifier)
        }
    }

    /// Turns a `name` or `id` into one shortcut, or explains why it cannot.
    private func resolve(_ reference: Reference) async throws -> ShortcutRecord {
        let shortcuts = try await library()
        switch reference {
        case .id(let identifier):
            guard let match = shortcuts.first(where: { $0.id == identifier })
            else { throw ToolError.notFound(reference: identifier) }
            return match

        case .name(let name):
            // Exact first, then ignoring case. A fallback rather than a single
            // case-insensitive pass, so a library holding both "Notes" and "notes" resolves
            // to the one that was actually asked for instead of reporting an ambiguity.
            var matches = shortcuts.filter { $0.name == name }
            if matches.isEmpty {
                matches = shortcuts.filter {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                }
            }

            guard let first = matches.first else { throw ToolError.notFound(reference: name) }
            guard matches.count == 1 else {
                throw ToolError.ambiguousName(name: name, ids: matches.map(\.id))
            }
            return first
        }
    }

    static var binaryPath: String {
        CommandLine.arguments.first.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            ?? "(unknown)"
    }
}
