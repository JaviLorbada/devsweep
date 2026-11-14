import DevSweepKit
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Help menu")
struct HelpCommandsTests {
    @Test
    func `the items are in title case, with an ellipsis where a form asks for more`() {
        #expect(FeedbackLink.Form.problem.title == "Report a Problem…")
        #expect(FeedbackLink.Form.idea.title == "Suggest an Idea…")
        #expect(HelpCommands.supportTitle == "Support DevSweep")
    }

    @Test
    func `reporting a problem or an idea opens its form, filled in, in the browser and nothing else`() {
        let links = RecordingLinkOpener()
        let help = HelpCommands(links: links)
        let about = FeedbackLink.About(version: "0.6.0 (202611141200)", macOS: "26.1 (25B78)")
        help.open(.problem, about: about)
        help.open(.idea, about: about)
        #expect(links.opened == [
            FeedbackLink(form: .problem, about: about).url,
            FeedbackLink(form: .idea, about: about).url,
        ])
    }

    @Test
    func `on its own, it fills the forms in with this app on this Mac`() throws {
        let links = RecordingLinkOpener()
        HelpCommands(links: links).open(.problem)
        let url = try #require(links.opened.first)
        #expect(url == FeedbackLink(form: .problem, about: .current).url)
    }
}
