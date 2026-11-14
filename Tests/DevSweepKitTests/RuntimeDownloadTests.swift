import Foundation
import Testing
@testable import DevSweepKit

@Suite("Simulator runtime downloads")
struct RuntimeDownloadTests {
    /// iOS 18.5 lives in the Cryptex folder and has a download of its own in
    /// AssetsV2; iOS 27.0 lives in its download, which simctl's size counts.
    func stubRuntimes(_ home: FakeHome, _ tools: FakeTools) -> String {
        let assets = home.outside("AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime")
        let download = "\(assets)/ios-18-5.asset"
        home.writeZeros("\(download)/AssetData/download.dmg", kilobytes: 2048)
        tools.runtimesJSON = Data("""
        {
          "WITH-DOWNLOAD": { "version": "18.5", "build": "22F77", "sizeBytes": 1048576,
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
            "path": "\(home.outside("Cryptex/ios-18-5/runtime.dmg"))",
            "parentImagePath": "\(download)/AssetData/download.dmg" },
          "IN-ITS-DOWNLOAD": { "version": "27.0", "build": "24A434", "sizeBytes": 1048576,
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            "path": "\(assets)/ios-27-0.asset/AssetData" }
        }
        """.utf8)
        return download
    }

    @Test
    func `a runtime's own download counts in its size, which removing it frees`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let download = self.stubRuntimes(home, tools)
        let runtimes = try await engine(home, tools).extras().runtimes
        let downloaded = try #require(runtimes.first { $0.id == "WITH-DOWNLOAD" })
        let measured = SizeMeasurer().measure(download).kilobytes
        #expect(measured >= 2048)
        #expect(downloaded.downloadKilobytes == measured)
        #expect(downloaded.kilobytes == 1024 + measured)
        let other = try #require(runtimes.first { $0.id == "IN-ITS-DOWNLOAD" })
        #expect(other.downloadKilobytes == nil)
        #expect(other.kilobytes == 1024)
    }

    @Test
    func `under the original script's name the download counts too, as the script counts it`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let download = self.stubRuntimes(home, tools)
        var config = ScanConfig.fromEnvironment(home.environment, command: .original)
        config.environment = home.environment
        let runtimes = try await Engine(config: config, tools: tools.tools).extras().runtimes
        let measured = SizeMeasurer().measure(download).kilobytes
        #expect(runtimes.first { $0.id == "WITH-DOWNLOAD" }?.kilobytes == 1024 + measured)
        #expect(runtimes.first { $0.id == "IN-ITS-DOWNLOAD" }?.kilobytes == 1024)
    }

    @Test
    func `a download any runtime lives in, its own too, or several share, or outside a MobileAsset is left out`() {
        let json = Data("""
        {
          "LIVES-IN-X": { "path": "/Assets/x.asset/AssetData" },
          "PARENT-X": { "parentImagePath": "/Assets/x.asset/AssetData/a.dmg" },
          "SHARES-Y-1": { "parentImagePath": "/Assets/y.asset/AssetData/b.dmg" },
          "SHARES-Y-2": { "parentImagePath": "/Assets/y.asset/AssetData/b.dmg" },
          "PARENT-Z": { "parentImagePath": "/Assets/z.asset/AssetData/c.dmg" },
          "LIVES-IN-ITS-OWN": { "path": "/Assets/s.asset/AssetData/Restore",
                                "parentImagePath": "/Assets/s.asset/AssetData/s.dmg" },
          "NOT-AN-ASSET": { "parentImagePath": "/Library/Developer/CoreSimulator/Images/d.dmg" }
        }
        """.utf8)
        #expect(ExtrasScanner.downloads(SimctlRuntimeList(json)) == ["PARENT-Z": "/Assets/z.asset"])
        #expect(ExtrasScanner.downloads(SimctlRuntimeList(Data("nope".utf8))).isEmpty)
    }

    @Test(arguments: [
        (
            "/System/Library/AssetsV2/kind/ios-18-5.asset/AssetData/a.dmg",
            "/System/Library/AssetsV2/kind/ios-18-5.asset"),
        ("/System/Library/AssetsV2/kind/ios-18-5.asset", "/System/Library/AssetsV2/kind/ios-18-5.asset"),
        ("/Library/Developer/CoreSimulator/Images/a.dmg", nil),
        // As the script's /^(.*\.asset)(\/|$)/ reads them: the last .asset
        // that ends a name, on the first line, relative or not.
        ("/a.asset/b.asset/c.dmg", "/a.asset/b.asset"),
        ("/folder/.asset/a.dmg", "/folder/.asset"),
        ("ios-18-5.asset/a.dmg", "ios-18-5.asset"),
        ("/x.assets/y.dmg", nil),
        ("/p.asset\n/q.asset", nil),
    ])
    func `a download is the MobileAsset folder its image is in`(path: String, folder: String?) {
        #expect(ExtrasScanner.assetFolder(path) == folder)
    }
}
