import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Disk capacity text")
struct SizeTextTests {
    @Test
    func `a disk's capacity is in whole gigabytes, as macOS gives it`() {
        // A 1 TB Mac: 994.7 billion bytes.
        #expect(SizeText.wholeGigabytes(kilobytes: 971_386_719) == "995 GB")
        #expect(SizeText.wholeGigabytes(kilobytes: 500_000) == "512 MB")
    }
}
