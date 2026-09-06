import Foundation
import MCP
import Testing

@testable import ShortcutsMCPCore

/// Drives the tool layer end to end against `FakeShortcutsStore`. No test in this file
/// sends an Apple event, so the suite runs with no permissions and runs nothing — which is
/// the point.
@Suite("Tool dispatch")
struct ShortcutsToolsTests {

    private func call(
        _ name: String, _ arguments: [String: Value] = [:],
        store: FakeShortcutsStore = FakeShortcutsStore(),
        configuration: Configuration = Configuration()
    ) async -> (text: String, isError: Bool) {
        let tools = ShortcutsTools(store: store, configuration: configuration)
        let result = await tools.handle(.init(name: name, arguments: arguments))
        guard case .text(let text, _, _) = result.content.first else {
            return ("(no text content)", true)
        }
        return (text, result.isError ?? false)
    }

    // MARK: Catalogue

    @Test("Every tool has a unique name, title and description")
    func catalogueIsWellFormed() {
        let names = ToolCatalog.all().map(\.name)
        #expect(names.count == Set(names).count)
        for tool in ToolCatalog.all() {
            #expect(tool.description?.isEmpty == false, "\(tool.name) has no description")
            #expect(tool.title?.isEmpty == false, "\(tool.name) has no title")
        }
    }

    @Test("Annotations match what each tool actually does")
    func annotationsAreHonest() {
        let reads = ["shortcuts_status", "shortcuts_list", "shortcut_get"]
        for tool in ToolCatalog.all() {
            #expect(tool.annotations.readOnlyHint == reads.contains(tool.name), "\(tool.name)")
            // run_shortcut is marked destructive and open-world because this server cannot
            // tell a shortcut that turns on a lamp from one that empties a folder.
            #expect(tool.annotations.destructiveHint == (tool.name == "run_shortcut"))
            #expect(tool.annotations.openWorldHint == (tool.name == "run_shortcut"))
        }
    }

    /// The convention across this family of servers: a read is named for what it returns,
    /// anything that acts is named for the verb. There is no create/update/delete here —
    /// nothing in the library is written — so `run_` is the only verb in the catalogue.
    @Test("The one tool that acts carries a verb prefix and the reads do not")
    func namingConventionHolds() {
        for tool in ToolCatalog.all() {
            let isWrite = tool.annotations.readOnlyHint == false
            #expect(isWrite == tool.name.hasPrefix("run_"), "\(tool.name)")
        }
    }

