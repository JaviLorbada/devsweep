import DevSweepKit
import Observation

/// The Xcode versions screen's own state: the Xcode selected and what the
/// screen says under its title.
@MainActor
@Observable
final class XcodesViewModel {
    /// The Xcode selected, by its path.
    private(set) var selectedPath: String?
    private let scan: ScanModel

    init(scan: ScanModel) {
        self.scan = scan
    }

    var xcodes: [InstalledXcode] {
        self.scan.extras?.xcodes ?? []
    }

    /// The selected Xcode, or the one in use, or the first.
    var current: InstalledXcode? {
        self.xcodes.first { $0.path == self.selectedPath } ?? self.xcodes.first { $0.isSelected } ?? self.xcodes.first
    }

    func select(_ xcode: InstalledXcode) {
        self.selectedPath = xcode.path
    }

    var subtitle: String {
        StatusText.xcodes(self.scan.extras?.xcodes, isLoading: self.scan.isLoadingExtras)
    }
}
