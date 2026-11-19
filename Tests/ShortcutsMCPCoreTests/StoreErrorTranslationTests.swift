import Foundation
import ShortcutsBridge
import Testing

@testable import ShortcutsMCPCore

/// The bridge's error cases as the tool layer reports them. Synthetic errors only.
@Suite("Store error translation")
struct StoreErrorTranslationTests {

    private func toolError(_ code: ShortcutsBridgeError.Code, _ message: String = "")
        -> ToolError
    {
        let failure = NSError(
            domain: ShortcutsBridgeErrorDomain, code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message])
        return ScriptingBridgeShortcutsStore.toolError(
            for: failure, identifier: "sc-id", timeoutSeconds: 50)
    }

    @Test("A shortcut that failed partway says it may have done part of its work")
    func runFailureWarnsOfPartialWork() {
        let error = toolError(.runFailed, "The file is not a PDF.")
        #expect(error == .shortcutFailed(detail: "The file is not a PDF."))
        #expect(error.message.contains("The file is not a PDF."))
        #expect(error.message.contains("MAY HAVE DONE PART OF ITS WORK"))
    }

    @Test("Not found, timeout and permission keep their own reports")
    func otherCasesKeepTheirReports() {
        #expect(toolError(.shortcutNotFound) == .notFound(reference: "sc-id"))
        #expect(toolError(.timedOut) == .timedOut(seconds: 50))
        #expect(toolError(.notPermitted) == .notAvailable(.automationDenied))
    }
}
