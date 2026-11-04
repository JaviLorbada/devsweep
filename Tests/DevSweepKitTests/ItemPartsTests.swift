import Foundation
import Testing
@testable import DevSweepKit

@Suite("Cleaning parts of DerivedData")
struct DerivedDataPartsTests {
    /// A DerivedData folder with both caches, two projects and one entry
    /// that is neither.
    func scanned(_ home: FakeHome, _ tools: FakeTools) async throws -> (Engine, ItemResult) {
        let folder = home.path(FakeHome.derivedData)
        home.fill("\(folder)/CompilationCache.noindex")
        home.fill("\(folder)/ModuleCache.noindex")
        home.fill("\(folder)/SymbolCache.noindex")
        home.makeDerivedData(
            "\(folder)/Atlas-abc",
            workspace: home.path("Workspace/Atlas/Atlas.xcodeproj"),
            lastAccessed: nil)
        home.makeDerivedData(
            "\(folder)/Fieldwork-def",
            workspace: home.path("Workspace/Fieldwork/Fieldwork.xcodeproj"),
            lastAccessed: nil)
        let engine = try engine(home, tools)
        return try (engine, #require(await collect(engine).result(.derivedData)))
    }

    func project(_ name: String, in result: ItemResult) throws -> String {
        try #require(result.derivedData?.projects.first { $0.folder.hasSuffix("/\(name)") }).folder
    }

    @Test
    func `cleaning one project leaves the other projects and the caches`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let (engine, result) = try await scanned(home, tools)
        let atlas = try project("Atlas-abc", in: result)

        let outcome = await engine.clean([.project(atlas)], of: result, mode: .delete)
        #expect(outcome.cleaned == [.project(atlas)])
        #expect(!home.exists(atlas))
        let folder = home.path(FakeHome.derivedData)
        for kept in ["Fieldwork-def", "CompilationCache.noindex", "ModuleCache.noindex", "SymbolCache.noindex"] {
            #expect(home.exists("\(folder)/\(kept)"), "\(kept)")
        }
        let breakdown = try #require(result.derivedData)
        let left = breakdown.removing(outcome.cleaned)
        #expect(left.totalKilobytes == breakdown.totalKilobytes - breakdown.kilobytes(of: .project(atlas)))
        #expect(try left.projects.map(\.folder) == [self.project("Fieldwork-def", in: result)])
    }

    @Test
    func `other is everything that is neither a shared cache nor a project`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let (engine, result) = try await scanned(home, tools)

        let outcome = await engine.clean([.other], of: result, mode: .delete)
        let folder = home.path(FakeHome.derivedData)
        #expect(outcome.cleaned == [.other])
        #expect(!home.exists("\(folder)/SymbolCache.noindex"))
        for kept in ["Atlas-abc", "Fieldwork-def", "CompilationCache.noindex", "ModuleCache.noindex"] {
            #expect(home.exists("\(folder)/\(kept)"), "\(kept)")
        }
    }

    @Test
    func `a project path that isn't directly in the scanned folder is left alone`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let (engine, result) = try await scanned(home, tools)
        let elsewhere = home.fill(home.path("Library/Caches/Keep"))
        let inside = try "\(project("Atlas-abc", in: result))/Build"
        home.fill(inside)

        let outcome = await engine.clean([.project(elsewhere), .project(inside)], of: result, mode: .delete)
        #expect(outcome.cleaned.isEmpty)
        #expect(outcome.outcome.removed.isEmpty)
        #expect(home.exists(elsewhere))
        #expect(home.exists(inside))
    }

    @Test
    func `parts moved to the Trash come back with Put Back, and the breakdown with them`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let (engine, result) = try await scanned(home, tools)
        let atlas = try project("Atlas-abc", in: result)
        let breakdown = try #require(result.derivedData)

        let outcome = await engine.clean([.project(atlas), .moduleCache], of: result, mode: .trash)
        #expect(outcome.cleaned == [.project(atlas), .moduleCache])
        #expect(outcome.outcome.canPutBack)
        let left = breakdown.removing(outcome.cleaned)

        let putBack = await engine.putBack(outcome.outcome)
        let restored = outcome.restored(by: putBack)
        #expect(restored == outcome.cleaned)
        #expect(home.exists(atlas))
        #expect(left.restoring(restored, from: breakdown) == breakdown)
    }

    @Test
    func `only a project's own folder can go while Xcode is open`() {
        #expect(!DerivedDataPart.project("/x/DerivedData/Atlas-abc").needsXcodeClosed)
        for part in [DerivedDataPart.compilationCache, .moduleCache, .other] {
            #expect(part.needsXcodeClosed)
        }
    }
}
