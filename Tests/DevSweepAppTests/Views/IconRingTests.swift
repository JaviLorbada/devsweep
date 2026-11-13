import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Icon ring")
struct IconRingTests {
    @Test
    func `the ring has every family once, around the whole circle, with even gaps`() {
        #expect(Set(IconRing.shares.map(\.family)) == Set(Family.allCases))
        #expect(abs(IconRing.shares.reduce(0) { $0 + $1.share } - 1) < 1e-9)
        let segments = IconRing.segments
        #expect(abs(segments[0].from - IconRing.gap / 2) < 1e-9)
        #expect(abs(segments[segments.count - 1].to - (1 - IconRing.gap / 2)) < 1e-9)
        for (segment, next) in zip(segments, segments.dropFirst()) {
            #expect(segment.from < segment.to)
            #expect(abs(next.from - segment.to - IconRing.gap) < 1e-9)
        }
    }
}
