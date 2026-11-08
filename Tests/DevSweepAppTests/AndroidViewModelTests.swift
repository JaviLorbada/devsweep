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
        let model = makeModel(home: home)
        model.scan.showListings(extras: nil, android: sampleAndroid)
        model.window.screen = .androidSDK
        let android = sampleAndroid
        #expect(model.android.entries == android.emulators + android.systemImages + android.platforms
            + android.buildTools + android.otherSDKParts)
        model.window.screen = .androidStudios
        #expect(model.android.entries == android.studios)
        model.window.screen = .gradleCaches
        #expect(model.android.entries == android.gradleCaches)
    }

    @Test
    func `the inspector shows the selected entry, else the first flagged, else the first`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        var android = sampleAndroid
        // An emulator used today comes first; the system image unused since 2025 is flagged.
        android.emulators[0].lastUsed = Date()
        model.scan.showListings(extras: nil, android: android)
        model.window.screen = .androidSDK
        #expect(model.android.current == android.systemImages[0])
        model.android.select(android.platforms[0])
        #expect(model.android.current == android.platforms[0])
        model.window.screen = .androidStudios
        #expect(model.android.current == android.studios[0])
    }

    @Test
    func `each Android screen keeps its own selection`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        model.scan.showListings(extras: nil, android: sampleAndroid)
        model.window.screen = .androidSDK
        model.android.select(sampleAndroid.platforms[0])
        model.window.screen = .gradleCaches
        #expect(model.android.current == sampleAndroid.gradleCaches[0])
        model.window.screen = .androidSDK
        #expect(model.android.current == sampleAndroid.platforms[0])
    }
}