    /// Regression guard for a defect first seen in the sibling contacts server, where it
    /// made every list field of update_contact unusable.
    ///
    /// Claude Desktop's schema sanitiser drops a property whose `type` is a union such as
    /// `["string", "null"]`, replacing the whole subtree with `{}`. The model then
    /// serialises the argument wrongly and it is rejected on arrival. Nothing downstream of
    /// the client can catch this, so it is caught here.
    @Test("No property declares its type as a union")
    func schemasDeclareScalarTypes() {
        func walk(_ value: Value, path: String) {
            guard let node = value.objectValue else { return }
            if let declared = node["type"] {
                #expect(
                    declared.stringValue != nil,
                    "\(path): type must be a single string, not a union")
            }
            for (key, child) in node["properties"]?.objectValue ?? [:] {
                walk(child, path: "\(path).\(key)")
            }
            if let items = node["items"] { walk(items, path: "\(path)[]") }
        }
        for tool in ToolCatalog.all() { walk(tool.inputSchema, path: tool.name) }
    }

    /// The advertised limits are interpolated from the live configuration, so a description
    /// cannot state a bound the running server does not enforce.
    @Test("run_shortcut advertises the configured timeout and result limit")
    func runDescriptionTracksConfiguration() {
        var configuration = Configuration()
        configuration.timeoutSeconds = 45
        configuration.resultLimit = 1_234
        let run = ToolCatalog.all(configuration).first { $0.name == "run_shortcut" }
        #expect(run?.description?.contains("45 seconds") == true)
        #expect(run?.description?.contains("1234 characters") == true)
    }

    // MARK: Status

    @Test("Status reports each availability state and never runs anything")
    func statusReportsAvailability() async {
        let cases: [(ShortcutsAvailability, String)] = [
            (.ready, "GRANTED"),
            (.automationDenied, "DENIED"),
            (.notInstalled, "UNAVAILABLE"),
            (.consentNotGranted, "not settled"),
        ]
        for (state, expected) in cases {
            let store = FakeShortcutsStore(state: state)
            let (text, isError) = await call("shortcuts_status", store: store)
            #expect(!isError, "status must answer even when access is denied")
            #expect(text.contains(expected), "\(state): \(text)")
            #expect(store.runs.isEmpty)
        }
    }

    // MARK: Availability gate

    @Test("A blocking availability refuses every tool but status")
    func blockedStatesRefuseWork() async {
        for state in [ShortcutsAvailability.automationDenied, .notInstalled] {
            let store = FakeShortcutsStore(state: state)
            for tool in ["shortcuts_list", "shortcut_get", "run_shortcut"] {
                let (_, isError) = await call(
                    tool, ["name": .string("MCP.Weather")], store: store)
                #expect(isError, "\(tool) must refuse when \(state)")
            }
            #expect(store.runs.isEmpty, "nothing may run when \(state)")
        }
    }

    /// Refusing here would mean the Automation dialog never appears, so the permission
    /// could never be granted at all.
    @Test("Consent not yet settled does not block a call")
    func pendingConsentDoesNotBlock() async {
        let store = FakeShortcutsStore(state: .consentNotGranted)
        let (text, isError) = await call("shortcuts_list", store: store)
        #expect(!isError, "\(text)")
    }

    // MARK: Listing

    @Test("The listing shows the whole library, with its folder and action count")
    func listShowsLibrary() async {
        let (text, isError) = await call("shortcuts_list")
        #expect(!isError, "\(text)")
        #expect(text.contains("7 shortcuts"))
        #expect(text.contains("MCP.Weather"))
        #expect(text.contains("id=sc-weather"))
        #expect(text.contains("7 actions"))
        #expect(text.contains("takes input"))
        #expect(text.contains("Folders on this page: Automation, Personal, Work"))
    }

    @Test("query matches name and subtitle, ignoring case")
    func listFiltersByQuery() async {
        let (byName, _) = await call("shortcuts_list", ["query": .string("lights")])
        #expect(byName.contains("MCP.Lights.On"))
        #expect(!byName.contains("Archive Downloads"))

        let (bySubtitle, _) = await call("shortcuts_list", ["query": .string("forecast")])
        #expect(bySubtitle.contains("MCP.Weather"))
        #expect(!bySubtitle.contains("MCP.Lights.On"))
    }

    @Test("folder narrows to one folder and ignores case")
    func listFiltersByFolder() async {
        let (text, _) = await call("shortcuts_list", ["folder": .string("automation")])
        #expect(text.contains("MCP.Lights.On"))
        #expect(text.contains("MCP.Weather"))
        #expect(!text.contains("Archive Downloads"))
    }

    @Test("A truncated listing says what it withheld and how to page")
    func listPages() async {
        let (first, _) = await call("shortcuts_list", ["limit": .int(2)])
        #expect(first.contains("…5 more · call again with offset=2"))

        let (second, _) = await call("shortcuts_list", ["limit": .int(2), "offset": .int(2)])
        #expect(!second.contains("Archive Downloads"), "offset must skip what page one showed")
        #expect(second.contains("MCP.Lights.On"))
        #expect(second.contains("…3 more · call again with offset=4"))
    }

    @Test("An out-of-range limit is clamped rather than refused")
    func listClampsLimit() async {
        let (text, isError) = await call("shortcuts_list", ["limit": .int(99_999)])
        #expect(!isError, "\(text)")
        #expect(text.contains("7 shortcuts"))
    }

    @Test("A non-integer limit is a plain argument error")
    func listRejectsNonIntegerLimit() async {
        let (text, isError) = await call("shortcuts_list", ["limit": .string("lots")])
        #expect(isError)
        #expect(text.contains("an integer was expected"))
    }

    // MARK: Resolution

    @Test("A shortcut resolves by name and by id")
    func getResolvesEitherWay() async {
        let (byName, nameFailed) = await call(
            "shortcut_get", ["name": .string("MCP.Weather")])
        #expect(!nameFailed, "\(byName)")
        #expect(byName.contains("sc-weather"))
        #expect(byName.contains("accepts input"))

        let (byID, idFailed) = await call("shortcut_get", ["id": .string("sc-archive")])
        #expect(!idFailed, "\(byID)")
        #expect(byID.contains("Archive Downloads"))
        #expect(byID.contains("(top level)"))
    }

    @Test("Every record says the actions cannot be read")
    func getStatesTheCeiling() async {
        let (text, _) = await call("shortcut_get", ["id": .string("sc-weather")])
        #expect(text.contains("no API for the contents"))
    }

    @Test("Neither name nor id is an error that says what to pass")
    func referenceIsRequired() async {
        let (text, isError) = await call("shortcut_get")
        #expect(isError)
        #expect(text.contains("pass 'name' or 'id'"))
    }

    @Test("Both name and id is refused rather than one silently winning")
    func nameAndIDAreExclusive() async {
        let store = FakeShortcutsStore()
        let (text, isError) = await call(
            "run_shortcut", ["name": .string("MCP.Weather"), "id": .string("sc-lights")],
            store: store)
        #expect(isError)
        #expect(text.contains("not both"))
        #expect(store.runs.isEmpty, "an ambiguous reference must not run anything")
    }

    @Test("An exact name wins over a case-insensitive match")
    func exactNameWinsOverCase() async {
        let (text, isError) = await call("shortcut_get", ["name": .string("Notes")])
        #expect(!isError, "\(text)")
        #expect(text.contains("sc-notes-upper"))
    }

    @Test("A name matching two shortcuts is refused with both ids")
    func duplicateNamesAreAmbiguous() async {
        let store = FakeShortcutsStore()
        let (text, isError) = await call(
            "run_shortcut", ["name": .string("Daily Report")], store: store)
        #expect(isError)
        #expect(text.contains("sc-twin-a"))
        #expect(text.contains("sc-twin-b"))
        #expect(store.runs.isEmpty, "an ambiguous name must not run either of them")
    }

    /// "NOTES" matches "Notes" and "notes" equally once case is ignored, and there is no
    /// exact match to prefer.
    @Test("A case-insensitive match that hits two names is ambiguous too")
    func caseInsensitiveDuplicatesAreAmbiguous() async {
        let (text, isError) = await call("shortcut_get", ["name": .string("NOTES")])
        #expect(isError)
        #expect(text.contains("More than one shortcut is named"))
    }

    @Test("An unknown name and an unknown id both say to look the shortcut up again")
    func unknownReferencesExplainThemselves() async {
        for argument in [["name": Value.string("Nope")], ["id": Value.string("sc-nope")]] {
            let (text, isError) = await call("shortcut_get", argument)
            #expect(isError)
            #expect(text.contains("shortcuts_list again"))
        }
    }

    @Test("An empty name is an argument error, not a failed lookup")
    func emptyNameIsRejected() async {
        let (text, isError) = await call("shortcut_get", ["name": .string("   ")])
        #expect(isError)
        #expect(text.contains("pass 'name' or 'id'"))
    }

    // MARK: Running

    /// There is deliberately no allow-list or name-prefix scope here any more: the owner
    /// removed both in favour of plug-and-play. A shortcut with a name that would once have
    /// been out of scope under a restrictive setting must still run — `run_shortcut`'s own
    /// permission switch in Claude Desktop is the only gate left.
    @Test("There is no name scope: any shortcut in the library can be run")
    func anyShortcutCanBeRun() async {
        let store = FakeShortcutsStore()
        let (text, isError) = await call(
            "run_shortcut", ["name": .string("Archive Downloads")], store: store)
        #expect(!isError, "\(text)")
        #expect(store.runs.map(\.id) == ["sc-archive"])
    }

    @Test("A run returns the shortcut's output and reports what it ran")
    func runReturnsOutput() async {
        let store = FakeShortcutsStore(outcome: { _ in .text("22 °C, clear") })
        let (text, isError) = await call(
            "run_shortcut", ["id": .string("sc-weather")], store: store)
        #expect(!isError, "\(text)")
        #expect(text.contains("Ran 'MCP.Weather'"))
        #expect(text.contains("22 °C, clear"))
        #expect(store.runs.map(\.id) == ["sc-weather"])
    }

    @Test("A run always addresses the shortcut by id, even when asked for by name")
    func runResolvesNameToID() async {
        let store = FakeShortcutsStore()
        _ = await call("run_shortcut", ["name": .string("MCP.Lights.On")], store: store)
        #expect(store.runs.map(\.id) == ["sc-lights"])
    }

    /// Input is the one string not trimmed: whitespace can matter to whatever the shortcut
    /// does with it.
    @Test("Input reaches the store exactly as it was given")
    func inputIsPassedVerbatim() async {
        let store = FakeShortcutsStore()
        _ = await call(
            "run_shortcut", ["id": .string("sc-weather"), "input": .string("  Bilbao ")],
            store: store)
        #expect(store.runs.first?.input == "  Bilbao ")

        let without = FakeShortcutsStore()
        _ = await call("run_shortcut", ["id": .string("sc-weather")], store: without)
        #expect(without.runs.first?.input == nil, "an absent key means no input at all")
    }

    @Test("The configured timeout is what the store is asked to wait")
    func runPassesTheConfiguredTimeout() async {
        var configuration = Configuration()
        configuration.timeoutSeconds = 30
        let store = FakeShortcutsStore()
        _ = await call(
            "run_shortcut", ["id": .string("sc-lights")], store: store,
            configuration: configuration)
        #expect(store.runs.first?.timeoutSeconds == 30)
    }

    @Test("A shortcut that returns nothing reads differently from one that returns nothing usable")
    func runDistinguishesEmptyFromUnrenderable() async {
        let silent = FakeShortcutsStore(outcome: { _ in .empty })
        let (quiet, _) = await call("run_shortcut", ["id": .string("sc-lights")], store: silent)
        #expect(quiet.contains("returned no output"))

        let opaque = FakeShortcutsStore(outcome: { _ in
            ShortcutRun(hasResult: true, resultIsText: false, result: "")
        })
        let (binary, _) = await call("run_shortcut", ["id": .string("sc-lights")], store: opaque)
        #expect(binary.contains("no textual form"))
    }

    @Test("A long result is cut at the configured limit and says how much was withheld")
    func runTruncatesLongOutput() async {
        var configuration = Configuration()
        configuration.resultLimit = 200
        let store = FakeShortcutsStore(outcome: { _ in .text(String(repeating: "x", count: 500)) })
        let (text, isError) = await call(
            "run_shortcut", ["id": .string("sc-weather")], store: store,
            configuration: configuration)
        #expect(!isError, "\(text)")
        #expect(text.contains("cut off at 200 characters of 500"))
        #expect(!text.contains(String(repeating: "x", count: 201)))
    }

    /// A timeout is the one failure that must not read as "it did not work": the shortcut
    /// is probably still running.
    @Test("A timeout says the shortcut may still be running")
    func runReportsTimeout() async {
        let store = FakeShortcutsStore(outcome: { _ in throw ToolError.timedOut(seconds: 120) })
        let (text, isError) = await call(
            "run_shortcut", ["id": .string("sc-weather")], store: store)
        #expect(isError)
        #expect(text.contains("MAY STILL BE RUNNING"))
    }

    @Test("A store failure is reported rather than swallowed")
    func runReportsStoreFailure() async {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "Shortcuts Events went away" }
        }
        let store = FakeShortcutsStore(outcome: { _ in throw Boom() })
        let (text, isError) = await call(
            "run_shortcut", ["id": .string("sc-weather")], store: store)
        #expect(isError)
        #expect(text.contains("Shortcuts Events went away"))
    }

    @Test("An unknown tool name is refused")
    func unknownToolIsRefused() async {
        let (text, isError) = await call("shortcuts_delete_everything")
        #expect(isError)
        #expect(text.contains("is not a tool of this server"))
    }
}
