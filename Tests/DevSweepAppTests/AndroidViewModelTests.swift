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
        model.screen = .androidSDK
        let android = sampleAndroid
        #expect(model.androidEntries == android.emulators + android.systemImages + android.platforms
            + android.buildTools + android.otherSDKParts)
        model.screen = .androidStudios
        #expect(model.androidEntries == android.studios)
        model.screen = .gradleCaches
        #expect(model.androidEntries == android.gradleCaches)
    }

    @Test
    func `the inspector shows the selected entry, else the first flagged, else the first`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        var android = sampleAndroid
        // An emulator used today comes first; the system image unused since 2025 is flagged.
        android.emulators[0].lastUsed = Date()
        model.scan.showListings(extras: nil, android: android)
        model.screen = .androidSDK
        #expect(model.currentAndroidEntry == android.systemImages[0])
        model.selectedAndroidEntry = android.platforms[0].path
        #expect(model.currentAndroidEntry == android.platforms[0])
        model.screen = .androidStudios
        #expect(model.currentAndroidEntry == android.studios[0])
    }
}
