import Foundation
import Testing

@testable import ShortcutsMCPCore

/// The edges of the tool standard for this server's tools: each bound and one past it, the
/// text of each notice, pages and windows that chain, the longest result, and the texts the
/// model reads. Every shortcut, folder and output in here is invented, and nothing is run.
@Suite("Bounds")
struct BoundsTests {

    // MARK: An invented library with as many shortcuts as a test asks for

    private static func padded(_ index: Int) -> String { String(format: "%04d", index) }

    /// Ids as the real ones look, so a row is as wide as it gets.
    private static func identifier(_ index: Int) -> String {
        "00000000-0000-4000-8000-" + String(format: "%012d", index)
    }

    /// Shortcuts whose every clipped field is exactly as wide as its width allows, so a
    /// full page is the widest page that is not clipped. The index leads each field so a
    /// test finds one row without walking the filler.
    private static func widest(_ count: Int) -> [ShortcutRecord] {
        func fill(_ lead: String, _ width: Int) -> String {
            lead + String(repeating: "x", count: width - lead.count)
        }
        return (0..<count).map {
            ShortcutRecord(
                id: identifier($0), name: fill("name-\(padded($0))-", Configuration.nameWidth),
                subtitle: fill("sub-\(padded($0))-", Configuration.subtitleWidth),
                folder: fill("folder-", Configuration.folderWidth), acceptsInput: true,
                actionCount: 1_234)
        }
    }

    private static func store(_ count: Int) -> FakeShortcutsStore {
        FakeShortcutsStore(library: widest(count))
    }

    private static func row(_ index: Int) -> String { "id=\(identifier(index))" }

    private func shown(_ text: String, of count: Int) -> [Int] {
        (0..<count).filter { text.contains(Self.row($0)) }
    }

    private func call(
        _ name: String, _ arguments: [String: Value] = [:], store: FakeShortcutsStore,
        configuration: Configuration = Configuration(),
        timeout: Duration = ShortcutsTools.defaultTimeout
    ) async -> (text: String, isError: Bool) {
        let tools = ShortcutsTools(store: store, configuration: configuration, timeout: timeout)
        let result = await tools.handle(.init(name: name, arguments: arguments))
        guard case .text(let text) = result.content.first else { return ("(no text content)", true) }
        return (text, result.isError)
    }

    private func list(_ count: Int, _ arguments: [String: Value] = [:]) async -> (text: String, isError: Bool) {
        await call(ToolCatalog.listName, arguments, store: Self.store(count))
    }

    // MARK: Pages

    @Test("A call with no optional argument returns one default page, announced before the data")
    func defaultPage() async {
        let limit = Configuration.defaultListLimit
        let total = limit + 5
        let result = await list(total)
        #expect(!result.isError)
        #expect(result.text.hasPrefix("Showing 1–\(limit) of \(total) shortcuts. Pass offset=\(limit) for the next page.\n\n"))
        #expect(shown(result.text, of: total) == Array(0..<limit))
    }

    @Test("A page of ordinary rows is about one usual page")
    func ordinaryPageIsUsual() async {
        let library = (0..<Configuration.defaultListLimit + 5).map {
            Fixtures.shortcut(
                id: Self.identifier($0), name: "Invented shortcut \(Self.padded($0))",
                subtitle: "An invented subtitle of ordinary length", folder: "Invented folder",
                acceptsInput: true, actionCount: 12)
        }
        let result = await call(ToolCatalog.listName, store: FakeShortcutsStore(library: library))
        #expect(result.text.utf16.count <= ToolStandard.usualPage)
    }

    @Test("A result that holds every shortcut from the start carries no notice")
    func wholeListingHasNoNotice() async {
        let result = await list(Configuration.defaultListLimit)
        #expect(shown(result.text, of: Configuration.defaultListLimit).count == Configuration.defaultListLimit)
        #expect(!result.text.contains("Showing"))
        #expect(!result.text.contains("is outside"))
        #expect(!result.text.contains("clipped"))
    }

    @Test("limit at its maximum is used as asked, and a full page of the widest rows fits a result")
    func limitAtItsMaximum() async {
        let maximum = Configuration.listLimitRange.upperBound
        let total = maximum + 10
        let result = await list(total, ["limit": .int(maximum)])
        #expect(!result.text.contains("is outside"))
        #expect(result.text.hasPrefix("Showing 1–\(maximum) of \(total) shortcuts. Pass offset=\(maximum) for the next page.\n\n"))
        #expect(shown(result.text, of: total) == Array(0..<maximum))
        #expect(result.text.utf16.count <= ToolStandard.longestResult)
    }

