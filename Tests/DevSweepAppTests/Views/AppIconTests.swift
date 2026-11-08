import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("App icon")
struct AppIconTests {
    @Test
    func `the ring has every family once, around the whole circle, with even gaps`() {
        #expect(Set(AppIconView.shares.map(\.family)) == Set(Family.allCases))
        #expect(abs(AppIconView.shares.reduce(0) { $0 + $1.share } - 1) < 1e-9)
        let segments = AppIconView.segments
        #expect(abs(segments[0].from - AppIconView.gap / 2) < 1e-9)
        #expect(abs(segments[segments.count - 1].to - (1 - AppIconView.gap / 2)) < 1e-9)
        for (segment, next) in zip(segments, segments.dropFirst()) {
            #expect(segment.from < segment.to)
            #expect(abs(next.from - segment.to - AppIconView.gap) < 1e-9)
        }
    }
}
