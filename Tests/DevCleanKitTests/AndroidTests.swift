import Foundation
import Testing
@testable import DevCleanKit

@Suite("Android Studio")
struct AndroidTests {
    /// A home with Android Studio, an SDK with two system images, an emulator
    /// in use and one left alone since January 2025, and Gradle's caches.
    func androidHome() -> (FakeHome, FakeTools) {
        let home = FakeHome(), tools = FakeTools(home: home)
        let app = home.path("Applications/Android Studio.app")
        home.write("\(app)/Contents/Info.plist", plist(["CFBundleShortVersionString": "2025.1", "CFBundleVersion": "AI-251.1"]))
        home.writeZeros("\(app)/Contents/MacOS/studio", kilobytes: 32)

        let sdk = home.path("Library/Android/sdk")
        let current = "\(sdk)/system-images/android-35/google_apis/arm64-v8a"
        home.write("\(current)/source.properties", "AndroidVersion.ApiLevel=35\nSystemImage.TagDisplay=Google APIs,Page Size 16KB\nSystemImage.Abi=arm64-v8a\n")
        home.writeZeros("\(current)/system.img", kilobytes: 64)
        let old = "\(sdk)/system-images/android-30/default/x86_64"
        home.writeZeros("\(old)/system.img", kilobytes: 48)
        home.write("\(sdk)/platforms/android-35/source.properties", "Platform.Version=15\nAndroidVersion.ApiLevel=35\n")
        home.fill("\(sdk)/build-tools/35.0.0")
        home.writeZeros("\(sdk)/emulator/qemu", kilobytes: 16)
        home.fill("\(sdk)/platform-tools")
        // Outside home: the path policy keeps it out.
        home.fill(home.outside("elsewhere"))
        home.symlink(home.outside("elsewhere"), at: "\(sdk)/linked")

        let avd = home.path(".android/avd")
        home.write("\(avd)/Pixel_8.avd/config.ini", """
            avd.ini.displayname=Pixel 8
            image.sysdir.1=system-images/android-35/google_apis/arm64-v8a/
            tag.display=Google APIs
            target=android-35
            """)
        home.writeZeros("\(avd)/Pixel_8.avd/userdata-qemu.img", kilobytes: 24)
        home.write("\(avd)/Old_Tablet.avd/config.ini", "image.sysdir.1=system-images/android-30/default/x86_64/\ntarget=android-30\n")
        home.writeZeros("\(avd)/Old_Tablet.avd/userdata-qemu.img", kilobytes: 8)
        for file in ["config.ini", "userdata-qemu.img", ""] {
            home.setModified("\(avd)/Old_Tablet.avd/\(file)", "202501011200")
        }
        for folder in [current, old, "\(old)/system.img", "\(current)/system.img", "\(current)/source.properties"] {
            home.setModified(folder, "202501011200")
        }

        home.fill(home.path(".gradle/caches/modules-2"))
        home.fill(home.path(".gradle/wrapper/dists/gradle-9.6.1-bin"))
        home.fill(home.path(".gradle/daemon"))
        return (home, tools)
    }

    func plist(_ values: [String: String]) -> String {
        let entries = values.map { "<key>\($0.key)</key><string>\($0.value)</string>" }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>\(entries)</dict></plist>"
    }

    func report(_ home: FakeHome, _ tools: FakeTools) async throws -> AndroidReport {
        var config = ScanConfig.fromEnvironment(home.environment)
        config.includeAndroid = true
        config.applicationsDirectories = [home.path("Applications")]
        let engine = try Engine(config: config, tools: tools.tools)
        return await engine.android()
    }

