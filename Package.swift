// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "apple-shortcuts-mcp",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        // Every Apple event this project sends, in Objective-C.
        //
        // Not a style choice. Scripting Bridge builds its classes at runtime, so their
        // metadata symbols do not exist at link time and a Swift metatype cast against
        // one aborts the process (swiftlang/swift#43407). In Objective-C a cast to a
        // protocol is a compile-time annotation and nothing has to be bridged at all.
        // Only Foundation types cross back.
        .target(name: "ShortcutsBridge"),

        // All logic lives here so the tests can import it. The executable target below
        // is only a launcher: an executable target cannot be imported by a test target.
        .target(
            name: "ShortcutsMCPCore",
            dependencies: ["ShortcutsBridge", .product(name: "MCP", package: "swift-sdk")]
        ),
        .executableTarget(
            name: "apple-shortcuts-mcp",
            dependencies: ["ShortcutsMCPCore"],
            // TCC identifies this binary by its own embedded Info.plist. Claude Desktop
            // spawns MCP servers through Contents/Helpers/disclaimer, which calls
            // responsibility_spawnattrs_setdisclaim, so the process is its own TCC
            // subject. Sending Apple events without NSAppleEventsUsageDescription is
            // denied without a prompt.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "ShortcutsMCPCoreTests", dependencies: ["ShortcutsMCPCore"]),
    ]
)