    @Test("limit one past either end is moved to the nearest value, and the result says which")
    func limitPastItsRange() async {
        let maximum = Configuration.listLimitRange.upperBound
        let total = maximum + 10

        let over = await list(total, ["limit": .int(maximum + 1)])
        #expect(over.text.hasPrefix("""
            limit=\(maximum + 1) is outside 1–\(maximum); \(maximum) was used.
            Showing 1–\(maximum) of \(total) shortcuts. Pass offset=\(maximum) for the next page.


            """))
        #expect(shown(over.text, of: total) == Array(0..<maximum))

        let under = await list(total, ["limit": .int(0)])
        #expect(under.text.hasPrefix("limit=0 is outside 1–\(maximum); 1 was used.\nShowing 1–1 of \(total) "))
        #expect(shown(under.text, of: total) == [0])
    }

    @Test("Each page starts where the last one ended, and the last says that is all")
    func pagesChain() async {
        let first = await list(7, ["limit": .int(3)])
        #expect(first.text.hasPrefix("Showing 1–3 of 7 shortcuts. Pass offset=3 for the next page.\n\n"))
        #expect(shown(first.text, of: 7) == [0, 1, 2])

        let second = await list(7, ["limit": .int(3), "offset": .int(3)])
        #expect(second.text.hasPrefix("Showing 4–6 of 7 shortcuts. Pass offset=6 for the next page.\n\n"))
        #expect(shown(second.text, of: 7) == [3, 4, 5])

        let last = await list(7, ["limit": .int(3), "offset": .int(6)])
        #expect(last.text.hasPrefix("Showing 7–7 of 7 shortcuts. That is all.\n\n"))
        #expect(shown(last.text, of: 7) == [6])
    }

    @Test("An offset past the end returns no row and says so; a negative one is moved to zero")
    func offsetEdges() async {
        let past = await list(7, ["offset": .int(7)])
        #expect(!past.isError)
        #expect(past.text.hasPrefix("Showing 0 of 7 shortcuts: offset=7 is past the end. That is all.\n\n"))
        #expect(shown(past.text, of: 7).isEmpty)
        #expect(!past.text.contains("Nothing matched"))

        let lastRow = await list(7, ["offset": .int(6)])
        #expect(shown(lastRow.text, of: 7) == [6])

        let negative = await list(7, ["offset": .int(-1)])
        let range = Configuration.offsetRange
        #expect(negative.text.hasPrefix("offset=-1 is outside \(range.lowerBound)–\(range.upperBound); 0 was used.\n\n"))
        #expect(shown(negative.text, of: 7) == Array(0..<7))

        let beyond = await list(7, ["offset": .int(range.upperBound + 1)])
        #expect(beyond.text.hasPrefix("offset=\(range.upperBound + 1) is outside \(range.lowerBound)–\(range.upperBound); \(range.upperBound) was used.\n"))
    }

    @Test("An empty library and a search that matched nothing say different things")
    func emptyPages() async {
        let none = await list(0)
        #expect(none.text.contains("The library holds no shortcuts."))
        #expect(!none.text.contains("Showing"))

        let unmatched = await call(
            ToolCatalog.listName, ["query": .string("no such shortcut")], store: Self.store(3))
        #expect(unmatched.text.contains("Nothing matched."))
        #expect(unmatched.text.contains("0 shortcuts"))
    }

    @Test("The order is stated, ignores case, and breaks a tie by id, the same on every call")
    func orderIsStatedAndHasNoTies() async {
        let library = [
            Fixtures.shortcut(id: "b-2", name: "Report"),
            Fixtures.shortcut(id: "a-9", name: "report"),
            Fixtures.shortcut(id: "c-1", name: "Report"),
            Fixtures.shortcut(id: "z-0", name: "alpha"),
        ]
        let store = FakeShortcutsStore(library: library)
        let result = await call(ToolCatalog.listName, store: store)
        #expect(result.text.contains("ordered by name (ignoring case), then id."))
        let positions = ["z-0", "a-9", "b-2", "c-1"].compactMap {
            result.text.range(of: "id=\($0)")?.lowerBound
        }
        #expect(positions.count == 4 && positions == positions.sorted())

        let reversed = FakeShortcutsStore(library: library.reversed())
        #expect(await call(ToolCatalog.listName, store: reversed).text == result.text)
    }

    // MARK: Fields clipped in a row

    @Test("A field exactly as wide as its width is not clipped; one character more is, and the result says so")
    func clippingEdges() async {
        let exact = await list(3)
        #expect(!exact.text.contains("clipped"))
        #expect(!exact.text.contains("…"))

        func wider(_ name: Int, _ folder: Int, _ subtitle: Int) -> FakeShortcutsStore {
            FakeShortcutsStore(library: [
                Fixtures.shortcut(
                    id: "sc-wide", name: String(repeating: "n", count: name),
                    subtitle: String(repeating: "s", count: subtitle),
                    folder: String(repeating: "f", count: folder))
            ])
        }
        let atWidth = await call(
            ToolCatalog.listName,
            store: wider(Configuration.nameWidth, Configuration.folderWidth, Configuration.subtitleWidth))
        #expect(!atWidth.text.contains("clipped"))

        let name = await call(
            ToolCatalog.listName,
            store: wider(Configuration.nameWidth + 1, Configuration.folderWidth, Configuration.subtitleWidth))
        #expect(name.text == name.text.replacingOccurrences(of: "Subtitle is clipped", with: ""))
        #expect(name.text.hasPrefix("Name is clipped to \(Configuration.nameWidth) characters in each row. Read one in full with shortcut_get.\n\n"))
        #expect(!name.text.contains("Folder is clipped"))
        #expect(name.text.contains(String(repeating: "n", count: Configuration.nameWidth - 1) + "…"))
        #expect(!name.text.contains(String(repeating: "n", count: Configuration.nameWidth) + " "))

        let all = await call(
            ToolCatalog.listName,
            store: wider(Configuration.nameWidth + 1, Configuration.folderWidth + 1, Configuration.subtitleWidth + 1))
        #expect(all.text.hasPrefix("""
            Name is clipped to \(Configuration.nameWidth) characters in each row. Read one in full with shortcut_get.
            Folder is clipped to \(Configuration.folderWidth) characters in each row. Read one in full with shortcut_get.
            Subtitle is clipped to \(Configuration.subtitleWidth) characters in each row. Read one in full with shortcut_get.


            """))
    }

    @Test("A clipped name is still read in full by shortcut_get, by its id")
    func clippedNameIsReadable() async {
        let name = "long-" + String(repeating: "n", count: 200)
        let store = FakeShortcutsStore(library: [Fixtures.shortcut(id: "sc-wide", name: name)])
        let result = await call(ToolCatalog.getName, ["id": .string("sc-wide")], store: store)
        #expect(result.text.hasPrefix(name + "\n"))
    }

    @Test("A page of rows too wide to fit holds fewer of them and says where to resume")
    func widePageShrinks() async throws {
        // Ids are never clipped, so a library of very long ones is wider than any width foresaw.
        let wide = String(repeating: "w", count: 1000)
        let library = (0..<100).map {
            Fixtures.shortcut(id: "id-\(Self.padded($0))-\(wide)", name: "Shortcut \(Self.padded($0))")
        }
        var offset = 0
        var seen: [Int] = []
        while offset < library.count {
            let result = await call(
                ToolCatalog.listName, ["limit": .int(100), "offset": .int(offset)],
                store: FakeShortcutsStore(library: library))
            #expect(result.text.utf16.count <= ToolStandard.longestResult)
            let rows = (0..<library.count).filter { result.text.contains("id=id-\(Self.padded($0))-") }
            let last = try #require(rows.last)
            #expect(rows.first == offset)
            #expect(rows.count < 100)
            let next = last + 1 < library.count ? "Pass offset=\(last + 1) for the next page." : "That is all."
            #expect(result.text.hasPrefix("Showing \(offset + 1)–\(last + 1) of 100 shortcuts. \(next)\n\n"))
            seen += rows
            offset = last + 1
        }
        #expect(seen == Array(0..<library.count))
    }

    // MARK: Arguments

    @Test("An argument the tool does not take is refused with the names it takes, before anything runs")
    func unknownArgumentsAreRefused() async {
        let store = Self.store(3)
        for (tool, stray, taken) in [
            (ToolCatalog.listName, "max_results", "folder, limit, offset, query"),
            (ToolCatalog.getName, "text", "character_offset, id, max_characters, name"),
            (ToolCatalog.runName, "timeout", "id, input, name"),
            (ToolCatalog.statusName, "verbose", ""),
        ] {
            let result = await call(tool, [stray: .int(1)], store: store)
            #expect(result.isError, "\(tool)")
            #expect(result.text.hasPrefix("'\(stray)' is not an argument of \(tool)."), "\(tool): \(result.text)")
            if !taken.isEmpty { #expect(result.text.contains("It takes: \(taken)."), "\(tool): \(result.text)") }
        }
        #expect(store.runs.isEmpty)
        #expect(store.budgets.isEmpty, "a refusal comes before any Apple event")
        let long = String(repeating: "q", count: 500)
        let echoed = await call(ToolCatalog.listName, [long: .int(1)], store: store)
        #expect(echoed.text.count < 250)
    }

    @Test("A value of the wrong type is refused with the form expected")
    func wrongTypesAreRefused() async {
        let store = Self.store(3)
        for (tool, arguments, form) in [
            (ToolCatalog.listName, ["limit": Value.string("lots")], "a whole number was expected"),
            (ToolCatalog.listName, ["offset": .double(1.5)], "a whole number was expected"),
            (ToolCatalog.listName, ["query": .int(3)], "text was expected"),
            (ToolCatalog.getName, ["max_characters": .bool(true)], "a whole number was expected"),
            (ToolCatalog.getName, ["id": .int(3)], "text was expected"),
            (ToolCatalog.runName, ["id": .string("x"), "input": .int(3)], "text was expected"),
        ] {
            let result = await call(tool, arguments, store: store)
            #expect(result.isError, "\(tool)")
            #expect(result.text.contains(form), "\(tool): \(result.text)")
        }
        #expect(store.runs.isEmpty)
    }

    // MARK: The window on one record

    private static let longSubtitle = "start-" + String(repeating: "abcdefghij", count: 3_000) + "-end"

    private static func recordStore() -> FakeShortcutsStore {
        FakeShortcutsStore(library: [
            Fixtures.shortcut(id: "sc-long", name: "Invented", subtitle: longSubtitle, folder: "Invented folder")
        ])
    }

    private func record(_ extra: [String: Value] = [:]) async -> (text: String, isError: Bool) {
        await call(
            ToolCatalog.getName, ["id": .string("sc-long")].merging(extra) { _, new in new },
            store: Self.recordStore())
    }

    private var whole: String {
        Format().detail(
            ShortcutRecord(
                id: "sc-long", name: "Invented", subtitle: Self.longSubtitle, folder: "Invented folder",
                acceptsInput: false, actionCount: 3))
    }

    @Test("A long record comes as one default window, announced before the data")
    func defaultWindow() async {
        let size = Configuration.defaultMaxCharacters
        #expect(whole.count > size)
        let result = await record()
        #expect(result.text == "Characters 1–\(size) of \(whole.count). Pass character_offset=\(size) for the rest.\n\n" + String(whole.prefix(size)))
    }

    @Test("Windows chain: each starts where the last ended, and together they are the whole record")
    func windowsChain() async {
        var offset = 0
        var joined = ""
        while offset < whole.count {
            let result = await record(["character_offset": .int(offset), "max_characters": .int(7_000)])
            let marker = result.text.range(of: "\n\n")!
            let window = String(result.text[marker.upperBound...])
            let last = offset + window.count
            let next = last < whole.count ? "Pass character_offset=\(last) for the rest." : "That is all."
            #expect(result.text.hasPrefix("Characters \(offset + 1)–\(last) of \(whole.count). \(next)\n\n"))
            joined += window
            offset = last
        }
        #expect(joined == whole)
    }

    @Test("A record that fits one window carries no notice")
    func shortRecordHasNoNotice() async {
        let result = await call(ToolCatalog.getName, ["id": .string("sc-lights")], store: FakeShortcutsStore())
        #expect(!result.text.contains("Characters"))
        #expect(result.text.hasPrefix("MCP.Lights.On\n"))
    }

    @Test("max_characters and character_offset at their edges are used or moved, and the result says which")
    func windowEdges() async {
        let maximum = Configuration.maxCharactersRange.upperBound
        #expect(whole.count > maximum)
        let atMaximum = await record(["max_characters": .int(maximum)])
        #expect(!atMaximum.text.contains("is outside"))
        #expect(atMaximum.text.utf16.count <= ToolStandard.longestResult)

        let over = await record(["max_characters": .int(maximum + 1)])
        #expect(over.text.hasPrefix("max_characters=\(maximum + 1) is outside 1–\(maximum); \(maximum) was used.\nCharacters 1–\(maximum) of "))
        let under = await record(["max_characters": .int(0)])
        #expect(under.text.hasPrefix("max_characters=0 is outside 1–\(maximum); 1 was used.\nCharacters 1–1 of "))

        let past = await record(["character_offset": .int(whole.count + 50)])
        #expect(past.text.hasPrefix("Characters 0 of \(whole.count): character_offset=\(whole.count + 50) is past the end. That is all.\n\n"))
        let negative = await record(["character_offset": .int(-3)])
        let range = Configuration.characterOffsetRange
        #expect(negative.text.hasPrefix("character_offset=-3 is outside \(range.lowerBound)–\(range.upperBound); 0 was used.\nCharacters 1–"))
    }

    @Test("A window of characters that take several UTF-16 units each still fits a result, and still chains")
    func windowOfWideCharacters() async {
        let subtitle = String(repeating: "👩‍👩‍👧", count: 12_000)
        let store = FakeShortcutsStore(library: [Fixtures.shortcut(id: "sc-wide", name: "Invented", subtitle: subtitle)])
        let wholeRecord = Format().detail(Fixtures.shortcut(id: "sc-wide", name: "Invented", subtitle: subtitle))
        var offset = 0
        var windows = 0
        var joined = ""
        while offset < wholeRecord.count {
            windows += 1
            let result = await call(
                ToolCatalog.getName,
                ["id": .string("sc-wide"), "character_offset": .int(offset),
                 "max_characters": .int(Configuration.maxCharactersRange.upperBound)], store: store)
            #expect(result.text.utf16.count <= ToolStandard.longestResult)
            let window = String(result.text[result.text.range(of: "\n\n")!.upperBound...])
            #expect(!window.isEmpty)
            joined += window
            offset += window.count
        }
        #expect(windows > 1, "the record has to need more than one window")
        // Compared by length first: a failing comparison of two strings this long prints both.
        #expect(joined.count == wholeRecord.count)
        #expect(joined == wholeRecord)
    }

    // MARK: A run's output

    private func run(
        _ output: String, limit: Int = Configuration.defaultResultLimit
    ) async -> (text: String, isError: Bool) {
        var configuration = Configuration()
        configuration.resultLimit = limit
        return await call(
            ToolCatalog.runName, ["id": .string("sc-weather")],
            store: FakeShortcutsStore(outcome: { _ in .text(output) }), configuration: configuration)
    }

    @Test("Output exactly at the limit is whole; one character more is cut, and the sentence says how much")
    func outputEdges() async {
        let whole = await run(String(repeating: "x", count: 300), limit: 300)
        #expect(!whole.text.contains("Cut at"))
        #expect(whole.text.hasSuffix("Output:\n" + String(repeating: "x", count: 300)))

        let cut = await run(String(repeating: "x", count: 301), limit: 300)
        #expect(cut.text.hasPrefix("Cut at 300 of 301 characters; the rest cannot be read again.\n\nRan 'MCP.Weather'."))
        #expect(cut.text.hasSuffix("Output:\n" + String(repeating: "x", count: 300)))
    }

    @Test("The result limit is held to its range, and the longest one still fits a result")
    func outputAtTheLongestLimit() async {
        let maximum = Configuration.resultLimitRange.upperBound
        #expect(maximum <= ToolStandard.longestResult / 2)
        let result = await run(String(repeating: "x", count: maximum + 100), limit: maximum)
        #expect(result.text.hasPrefix("Cut at \(maximum) of \(maximum + 100) characters;"))
        #expect(result.text.utf16.count <= ToolStandard.longestResult)
    }

    @Test("Output of characters that take several UTF-16 units each is cut shorter, and the sentence stays true")
    func wideOutputIsFitted() async throws {
        let output = String(repeating: "👩‍👩‍👧", count: 6_000)
        let result = await run(output, limit: Configuration.resultLimitRange.upperBound)
        #expect(result.text.utf16.count <= ToolStandard.longestResult)
        let sentence = try #require(result.text.split(separator: "\n").first)
        let numbers = sentence.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        #expect(numbers.count == 2 && numbers[1] == 6_000 && numbers[0] < 6_000)
        let body = String(result.text[result.text.range(of: "Output:\n")!.upperBound...])
        #expect(body.count == numbers[0])
    }

    @Test("input at the limit runs; one character more is refused with its size, and nothing runs")
    func inputEdges() async {
        let limit = Configuration.inputLimit
        let store = FakeShortcutsStore()
        let atLimit = await call(
            ToolCatalog.runName, ["id": .string("sc-weather"), "input": .string(String(repeating: "i", count: limit))],
            store: store)
        #expect(!atLimit.isError)
        #expect(store.runs.count == 1 && store.runs[0].input?.count == limit)

        let refused = await call(
            ToolCatalog.runName,
            ["id": .string("sc-weather"), "input": .string(String(repeating: "i", count: limit + 1))],
            store: store)
        #expect(refused.isError)
        #expect(refused.text.contains("'input' is \(limit + 1) characters long; the most a run accepts is \(limit)."))
        #expect(store.runs.count == 1, "the refused call ran nothing")
        #expect(store.budgets.count == 1, "and looked nothing up")
    }

    // MARK: Errors

    @Test("An error repeats a caller's text only to a bounded width, and cuts a list of candidates")
    func errorsAreBounded() async {
        let long = String(repeating: "q", count: 500)
        let missing = await call(ToolCatalog.getName, ["name": .string(long)], store: FakeShortcutsStore())
        #expect(missing.isError && missing.text.utf16.count < 700)
        #expect(!missing.text.contains(String(repeating: "q", count: 100)))

        let twins = (0..<9).map { Fixtures.shortcut(id: "twin-\($0)", name: "Daily") }
        let ambiguous = await call(
            ToolCatalog.getName, ["name": .string("Daily")], store: FakeShortcutsStore(library: twins))
        #expect(ambiguous.text.contains("9 match. Ids: twin-0, twin-1, twin-2, twin-3, twin-4 and 4 more"))
        #expect(!ambiguous.text.contains("twin-5"))
        #expect(ambiguous.text.utf16.count <= ToolStandard.longestError)

        let message = ToolError.shortcutFailed(detail: String(repeating: "d", count: 50_000)).message
        #expect(message.utf16.count <= ToolStandard.longestError)
    }

    // MARK: Time

    @Test("A library that was not read in time is an error and lists nothing")
    func libraryNotRead() async {
        let store = FakeShortcutsStore()
        store.libraryFailure = .libraryNotRead(seconds: Configuration.scanBudgetSeconds)
        for tool in [ToolCatalog.listName, ToolCatalog.getName, ToolCatalog.runName] {
            let arguments: [String: Value] = tool == ToolCatalog.listName ? [:] : ["id": .string("sc-weather")]
            let result = await call(tool, arguments, store: store)
            #expect(result.isError, "\(tool)")
            #expect(result.text.hasPrefix("The library was not read within \(Configuration.scanBudgetSeconds) seconds"), "\(tool)")
        }
        #expect(store.runs.isEmpty)
        #expect(Set(store.budgets) == [Configuration.scanBudgetSeconds])
    }

    @Test("A read that outlasts the call's deadline is abandoned, and says nothing was changed")
    func readDeadline() async {
        let store = FakeShortcutsStore()
        store.libraryDelay = .seconds(5)
        let result = await call(ToolCatalog.listName, store: store, timeout: .milliseconds(100))
        #expect(result.isError)
        #expect(result.text.contains("This tool only reads, so nothing was changed."))
    }

    @Test("A run that outlasts the call's deadline says the shortcut may have run")
    func runDeadline() async {
        let store = FakeShortcutsStore()
        store.libraryDelay = .seconds(5)
        let result = await call(
            ToolCatalog.runName, ["id": .string("sc-weather")], store: store, timeout: .milliseconds(100))
        #expect(result.isError)
        #expect(result.text.contains("THE SHORTCUT MAY HAVE RUN, OR STILL BE RUNNING"))
    }

    @Test("The call's deadline is inside the time limit and outlasts a read plus a run's own wait")
    func deadlineIsChosenWithinTheLimit() {
        #expect(ShortcutsTools.defaultTimeout < ToolStandard.timeLimit)
        let longestWork = Configuration.scanBudgetSeconds * 2 + Configuration.timeoutRange.upperBound
        #expect(ShortcutsTools.defaultTimeout > .seconds(longestWork))
    }

    @Test("A setting moved into its range when the flags were read is reported by status")
    func statusReportsAdjustedSettings() async {
        let configuration = Configuration.parse(["--result-limit", "999999", "--timeout-seconds", "1"])
        let range = Configuration.resultLimitRange
        let result = await call(ToolCatalog.statusName, store: FakeShortcutsStore(), configuration: configuration)
        #expect(result.text.hasPrefix("--result-limit=999999 is outside \(range.lowerBound)–\(range.upperBound); \(range.upperBound) was used.\n--timeout-seconds=1 is outside"))
        let plain = await call(ToolCatalog.statusName, store: FakeShortcutsStore())
        #expect(!plain.text.contains("is outside"))
    }

    // MARK: The texts the model reads

    @Test("The instructions and every description are within the limit, as sent")
    func textsAreWithinTheLimit() {
        let catalog = ToolCatalog.all()
        #expect(ToolStandard.overlongTexts(instructions: ShortcutsMCPServer.instructions, catalog: catalog).isEmpty)
        var widest = Configuration()
        widest.resultLimit = Configuration.resultLimitRange.upperBound
        #expect(ToolStandard.overlongTexts(instructions: ShortcutsMCPServer.instructions, catalog: ToolCatalog.all(widest)).isEmpty)
    }

    @Test("Descriptions and the schema state the bounds the code enforces")
    func boundsAreStated() throws {
        let list = try #require(ToolCatalog.all().first { $0.name == ToolCatalog.listName })
        let description = try #require(list.description)
        #expect(description.contains("\(Configuration.defaultListLimit) to a page"))
        #expect(description.contains("1–\(Configuration.listLimitRange.upperBound)"))
        let limit = try #require(list.inputSchema.objectValue?["properties"]?.objectValue?["limit"]?.objectValue)
        #expect(limit["maximum"]?.intValue == Configuration.listLimitRange.upperBound)
        #expect(limit["default"]?.intValue == Configuration.defaultListLimit)

        let run = try #require(ToolCatalog.all().first { $0.name == ToolCatalog.runName })
        let input = try #require(run.inputSchema.objectValue?["properties"]?.objectValue?["input"]?.objectValue)
        #expect(input["maxLength"]?.intValue == Configuration.inputLimit)
        #expect(ShortcutsMCPServer.instructions.contains("\(Configuration.defaultListLimit) shortcuts to a page"))
    }

    // MARK: What is written for people

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func grouped(_ number: Int) -> String {
        number.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    @Test("The README states the figures the code enforces")
    func readmeStatesTheBounds() throws {
        let readme = try String(contentsOf: Self.root.appendingPathComponent("README.md"), encoding: .utf8)
        let figures: [(String, Int)] = [
            ("default page", Configuration.defaultListLimit),
            ("largest page", Configuration.listLimitRange.upperBound),
            ("name width", Configuration.nameWidth),
            ("folder width", Configuration.folderWidth),
            ("subtitle width", Configuration.subtitleWidth),
            ("result limit", Configuration.defaultResultLimit),
            ("result limit maximum", Configuration.resultLimitRange.upperBound),
            ("input limit", Configuration.inputLimit),
            ("run wait", Configuration().timeoutSeconds),
            ("read budget", Configuration.scanBudgetSeconds),
            ("call deadline", Int(ShortcutsTools.defaultTimeout.components.seconds)),
        ]
        for (name, figure) in figures {
            #expect(readme.contains(Self.grouped(figure)), "README does not state the \(name): \(figure)")
        }
    }

    @Test("The manifest describes every tool in step with its description, and states no figure")
    func manifestDescriptions() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("extension/manifest.json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let listed = try #require(manifest["tools"] as? [[String: Any]])
        #expect(listed.compactMap { $0["name"] as? String } == ToolCatalog.all().map(\.name))
        let text = (listed.compactMap { $0["description"] as? String } + [manifest["long_description"] as? String ?? ""]).joined()
        #expect(!text.contains("…"), "a manifest description is written whole, not cut")
        for tool in listed { #expect((tool["description"] as? String)?.isEmpty == false) }
    }
}
