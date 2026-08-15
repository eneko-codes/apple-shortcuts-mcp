import Foundation
import Testing

@testable import ShortcutsMCPCore

/// `Configuration` is down to two numeric settings now that the owner's plug-and-play rule
/// removed the shortcut allow-list and the name-prefix scope. These tests exist to pin the
/// parsing rules that remain: clamping, defaults, and ignoring an unsubstituted manifest
/// placeholder.
@Suite("Configuration")
struct ConfigurationTests {

    @Test("Flags parse to the values given")
    func flagsParse() {
        let parsed = Configuration.parse(["--result-limit", "500", "--timeout-seconds", "30"])
        #expect(parsed.resultLimit == 500)
        #expect(parsed.timeoutSeconds == 30)
    }

    @Test("No arguments gives the documented defaults")
    func defaultsHold() {
        let parsed = Configuration.parse([])
        #expect(parsed.resultLimit == 4_000)
        #expect(parsed.timeoutSeconds == 120)
    }

    @Test("An empty value falls back to the default rather than parsing as zero")
    func emptyValuesAreIgnored() {
        let parsed = Configuration.parse(["--result-limit", "", "--timeout-seconds", ""])
        #expect(parsed.resultLimit == 4_000)
        #expect(parsed.timeoutSeconds == 120)
    }

    /// Claude Desktop leaves `${user_config.key}` unsubstituted when a setting is empty, so
    /// the literal text could otherwise arrive as an argument. Neither flag is wired into
    /// the manifest today, but the parser still has to be forgiving of the pattern.
    @Test("An unsubstituted placeholder is treated as absent")
    func placeholdersAreIgnored() {
        let parsed = Configuration.parse([
            "--result-limit", "${user_config.result_limit}",
            "--timeout-seconds", "${user_config.timeout_seconds}",
        ])
        #expect(parsed.resultLimit == 4_000)
        #expect(parsed.timeoutSeconds == 120)
    }

    @Test("Out-of-range numbers are clamped, not refused")
    func numbersAreClamped() {
        let low = Configuration.parse(["--result-limit", "1", "--timeout-seconds", "0"])
        #expect(low.resultLimit == Configuration.resultLimitRange.lowerBound)
        #expect(low.timeoutSeconds == Configuration.timeoutRange.lowerBound)

        let high = Configuration.parse([
            "--result-limit", "9999999", "--timeout-seconds", "99999",
        ])
        #expect(high.resultLimit == Configuration.resultLimitRange.upperBound)
        #expect(high.timeoutSeconds == Configuration.timeoutRange.upperBound)
    }

    /// A server that refuses to start over a malformed argument is far harder to diagnose
    /// than one running on a default.
    @Test("Unknown flags and junk values are ignored")
    func unknownFlagsAreIgnored() {
        let parsed = Configuration.parse(["--not-a-flag", "x", "--timeout-seconds", "soon"])
        #expect(parsed.timeoutSeconds == 120)
    }
}
