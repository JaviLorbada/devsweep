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
        #expect(model.currentXcode?.isSelected == true)
        model.selectedXcode = extras.xcodes[0].path
        #expect(model.currentXcode == extras.xcodes[0])

        extras.xcodes = extras.xcodes.map { xcode in
            var xcode = xcode
            xcode.isSelected = false
            return xcode
        }
        let other = makeModel(home: home, extras: extras)
        #expect(other.currentXcode == extras.xcodes[0])
    }
}
