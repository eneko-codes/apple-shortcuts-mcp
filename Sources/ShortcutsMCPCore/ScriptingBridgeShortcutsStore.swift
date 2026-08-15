import Foundation
import ShortcutsBridge

/// `ShortcutsStore` backed by the real Shortcuts library, driven through Apple events.
///
/// The events themselves live in the `ShortcutsBridge` Objective-C target; see its header
/// for why they cannot live in Swift. What stays here is translation: bridge dictionaries
/// into value types, bridge errors into `ToolError`. Every decision worth testing —
/// resolution, truncation, formatting — is above the `ShortcutsStore` seam, not here.
public struct ScriptingBridgeShortcutsStore: ShortcutsStore {
    public static let bundleIdentifier = "com.apple.shortcuts.events"

    public init() {}

    // MARK: Availability

    public func availability() -> ShortcutsAvailability {
        guard ShortcutsBridge.isShortcutsEventsInstalled else { return .notInstalled }

        switch Self.automationPermission() {
        case OSStatus(errAEEventNotPermitted): return .automationDenied
        case OSStatus(errAEEventWouldRequireUserConsent): return .consentNotGranted
        // Shortcuts Events is not running, which is its ordinary state: it is a faceless
        // helper launched by the first Apple event. TCC cannot be asked about a process
        // that does not exist yet, so the permission is only settled by sending one.
        case OSStatus(procNotFound): return .consentNotGranted
        default: return .ready
        }
    }

    /// Asks TCC whether this process may drive Shortcuts Events, **without sending a real
    /// event and without raising a dialog** (`askUserIfNeeded: false`). That is what lets
    /// `shortcuts_status` be honest about permissions while running nothing at all.
    static func automationPermission() -> OSStatus {
        var target = AEAddressDesc()
        let identifier = Data(bundleIdentifier.utf8)
        let created = identifier.withUnsafeBytes { bytes in
            AECreateDesc(typeApplicationBundleID, bytes.baseAddress, bytes.count, &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
    }

    private func guardAvailability() throws {
        let state = availability()
        guard !state.blocksCalls else { throw ToolError.notAvailable(state) }
    }

    /// The bridge reports failures as `NSError`; the tool layer speaks `ToolError`.
    ///
    /// Three codes are worth telling apart because their remedies differ completely: a
    /// denied grant is fixed in System Settings, a timeout means the shortcut is probably
    /// still running, and a missing shortcut means the library moved on since the listing.
    private func translate(_ error: Error, identifier: String, timeoutSeconds: Int) -> ToolError {
        let failure = error as NSError
        guard failure.domain == ShortcutsBridgeErrorDomain else {
            return .storeFailure(failure.localizedDescription)
        }
        switch failure.code {
        case ShortcutsBridgeError.notPermitted.rawValue:
            return .notAvailable(.automationDenied)
        case ShortcutsBridgeError.notInstalled.rawValue:
            return .notAvailable(.notInstalled)
        case ShortcutsBridgeError.timedOut.rawValue:
            return .timedOut(seconds: timeoutSeconds)
        case ShortcutsBridgeError.shortcutNotFound.rawValue:
            return .notFound(reference: identifier)
        default:
            return .storeFailure(failure.localizedDescription)
        }
    }

    // MARK: Library

    public func shortcuts() async throws -> [ShortcutRecord] {
        try guardAvailability()

        let raw: [[String: Any]]
        do {
            raw = try ShortcutsBridge.shortcuts()
        } catch {
            throw translate(error, identifier: "", timeoutSeconds: 0)
        }

        return raw.compactMap { entry in
            guard let identifier = entry["id"] as? String, let name = entry["name"] as? String
            else { return nil }
            let subtitle = entry["subtitle"] as? String
            return ShortcutRecord(
                id: identifier,
                name: name,
                subtitle: (subtitle?.isEmpty ?? true) ? nil : subtitle,
                folder: entry["folder"] as? String,
                acceptsInput: entry["acceptsInput"] as? Bool ?? false,
                actionCount: entry["actionCount"] as? Int ?? 0)
        }
    }

    // MARK: Run

    public func run(id: String, input: String?, timeoutSeconds: Int) async throws -> ShortcutRun {
        try guardAvailability()

        let raw: [String: Any]
        do {
            raw = try ShortcutsBridge.runShortcut(
                withIdentifier: id, input: input, timeoutSeconds: timeoutSeconds)
        } catch {
            throw translate(error, identifier: id, timeoutSeconds: timeoutSeconds)
        }

        return ShortcutRun(
            hasResult: raw["hasResult"] as? Bool ?? false,
            resultIsText: raw["resultIsText"] as? Bool ?? false,
            result: raw["result"] as? String ?? "")
    }
}
