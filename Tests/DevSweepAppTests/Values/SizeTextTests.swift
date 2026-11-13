import Testing
@testable import DevSweepApp

@Suite("Size text")
struct SizeTextTests {
    @Test
    func `sizes count in thousands and round, as Finder and System Settings do`() {
        // 356.6 billion bytes, measured in 1024-byte blocks.
        #expect(SizeText.of(kilobytes: 348_243_164) == "356.6 GB")
        #expect(SizeText.of(kilobytes: 102_400) == "105 MB")
        #expect(SizeText.of(kilobytes: 16) == "16 KB")
        // Each unit takes over where the one below would round to 1000.
        #expect(SizeText.of(bytes: 999_500_000) == "1.0 GB")
        #expect(SizeText.of(bytes: 999_499_999) == "999 MB")
        #expect(SizeText.of(bytes: 999_500) == "1 MB")
        #expect(SizeText.of(bytes: 999_499) == "999 KB")
        #expect(SizeText.of(kilobytes: 0) == "0 KB")
        #expect(SizeText.of(kilobytes: -5) == "0 KB")
    }

    @Test
    func `a disk's capacity is in whole gigabytes, as macOS gives it`() {
        // A 1 TB Mac: 994.7 billion bytes.
        #expect(SizeText.wholeGigabytes(kilobytes: 971_386_719) == "995 GB")
        #expect(SizeText.wholeGigabytes(kilobytes: 500_000) == "512 MB")
    }
}
