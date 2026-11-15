/// Times a scan from its start: until every item was measured, and until
/// the listings it waits for, the extras and Android Studio's, were in too.
struct ScanStopwatch {
    /// What a scan waits for before it's done.
    enum Phase {
        /// Every item measured.
        case items
        /// The Xcodes, runtimes and worktrees listed.
        case extras
        /// What Android Studio keeps, listed.
        case android
    }

    private let start: ContinuousClock.Instant
    private let waitsForExtras: Bool
    private let waitsForAndroid: Bool
    /// Seconds from the start to each phase that is in.
    private let laps: [Phase: Double]

    /// Starts timing a scan; it waits for the extras, Android Studio's
    /// listing, or both, when the scan makes them.
    init(waitsForExtras: Bool, waitsForAndroid: Bool, start: ContinuousClock.Instant = .now) {
        self.init(start: start, waitsForExtras: waitsForExtras, waitsForAndroid: waitsForAndroid, laps: [:])
    }

    private init(start: ContinuousClock.Instant, waitsForExtras: Bool, waitsForAndroid: Bool, laps: [Phase: Double]) {
        self.start = start
        self.waitsForExtras = waitsForExtras
        self.waitsForAndroid = waitsForAndroid
        self.laps = laps
    }

    /// The stopwatch with `phase` in at `now`.
    func lap(_ phase: Phase, at now: ContinuousClock.Instant = .now) -> ScanStopwatch {
        ScanStopwatch(
            start: self.start,
            waitsForExtras: self.waitsForExtras,
            waitsForAndroid: self.waitsForAndroid,
            laps: self.laps.merging([phase: (now - self.start) / .seconds(1)]) { $1 })
    }

    /// Seconds from the start until every item was measured, and until
    /// everything was in; nil until then.
    var timing: (items: Double, total: Double)? {
        guard let items = self.laps[.items],
              !self.waitsForExtras || self.laps[.extras] != nil,
              !self.waitsForAndroid || self.laps[.android] != nil
        else {
            return nil
        }
        return (items, self.laps.values.max() ?? items)
    }
}
