import Foundation
import ShortcutsBridge
import Testing

/// Synthetic `NSError`s only: the translation is a pure function, so nothing is sent to
/// Shortcuts Events.
@Suite("Bridge error translation")
struct BridgeErrorTranslationTests {

    private func translated(_ status: Int, userInfo: [String: Any] = [:]) -> NSError {
        let failure = NSError(domain: NSOSStatusErrorDomain, code: status, userInfo: userInfo)
        return ShortcutsBridge.translatedError(failure) as NSError
    }

    private func code(_ status: Int) -> ShortcutsBridgeError.Code? {
        ShortcutsBridgeError.Code(rawValue: translated(status).code)
    }

    @Test("errAENoSuchObject (-1728) means the shortcut is gone, not that the run failed")
    func noSuchObjectIsShortcutNotFound() {
        #expect(code(-1728) == .shortcutNotFound)
    }

    @Test("A denied grant and a timeout keep their own cases")
    func existingCasesStillMap() {
        #expect(code(-1743) == .notPermitted)
        #expect(code(-1712) == .timedOut)
    }

    /// Scripting Bridge puts the target's own explanation under "ErrorString"; for a
    /// shortcut that is the message of the action that failed.
    @Test("errOSAScriptError (-1753) is the shortcut failing, and keeps its own message")
    func scriptErrorIsRunFailed() {
        let failure = translated(-1753, userInfo: ["ErrorString": "The file is not a PDF."])
        #expect(ShortcutsBridgeError.Code(rawValue: failure.code) == .runFailed)
        #expect(failure.localizedDescription == "The file is not a PDF.")
    }

    @Test("Any other failed event is not blamed on the shortcut")
    func otherFailuresAreEventFailures() {
        #expect(code(-609) == .eventFailed)
    }
}
