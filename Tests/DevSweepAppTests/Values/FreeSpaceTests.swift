import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Free space")
struct FreeSpaceTests {
    // A 1 TB Mac: 994.7 billion bytes, 329.2 billion free, 337.6 billion as
    // Finder counts it.
    let total: Int64 = 971_386_719
    let free: Int64 = 321_484_375
    let finder: Int64 = 329_687_500

    @Test
    func `free space is what Finder and System Settings show, purgeable space included`() {
        let space = DiskSpace(
            totalKilobytes: self.total,
            availableKilobytes: self.free,
            availableIncludingPurgeableKilobytes: self.finder)
        #expect(space.freeKilobytes == self.finder)
        #expect(space.freeOfTotal == "337.6 GB free of 995 GB")
    }

    @Test
    func `without macOS's figure, the free blocks stand in`() {
        let space = DiskSpace(totalKilobytes: self.total, availableKilobytes: self.free)
        #expect(space.freeKilobytes == self.free)
        #expect(space.freeOfTotal == "329.2 GB free of 995 GB")
    }
}
