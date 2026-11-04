import Foundation
import Testing
@testable import DevSweepKit

@Suite("Cleaning parts of an item")
struct ItemPartsTests {
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

        let outcome = await engine.clean([.folder(atlas)], of: result, mode: .delete)
        #expect(outcome.cleaned == [.folder(atlas)])
        #expect(!home.exists(atlas))
        let folder = home.path(FakeHome.derivedData)
        for kept in ["Fieldwork-def", "CompilationCache.noindex", "ModuleCache.noindex", "SymbolCache.noindex"] {
            #expect(home.exists("\(folder)/\(kept)"), "\(kept)")
        }
        let breakdown = try #require(result.derivedData)
        let left = breakdown.removing(outcome.cleaned)
        #expect(left.totalKilobytes == breakdown.totalKilobytes - breakdown.kilobytes(of: .folder(atlas)))
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

        let outcome = await engine.clean([.folder(elsewhere), .folder(inside)], of: result, mode: .delete)
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

        let outcome = await engine.clean([.folder(atlas), .moduleCache], of: result, mode: .trash)
        #expect(outcome.cleaned == [.folder(atlas), .moduleCache])
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
        #expect(!ItemPart.folder("/x/DerivedData/Atlas-abc").needsXcodeClosed(in: .derivedData))
        for part in [ItemPart.compilationCache, .moduleCache, .other] {
            #expect(part.needsXcodeClosed(in: .derivedData))
        }
        #expect(!ItemPart.folder("/x/Workspace/Atlas/.build").needsXcodeClosed(in: .swiftpmBuilds))
        #expect(ItemPart.folder("/x/Xcode/iOS DeviceSupport/18.0").needsXcodeClosed(in: .deviceSupport))
    }

    /// Two packages with a `.build` folder each, of different sizes.
    func scannedBuilds(_ home: FakeHome, _ tools: FakeTools) async throws -> (Engine, ItemResult, String, String) {
        let atlas = "\(home.projects)/Atlas/.build", fieldwork = "\(home.projects)/Fieldwork/.build"
        home.touch("\(home.projects)/Atlas/Package.swift")
        home.touch("\(home.projects)/Fieldwork/Package.swift")
        home.writeZeros("\(atlas)/debug/blob", kilobytes: 256)
        home.writeZeros("\(fieldwork)/debug/blob", kilobytes: 64)
        let engine = try engine(home, tools)
        let result = try #require(await collect(engine).result(.swiftpmBuilds))
        let resolved = { (path: String) in try #require(result.paths.first { $0.hasSuffix(path) }) }
        return try (engine, result, resolved("/Atlas/.build"), resolved("/Fieldwork/.build"))
    }

    @Test
    func `the scan keeps each folder's size, and they add up to the item's`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let (_, result, atlas, fieldwork) = try await scannedBuilds(home, tools)
        let sizes = try #require(result.folderKilobytes)
        #expect(Set(sizes.keys) == Set(result.paths))
        #expect(sizes.values.reduce(0, +) == result.kilobytes)
        #expect(try #require(sizes[atlas]) > #require(sizes[fieldwork]))
    }

    @Test
    func `cleaning one build folder leaves the others, and Put Back brings it back`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let (engine, result, atlas, fieldwork) = try await scannedBuilds(home, tools)

        let outcome = await engine.clean([.folder(atlas)], of: result, mode: .trash)
        #expect(outcome.cleaned == [.folder(atlas)])
        #expect(!home.exists(atlas))
        #expect(home.exists(fieldwork))
        let left = result.removing(outcome.cleaned)
        #expect(left.paths == [fieldwork])
        #expect(left.kilobytes == result.kilobytes - result.kilobytes(of: .folder(atlas)))
        #expect(left.label == "SwiftPM .build folders (1)")

        let putBack = await engine.putBack(outcome.outcome)
        #expect(home.exists(atlas))
        #expect(left.restoring(outcome.restored(by: putBack), from: result) == result)
    }

    @Test
    func `a folder that isn't one of the item's is left alone`() async throws {
        let home = FakeHome(), tools = FakeTools(home: home)
        let (engine, result, atlas, _) = try await scannedBuilds(home, tools)
        let source = "\(FileSystem.dirname(atlas))/Sources"
        home.fill(source)

        let outcome = await engine.clean([.folder(source), .compilationCache], of: result, mode: .delete)
        #expect(!outcome.cleaned.contains(.folder(source)))
        #expect(outcome.outcome.removed.isEmpty)
        #expect(home.exists(source))
    }
}
