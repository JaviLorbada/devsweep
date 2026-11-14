import Foundation

/// Opens a page in the browser: the Help menu's links. Live, the default
/// browser opens it; tests keep the links instead, so none opens a browser.
protocol LinkOpening: Sendable {
    @MainActor
    func open(_ url: URL)
}
