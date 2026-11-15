import Testing
@testable import DevSweepApp

// The kit's clean results have no public initializers: these are made as
// the kit would make them.
@testable import DevSweepKit

@Suite("Parts clean")
struct PartsCleanTests {
    let before: ItemResult
    let project: String

    init() throws {
        self.before = try #require(sampleResults.first { $0.item == .derivedData })
        self.project = try #require(self.before.derivedData?.projects.first).folder
    }

    /// `parts` cleaned to the Trash, but for the folders in `failed`.
    func clean(_ parts: [ItemPart: [String]], failed: [String] = []) -> PartsClean {
        var outcome = CleanOutcome(item: .derivedData, mode: .trash)
        for folder in parts.values.flatMap(\.self) {
            if failed.contains(folder) {
                outcome.failed.append(folder)
            } else {
                outcome.removed.append(.init(original: folder, trashed: "/Trash/\(folder)"))
            }
        }
        return PartsClean(outcome: PartsCleanOutcome(outcome: outcome, paths: parts), before: self.before)
    }

    @Test
    func `a project cleaned on its own says what went, what it took and what is left`() {
        let clean = self.clean([.folder(self.project): [self.project]])
        #expect(clean.parts == [.folder(self.project)])
        #expect(clean.left == self.before.removing([.folder(self.project)]))
        #expect(clean.kilobytes == self.before.kilobytes(of: .folder(self.project)))
        #expect(clean.summary == "1 project")
        #expect(clean.canPutBack)
    }

    @Test
    func `a folder that failed takes nothing`() {
        let clean = self.clean([.folder(self.project): [self.project]], failed: [self.project])
        #expect(clean.parts.isEmpty)
        #expect(clean.left == self.before)
        #expect(clean.kilobytes == 0)
    }

    @Test
    func `putting it back makes the item whole again`() {
        let clean = self.clean([.folder(self.project): [self.project]])
        let putBack = PutBackOutcome(restored: [self.project], failed: [])
        #expect(clean.restoring(putBack, into: clean.left) == self.before)
    }
}