    @Test
    func `lists Android Studio, the SDK's parts, emulators and Gradle's caches with sizes`() async throws {
        let (home, tools) = androidHome()
        let report = try await report(home, tools)

        #expect(report.studios.map(\.title) == ["Android Studio 2025.1"])
        #expect(report.studios.first?.detail == "AI-251.1")
        #expect(report.systemImages.map(\.title) == ["API 35, Google APIs, Page Size 16KB", "API 30, default"])
        #expect(report.systemImages.first?.detail == "arm64-v8a")
        #expect(report.platforms.map(\.title) == ["Android 15 (API 35)"])
        #expect(report.buildTools.map(\.title) == ["Build tools 35.0.0"])
        #expect(report.otherSDKParts.map(\.title) == ["Emulator", "Platform tools"])
        #expect(report.emulators.map(\.title) == ["Pixel 8", "Old Tablet"])
        #expect(report.emulators.first?.detail == "API 35, Google APIs")
        #expect(Set(report.gradleCaches.map(\.title)) == ["Dependency and build caches", "Gradle versions", "Daemon logs"])
        #expect(report.gradleCaches.first { $0.title == "Gradle versions" }?.detail == "9.6.1")
        #expect(report.all.allSatisfy { $0.kilobytes > 0 })
        #expect(report.systemImages.first?.kilobytes ?? 0 >= 64)
    }

    @Test
    func `keeps out anything the path policy refuses`() async throws {
        let (home, tools) = androidHome()
        let report = try await report(home, tools)
        #expect(!report.all.contains { $0.path.contains("elsewhere") || $0.path.hasSuffix("/linked") })
        let homeReal = try #require(FileSystem.physicalDirectory(home.home))
        #expect(report.sdkEntries.allSatisfy { $0.path.hasPrefix(homeReal + "/") })
    }

    @Test
    func `flags system images and emulators unused for the threshold, by modification date`() async throws {
        let (home, tools) = androidHome()
        let report = try await report(home, tools)
        let pixel = try #require(report.emulators.first { $0.title == "Pixel 8" })
        let tablet = try #require(report.emulators.first { $0.title == "Old Tablet" })
        #expect(pixel.flagReason(staleDays: 90) == nil)
        #expect(tablet.flagReason(staleDays: 90)?.hasPrefix("Not used in ") == true)

        // The current image's own files are old, but an emulator on it ran today.
        let current = try #require(report.systemImages.first { $0.title.hasPrefix("API 35") })
        let old = try #require(report.systemImages.first { $0.title.hasPrefix("API 30") })
        #expect(current.emulatorCount == 1)
        #expect(current.flagReason(staleDays: 90) == nil)
        #expect(old.emulatorCount == 1)
        #expect(old.flagReason(staleDays: 90) != nil)
        #expect(old.flagReason(staleDays: 100_000) == nil)

        // Installs, platforms and caches are never flagged.
        #expect((report.studios + report.platforms + report.buildTools + report.gradleCaches).allSatisfy { $0.flagReason(staleDays: 0) == nil })
    }

    @Test
    func `only a scan that asks for it lists Android Studio, so the command line never does`() async throws {
        let (home, tools) = androidHome()
        let commandLine = try engine(home, tools)
        #expect(!commandLine.config.includeAndroid)
        let events = await collect(commandLine)
        #expect(!events.contains { if case .android = $0 { true } else { false } })

        var config = commandLine.config
        config.includeAndroid = true
        let app = try Engine(config: config, tools: tools.tools)
        var reports = 0
        for await event in app.scan(.interactive) {
            if case .android = event { reports += 1 }
        }
        #expect(reports == 1)
    }

    @Test
    func `an empty home lists nothing`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let report = try await report(home, tools)
        #expect(report.all.isEmpty)
        #expect(report.sdk == nil)
    }

    @Test
    func `A saved scan from before Android Studio was listed still loads`() throws {
        let home = FakeHome()
        let store = ScanStore(url: URL(fileURLWithPath: home.path("last-scan.json")))
        let json = #"{"version":1,"date":"2026-10-21T10:00:00Z","home":"/x","results":[],"extras":null}"#
        home.write(home.path("last-scan.json"), json)
        let scan = try #require(store.load(home: "/x"))
        #expect(scan.android == nil)
    }
}
