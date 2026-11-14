import Testing
@testable import DevSweepKit

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

    @Test(arguments: [
        (Int64(976), "999 KB"),
        (977, "1 MB"),
        (1023, "1 MB"),
        (976_074, "999 MB"),
        (976_075, "1.0 GB"),
        (1_048_576, "1.1 GB"),
        (8_388_608, "8.6 GB"),
        (1_073_741_824, "1099.5 GB"),
    ])
    func `kilobytes as du counts them, 1024 bytes each, print as the bash script prints them`(
        kilobytes: Int64,
        expected: String)
    {
        #expect(SizeText.of(kilobytes: kilobytes) == expected)
    }
}
