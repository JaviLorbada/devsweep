import DevSweepKit
import SwiftUI

/// The Help menu, in place of a Help book there is none of: the project on
/// GitHub, its issue forms filled in, and its tip jar. Each item opens a
/// page in the browser through `links`, and DevSweep sends nothing itself.
struct HelpCommands: Commands {
    let links: any LinkOpening

    /// Opens the tip jar.
    static let supportTitle = "Support \(ProductInfo.name)"

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("\(ProductInfo.name) on GitHub") { self.links.open(ProductInfo.repository) }
            Button(FeedbackLink.Form.problem.title) { self.open(.problem) }
            Button(FeedbackLink.Form.idea.title) { self.open(.idea) }
            Divider()
            Button(Self.supportTitle) { self.links.open(ProductInfo.tipJar) }
        }
    }

    /// Opens the form in the browser, filled in with this app on this Mac.
    @MainActor
    func open(_ form: FeedbackLink.Form, about: FeedbackLink.About = .current) {
        self.links.open(FeedbackLink(form: form, about: about).url)
    }
}
