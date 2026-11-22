import ServiceManagement

/// The app itself as a login item, through `SMAppService.mainApp`. Run from
/// a plain executable it registers too, though it reports not found until
/// then, as an app bundle never registered does.
@MainActor
struct MainAppLoginItem: LoginItemRegistering {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
