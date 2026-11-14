import AppKit

/// Opens a page in the browser: the Help menu's links. Live, the default
/// browser opens it; tests keep the links instead, so none opens a browser.
protocol LinkOpening: Sendable {
    @MainActor
    func open(_ url: URL)
}

/// Opens the page in the default browser, as clicking a link would.
struct WorkspaceLinkOpener: LinkOpening {
    @MainActor
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
