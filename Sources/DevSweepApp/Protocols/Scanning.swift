/// The scan as a button outside the window starts it: whether one runs,
/// whether a clean holds the rows, whether there is a home to scan, and
/// starting one.
///
/// `ScanModel` conforms. `MenuBarViewModel` takes it, so its tests start
/// scans on a fake that only counts them.
@MainActor
protocol Scanning: AnyObject {
    var isScanning: Bool { get }
    var isCleaning: Bool { get }
    var canScan: Bool { get }
    func scan()
}
