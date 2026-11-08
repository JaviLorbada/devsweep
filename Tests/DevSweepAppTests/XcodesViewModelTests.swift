import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Xcode versions screen")
struct XcodesViewModelTests {
    @Test
    func `the inspector shows the selected Xcode, else the one in use, else the first`() {
        let home = TemporaryHome()
        var extras = sampleExtras
        extras.xcodes.reverse()
        let app = makeApp(home: home, extras: extras)
        #expect(app.xcodes.current?.isSelected == true)
        app.xcodes.select(extras.xcodes[0])
        #expect(app.xcodes.current == extras.xcodes[0])

        extras.xcodes = extras.xcodes.map { xcode in
            var xcode = xcode
            xcode.isSelected = false
            return xcode
        }
        let other = makeApp(home: home, extras: extras)
        #expect(other.xcodes.current == extras.xcodes[0])
    }
}
