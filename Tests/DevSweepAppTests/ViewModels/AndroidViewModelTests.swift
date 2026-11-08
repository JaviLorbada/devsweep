import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Android screens")
struct AndroidViewModelTests {
    let window = FakeNavigation()
    let listings = FakeListings(android: sampleAndroid)

    var android: AndroidViewModel {
        AndroidViewModel(
            window: self.window,
            scan: self.listings,
            preferences: Preferences(storage: InMemoryPreferencesStore()))
    }

    @Test
    func `the SDK screen lists emulators, then system images, platforms, build tools and the rest`() {
        let model = self.android
        self.window.show(.androidSDK)
        let android = sampleAndroid
        #expect(model.entries == android.emulators + android.systemImages + android.platforms
            + android.buildTools + android.otherSDKParts)
        self.window.show(.androidStudios)
        #expect(model.entries == android.studios)
        self.window.show(.gradleCaches)
        #expect(model.entries == android.gradleCaches)
    }

    @Test
    func `the inspector shows the selected entry, else the first flagged, else the first`() {
        var android = sampleAndroid
        // An emulator used today comes first; the system image unused since 2025 is flagged.
        android.emulators[0].lastUsed = Date()
        self.listings.android = android
        let model = self.android
        self.window.show(.androidSDK)
        #expect(model.current == android.systemImages[0])
        model.select(android.platforms[0])
        #expect(model.current == android.platforms[0])
        self.window.show(.androidStudios)
        #expect(model.current == android.studios[0])
    }

    @Test
    func `each Android screen keeps its own selection`() {
        let model = self.android
        self.window.show(.androidSDK)
        model.select(sampleAndroid.platforms[0])
        self.window.show(.gradleCaches)
        #expect(model.current == sampleAndroid.gradleCaches[0])
        self.window.show(.androidSDK)
        #expect(model.current == sampleAndroid.platforms[0])
    }
}
