import ServiceManagement

/// DevSweep as a login item, which macOS opens when the person logs in.
/// macOS keeps it, and the person can remove it in System Settings as well,
/// so it is read, never kept. Live, Service Management does it; tests keep
/// what was asked, so none adds the test runner to Login Items.
@MainActor
protocol LoginItemRegistering {
    /// Registered, waiting on the person's approval, or neither: not
    /// registered, or not found, as macOS says of an app never registered.
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings at Login Items.
    func openLoginItems()
}
