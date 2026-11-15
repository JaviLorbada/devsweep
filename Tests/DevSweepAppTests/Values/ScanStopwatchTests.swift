import Testing
@testable import DevSweepApp

@Suite("Scan stopwatch")
struct ScanStopwatchTests {
    let start = ContinuousClock.now

    @Test
    func `a scan that lists nothing is timed once its items are measured`() {
        let stopwatch = ScanStopwatch(waitsForExtras: false, waitsForAndroid: false, start: self.start)
        #expect(stopwatch.timing == nil)

        let timing = stopwatch.lap(.items, at: self.start + .seconds(2)).timing
        #expect(timing?.items == 2)
        #expect(timing?.total == 2)
    }

    @Test
    func `it waits for the listings the scan makes, and ends with the last of them`() {
        let measured = ScanStopwatch(waitsForExtras: true, waitsForAndroid: true, start: self.start)
            .lap(.items, at: self.start + .seconds(2))
        #expect(measured.timing == nil)

        let android = measured.lap(.android, at: self.start + .seconds(5))
        #expect(android.timing == nil, "the extras aren't in yet")

        let timing = android.lap(.extras, at: self.start + .milliseconds(3500)).timing
        #expect(timing?.items == 2)
        #expect(timing?.total == 5)
    }

    @Test
    func `listings in before the items wait for them`() {
        let listed = ScanStopwatch(waitsForExtras: true, waitsForAndroid: false, start: self.start)
            .lap(.extras, at: self.start + .seconds(1))
        #expect(listed.timing == nil)

        let timing = listed.lap(.items, at: self.start + .seconds(3)).timing
        #expect(timing?.items == 3)
        #expect(timing?.total == 3)
    }
}
