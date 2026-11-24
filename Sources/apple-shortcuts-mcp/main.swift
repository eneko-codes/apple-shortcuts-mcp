import Foundation
import ShortcutsMCPCore

// Launcher only. Everything testable lives in ShortcutsMCPCore, which the test target
// imports; an executable target cannot be imported.
//
// Settings come from the Claude extension manifest, which substitutes the person's
// user_config into this process's arguments.
await ShortcutsMCPServer.run(
    configuration: Configuration.parse(Array(CommandLine.arguments.dropFirst())))
