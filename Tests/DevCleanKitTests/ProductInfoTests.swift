import Foundation
import Testing
@testable import DevCleanKit

@Suite("Product info")
struct ProductInfoTests {
    /// `version.env` at the package root, as `KEY=value` lines.
    func versionFile() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appending(path: "version.env"), encoding: .utf8)
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        return values
    }

    @Test func `the names in the code match version.env`() throws {
        let file = try versionFile()
        #expect(file["PRODUCT_NAME"] == ProductInfo.name)
        #expect(file["CLI_NAME"] == ProductInfo.cliName)
        #expect(file["BUNDLE_ID"] == ProductInfo.bundleIdentifier)
        #expect(file["MARKETING_VERSION"]?.isEmpty == false)
        #expect(Int(file["BUILD_NUMBER"] ?? "") != nil)
    }

    @Test func `the command line still calls itself devclean, as the bash script does`() {
        #expect(CommandLineOptions.usage.hasPrefix("Usage: devclean [--run [--yes]]"))
    }
}
