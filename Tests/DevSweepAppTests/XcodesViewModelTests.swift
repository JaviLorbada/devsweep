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
        let model = makeModel(home: home, extras: extras)
        #expect(model.xcodes.current?.isSelected == true)
        model.xcodes.select(extras.xcodes[0])
        #expect(model.xcodes.current == extras.xcodes[0])

        extras.xcodes = extras.xcodes.map { xcode in
            var xcode = xcode
            xcode.isSelected = false
            return xcode
        }
        let other = makeModel(home: home, extras: extras)
        #expect(other.xcodes.current == extras.xcodes[0])
    }
}
