import Foundation
import Testing
@testable import DevSweepKit

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

    @Test
    func `the tool is devsweep, and devclean when run under the original script's name`() {
        #expect(CommandLineOptions.usage().hasPrefix("Usage: devsweep [--run [--yes]]"))
        #expect(CommandLineOptions.usage(.original).hasPrefix("Usage: devclean [--run [--yes]]"))
        #expect(CommandLineOptions.usage().contains("$DEVSWEEP_PROJECT_DIRS if set"))
        #expect(CommandLineOptions.usage(.original).contains("$DEVCLEAN_PROJECT_DIRS if set"))
        #expect(CommandName.invoked(as: "/usr/local/bin/devsweep") == .product)
        #expect(CommandName.invoked(as: "/tmp/harness/bin/devclean") == .original)
        #expect(CommandName.invoked(as: "devclean") == .original)
        #expect(CommandName.invoked(as: "") == .product)
    }

    @Test
    func `each name reads its own variables`() {
        let environment = ["HOME": "/h", "DEVSWEEP_PROJECT_DIRS": "/new", "DEVCLEAN_PROJECT_DIRS": "/old"]
        #expect(ScanConfig.fromEnvironment(environment).projectDirectories == ["/new"])
        #expect(ScanConfig.fromEnvironment(environment, command: .original).projectDirectories == ["/old"])
    }
}
