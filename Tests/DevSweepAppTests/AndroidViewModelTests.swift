import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Android screens")
struct AndroidViewModelTests {
    @Test
    func `the SDK screen lists emulators, then system images, platforms, build tools and the rest`() {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.scan.showListings(extras: nil, android: sampleAndroid)
        app.window.screen = .androidSDK
        let android = sampleAndroid
        #expect(app.android.entries == android.emulators + android.systemImages + android.platforms
            + android.buildTools + android.otherSDKParts)
        app.window.screen = .androidStudios
        #expect(app.android.entries == android.studios)
        app.window.screen = .gradleCaches
        #expect(app.android.entries == android.gradleCaches)
    }

    @Test
    func `the inspector shows the selected entry, else the first flagged, else the first`() {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        var android = sampleAndroid
        // An emulator used today comes first; the system image unused since 2025 is flagged.
        android.emulators[0].lastUsed = Date()
        app.scan.showListings(extras: nil, android: android)
        app.window.screen = .androidSDK
        #expect(app.android.current == android.systemImages[0])
        app.android.select(android.platforms[0])
        #expect(app.android.current == android.platforms[0])
        app.window.screen = .androidStudios
        #expect(app.android.current == android.studios[0])
    }

    @Test
    func `each Android screen keeps its own selection`() {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.scan.showListings(extras: nil, android: sampleAndroid)
        app.window.screen = .androidSDK
        app.android.select(sampleAndroid.platforms[0])
        app.window.screen = .gradleCaches
        #expect(app.android.current == sampleAndroid.gradleCaches[0])
        app.window.screen = .androidSDK
        #expect(app.android.current == sampleAndroid.platforms[0])
    }
}
