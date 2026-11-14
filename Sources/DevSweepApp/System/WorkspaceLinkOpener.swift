import AppKit

/// Opens the page in the default browser, as clicking a link would.
struct WorkspaceLinkOpener: LinkOpening {
    @MainActor
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
