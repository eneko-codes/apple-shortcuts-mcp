import Foundation
import MCP

/// Routes a `tools/call` to the store and renders the answer.
///
/// Never sends an Apple event — everything goes through `ShortcutsStore`, which is what
/// lets the tests drive every branch below against an in-memory double with nothing run
/// and nothing in the owner's library touched.
///
/// This is also where a `name` or `id` argument resolves to one shortcut. A store
/// implementation only walks the whole library; matching a name, picking between two
/// shortcuts that share one, and running by id are answered once, here.
public struct ShortcutsTools: Sendable {
    private let store: any ShortcutsStore
    private let configuration: Configuration
    private let format: Format

    public init(store: any ShortcutsStore, configuration: Configuration = Configuration()) {
        self.store = store
        self.configuration = configuration
        self.format = Format()
    }

    public func handle(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        do {
            let text = try await run(parameters)
            return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
        } catch let error as ToolError {
            return .init(
                content: [.text(text: error.message, annotations: nil, _meta: nil)], isError: true)
        } catch {
            return .init(
                content: [
                    .text(
                        text: ToolError.storeFailure(error.localizedDescription).message,
                        annotations: nil, _meta: nil)
                ], isError: true)
        }
    }

    private func run(_ parameters: CallTool.Parameters) async throws -> String {
        let arguments = Arguments(parameters.arguments)

        if parameters.name == ToolCatalog.statusName {
            return format.status(
                store.availability(), binaryPath: Self.binaryPath, configuration: configuration)
        }

        try requireAvailable()

        switch parameters.name {
        case ToolCatalog.listName:
            return try await list(arguments)

        case ToolCatalog.getName:
            return format.detail(try await resolve(arguments))

        case ToolCatalog.runName:
            return try await runShortcut(arguments)

        default:
            throw ToolError.badArgument(
                name: "name", reason: "'\(parameters.name)' is not a tool of this server")
        }
    }

    private func requireAvailable() throws {
        let state = store.availability()
        guard !state.blocksCalls else { throw ToolError.notAvailable(state) }
    }

    // MARK: Tools

    private func list(_ arguments: Arguments) async throws -> String {
        var matches = try await store.shortcuts()

        if let folder = arguments.optionalString("folder") {
            matches = matches.filter {
                $0.folder?.localizedCaseInsensitiveCompare(folder) == .orderedSame
            }
        }
        if let needle = arguments.optionalString("query") {
            matches = matches.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                    || ($0.subtitle ?? "").localizedCaseInsensitiveContains(needle)
            }
        }
        matches.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let limit = try arguments.int(
            "limit", default: Configuration.defaultListLimit, in: Configuration.listLimitRange)
        let offset = try arguments.int("offset", default: 0, in: Configuration.offsetRange)
        let page = Array(matches.dropFirst(offset).prefix(limit))

        return format.shortcutList(page, total: matches.count, offset: offset)
    }

    private func runShortcut(_ arguments: Arguments) async throws -> String {
        let shortcut = try await resolve(arguments)
        let result = try await store.run(
            id: shortcut.id,
            input: arguments.verbatimString("input"),
            timeoutSeconds: configuration.timeoutSeconds)
        return format.runResult(
            shortcut, run: result, resultLimit: configuration.resultLimit)
    }

    // MARK: Resolution

    /// Turns a `name` or `id` argument into one shortcut, or explains why it cannot.
    ///
    /// The two are exclusive rather than one falling back to the other: if they disagree
    /// there is no right answer, and picking either would run something nobody asked for.
    private func resolve(_ arguments: Arguments) async throws -> ShortcutRecord {
        let name = arguments.optionalString("name")
        let identifier = arguments.optionalString("id")

        switch (name, identifier) {
        case (nil, nil): throw ToolError.referenceRequired
        case (.some, .some): throw ToolError.bothNameAndID

        case (nil, .some(let identifier)):
            guard let match = try await store.shortcuts().first(where: { $0.id == identifier })
            else { throw ToolError.notFound(reference: identifier) }
            return match

        case (.some(let name), nil):
            let library = try await store.shortcuts()
            // Exact first, then ignoring case. A fallback rather than a single
            // case-insensitive pass, so a library holding both "Notes" and "notes" resolves
            // to the one that was actually asked for instead of reporting an ambiguity.
            var matches = library.filter { $0.name == name }
            if matches.isEmpty {
                matches = library.filter {
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
