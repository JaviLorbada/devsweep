import DevSweepKit
import Testing
@testable import DevSweepApp

@Suite("Clean notices")
struct CleanNoticeTests {
    @Test
    func `apps that didn't quit are named, and nothing was cleaned`() {
        let notice = CleanNotice.notQuit([.xcode, .simulator])
        #expect(notice.title == "Xcode and Simulator didn't quit")
        #expect(notice.message.hasPrefix("Nothing was cleaned. Quit them yourself"))
    }

    @Test
    func `apps opened since the question are named`() {
        let notice = CleanNotice.appsOpen([.xcode])
        #expect(notice.title == "Nothing was cleaned")
        #expect(notice.message == "Xcode is open.")
    }

    @Test
    func `a scan that took the rows asks to clean again after it`() {
        let notice = CleanNotice.rowsTaken
        #expect(notice.title == "Nothing was cleaned")
        #expect(notice.message == "A scan started before you answered. Clean again once it's done.")
    }

    @Test
    func `what was left alone comes a line each, and nothing left alone says nothing`() {
        let notice = CleanNotice.leftAlone(["Skipped DerivedData: Xcode is open.", "Couldn't remove ~/x."])
        #expect(notice?.title == "Some things were left alone")
        #expect(notice?.message == "Skipped DerivedData: Xcode is open.\nCouldn't remove ~/x.")
        #expect(CleanNotice.leftAlone([]) == nil)
    }

    @Test
    func `folders not put back are listed, still in the Trash, and none says nothing`() {
        let notice = CleanNotice.notPutBack(["~/a", "~/b"])
        #expect(notice?.title == "Some folders couldn't be put back")
        #expect(notice?.message.hasSuffix("They are still in the Trash:\n~/a\n~/b") == true)
        #expect(CleanNotice.notPutBack([]) == nil)
    }
}
