import Foundation
import Testing

@testable import ShortcutsMCPCore

/// The installer decides whether a bundle is new by the manifest version alone, while
/// `initialize` reports the server constant and TCC sees the Info.plist. If they drift,
/// a bug report describes a build nobody has.
@Suite("Version")
struct VersionTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("Manifest, server constant and Info.plist carry the same version")
    func versionsAgree() throws {
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.root.appending(path: "extension/manifest.json")))
            as? [String: Any]
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: Self.root.appending(path: "Resources/Info.plist")),
            format: nil) as? [String: Any]

        #expect(manifest?["version"] as? String == ShortcutsMCPServer.version)
        #expect(plist?["CFBundleShortVersionString"] as? String == ShortcutsMCPServer.version)
    }
}
