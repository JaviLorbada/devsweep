import SwiftUI
import Testing
@testable import DevSweepApp

@Suite("Chart contrast")
struct ChartContrastTests {
    let standard = ChartContrast()

    @Test
    func `the charts draw as they always have`() {
        #expect(self.standard.ringGap == 1.6)
        #expect(self.standard.dimmed == 0.42)
        #expect(self.standard.lastScan == 0.25)
        #expect(self.standard.measuring == 0.6)
        #expect(self.standard.pending == 0.5)
        #expect(self.standard.blockEdgeWidth == 1)
    }
}
