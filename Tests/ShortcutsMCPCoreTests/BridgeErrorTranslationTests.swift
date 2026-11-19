import Foundation
import ShortcutsBridge
import Testing

/// Synthetic `NSError`s only: the translation is a pure function, so nothing is sent to
/// Shortcuts Events.
@Suite("Bridge error translation")
struct BridgeErrorTranslationTests {

    private func translated(_ status: Int) -> ShortcutsBridgeError.Code? {
        let failure = NSError(domain: NSOSStatusErrorDomain, code: status)
        let result = ShortcutsBridge.translatedError(failure) as NSError
        return ShortcutsBridgeError.Code(rawValue: result.code)
    }

    @Test("errAENoSuchObject (-1728) means the shortcut is gone, not that the run failed")
    func noSuchObjectIsShortcutNotFound() {
        #expect(translated(-1728) == .shortcutNotFound)
    }

    @Test("A denied grant and a timeout keep their own cases")
    func existingCasesStillMap() {
        #expect(translated(-1743) == .notPermitted)
        #expect(translated(-1712) == .timedOut)
    }
}
