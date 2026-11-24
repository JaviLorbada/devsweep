/// An update the daily check found, waiting for the person: the menu bar
/// item's dot, and a row at the top of its panel. Debug runs name it with
/// `DEVSWEEP_UPDATE=available` or `ready`.
enum WaitingUpdate: String {
    /// Found: choosing the row shows it in Sparkle's window, which offers
    /// what comes next.
    case available
    /// Downloaded, to install when the app quits: choosing the row installs
    /// it now and relaunches the app.
    case ready

    /// The row's title, after Sparkle's own words. An ellipsis where its
    /// window asks what to do next; none where the row does it.
    var title: String {
        switch self {
        case .available: "Update Available…"
        case .ready: "Install Update and Relaunch"
        }
    }
}
