import DevSweepKit

/// The boot volume's free space as the app shows it: what Finder and System
/// Settings call available, which counts the space macOS can purge on its
/// own. `df`'s free blocks stand in when macOS doesn't say.
extension DiskSpace {
    var freeKilobytes: Int64 {
        self.availableIncludingPurgeableKilobytes ?? self.availableKilobytes
    }

    /// "337.6 GB free of 995 GB".
    var freeOfTotal: String {
        let free = SizeText.of(kilobytes: self.freeKilobytes)
        return "\(free) free of \(SizeText.wholeGigabytes(kilobytes: self.totalKilobytes))"
    }
}
