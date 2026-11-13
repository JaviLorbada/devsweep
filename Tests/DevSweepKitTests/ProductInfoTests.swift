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
    }

    @Test func `the build number is the date and time the release was cut`() throws {
        let build = try #require(try versionFile()["BUILD_NUMBER"])
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyyMMddHHmm"
        #expect(build.count == 12 && build.allSatisfy(\.isASCII) && build.allSatisfy(\.isNumber))
        let date = try #require(format.date(from: build))
        #expect(format.string(from: date) == build, "\(build) isn't a real date and time")
    }

    @Test func `the About window and Help menu link to the repository the README names`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(contentsOf: root.appending(path: "README.md"), encoding: .utf8)
        #expect(readme.contains(ProductInfo.repository.absoluteString))
        #expect(ProductInfo.issues.absoluteString == ProductInfo.repository.absoluteString + "/issues")
        #expect(ProductInfo.license.absoluteString == ProductInfo.repository.absoluteString + "/blob/main/LICENSE")
    }

    @Test func `About, the Help menu and the README name the same places to sponsor and tip`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(contentsOf: root.appending(path: "README.md"), encoding: .utf8)
        #expect(ProductInfo.sponsor.absoluteString == "https://github.com/sponsors/JaviLorbada")
        #expect(ProductInfo.tipJar.absoluteString == "https://ko-fi.com/javilorbada")
        #expect(readme.contains("## Support"))
        #expect(readme.contains(ProductInfo.sponsor.absoluteString))
        #expect(readme.contains(ProductInfo.tipJar.absoluteString))
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
