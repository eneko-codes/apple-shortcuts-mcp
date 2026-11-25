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

    /// The server is built from the system's own frameworks and nothing else. A dependency
    /// is a decision for the owner, so adding one has to break this test first.
    @Test("The package declares no third-party dependency")
    func noDependencies() throws {
        let package = try String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!package.contains(".package("), "Package.swift declares a dependency")
        #expect(!package.contains(".product("))
    }
}
