import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Xcode versions screen")
struct XcodesViewModelTests {
    @Test
    func `the inspector shows the selected Xcode, else the one in use, else the first`() {
        var extras = sampleExtras
        extras.xcodes.reverse()
        let listings = FakeListings(extras: extras)
        let xcodes = XcodesViewModel(scan: listings)
        #expect(xcodes.current?.isSelected == true)
        xcodes.select(extras.xcodes[0])
        #expect(xcodes.current == extras.xcodes[0])

        extras.xcodes = extras.xcodes.map { xcode in
            var xcode = xcode
            xcode.isSelected = false
            return xcode
        }
        let other = XcodesViewModel(scan: FakeListings(extras: extras))
        #expect(other.current == extras.xcodes[0])
    }

    @Test
    func `the subtitle says when the list is still coming`() {
        let listings = FakeListings()
        listings.isLoadingExtras = true
        let xcodes = XcodesViewModel(scan: listings)
        #expect(xcodes.subtitle == StatusText.xcodes(nil, isLoading: true))
        listings.extras = sampleExtras
        listings.isLoadingExtras = false
        #expect(xcodes.subtitle == StatusText.xcodes(sampleExtras.xcodes, isLoading: false))
    }
}
