import DevSweepKit
import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Overview")
struct OverviewViewModelTests {
    let window = FakeNavigation(.worktrees)
    /// DerivedData the biggest; SwiftPM's builds and cache, the cache bigger;
    /// npm's cache with nothing in it.
    let scan = FakeScanResults([
        result(.derivedData, kilobytes: 256),
        result(.swiftpmBuilds, kilobytes: 64),
        result(.swiftpmCache, kilobytes: 192),
        result(.npmCache, kilobytes: 0),
    ])
    let cleaning = FakeCleaningTotals()
    let apps = FakeRunningApps()

    var overview: OverviewViewModel {
        OverviewViewModel(window: self.window, scan: self.scan, cleaning: self.cleaning, apps: self.apps)
    }

    @Test
    func `picking a family shows the overview with its biggest item selected`() {
        let overview = self.overview
        overview.pick(.swiftPackages)
        #expect(self.window.screen == .overview)
        #expect(overview.selection == .swiftpmCache)
        // Nothing of npm's can be cleaned: its biggest row is still selected.
        overview.pick(.npm)
        #expect(overview.selection == .npmCache)
    }

    @Test
    func `a scan's end selects the biggest item, only when nothing is selected`() {
        let overview = self.overview
        overview.selectFirstIfNone()
        #expect(overview.selection == .derivedData)
        overview.select(.swiftpmCache)
        overview.selectFirstIfNone()
        #expect(overview.selection == .swiftpmCache)
    }

    @Test
    func `the status line says what the scan found, what is open, and what this session cleaned`() {
        let overview = self.overview
        #expect(overview.statusLine == "Not scanned yet.")
        let now = Date()
        self.scan.statusFacts = StatusText.Facts(measured: 4, items: 4, lastScan: now, now: now)
        #expect(overview.statusLine.hasPrefix("Scanned just now, 4 items."))
        self.cleaning.trashedThisSession = 1024
        #expect(overview.statusLine.hasSuffix("\(SizeText.of(kilobytes: 1024)) moved to Trash this session."))
        #expect(overview.subtitle.hasPrefix(overview.statusLine))
    }
}
