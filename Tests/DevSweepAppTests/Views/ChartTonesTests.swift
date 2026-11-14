import SwiftUI
import Testing
@testable import DevSweepApp

@Suite("Chart tones")
struct ChartTonesTests {
    let standard = ChartTones(.standard)
    let increased = ChartTones(.increased)

    @Test
    func `without Increase Contrast the charts draw as they always have`() {
        #expect(self.standard.ringGap == 1.6)
        #expect(self.standard.dimmed == 0.42)
        #expect(self.standard.lastScan == 0.25)
        #expect(self.standard.measuring == 0.6)
        #expect(self.standard.pending == 0.5)
        #expect(self.standard.blockEdgeWidth == 1)
    }

    @Test
    func `with Increase Contrast segments sit further apart, and what is faded draws stronger`() {
        #expect(self.increased.ringGap > self.standard.ringGap)
        #expect(self.increased.blockEdgeWidth > self.standard.blockEdgeWidth)
        let faded: [KeyPath<ChartTones, Double>] = [\.dimmed, \.lastScan, \.measuring, \.pending]
        for tone in faded {
            #expect(self.increased[keyPath: tone] > self.standard[keyPath: tone])
        }
        let environment = EnvironmentValues()
        for tone in [\ChartTones.placeholder, \.cleaned] {
            #expect(self.increased[keyPath: tone].resolve(in: environment).opacity
                > self.standard[keyPath: tone].resolve(in: environment).opacity * 1.8)
        }
    }
}
