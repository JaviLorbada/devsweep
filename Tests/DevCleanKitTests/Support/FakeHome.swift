import Darwin
import Foundation
@testable import DevCleanKit

/// A temp folder per test holding a fake home folder, a projects folder in it,
/// and room for things outside home. Removed when the test lets go of it.
final class FakeHome: @unchecked Sendable {
    /// The temp folder, unresolved, under `/var/folders`, which is itself a
    /// symlink, so every test also exercises home resolution.
    let root: String
    let home: String
    let projects: String

    static let derivedData = "Library/Developer/Xcode/DerivedData"
    static let iosDeviceSupport = "Library/Developer/Xcode/iOS DeviceSupport"
    static let deviceInstalls =
        "Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas"

    init() {
        let base = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        root = (base.hasSuffix("/") ? base : base + "/") + "devclean-tests-\(UUID().uuidString)"
        home = "\(root)/home"
        projects = "\(home)/Workspace"
        try! FileManager.default.createDirectory(atPath: projects, withIntermediateDirectories: true)
    }

    deinit {
        precondition(root.contains("/devclean-tests-"), "refusing to remove \(root)")
        try? FileManager.default.removeItem(atPath: root)
    }

    /// `home/<relative>`
    func path(_ relative: String) -> String { "\(home)/\(relative)" }

    /// `<temp>/<relative>`, outside home.
    func outside(_ relative: String) -> String { "\(root)/\(relative)" }

    /// Creates a folder with a file in it, so it has a size.
    @discardableResult
    func fill(_ path: String) -> String {
        mkdir(path)
        FileManager.default.createFile(atPath: "\(path)/file", contents: Data("data\n".utf8))
        return path
    }

    func mkdir(_ path: String) {
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func touch(_ path: String) {
        mkdir(FileSystem.dirname(path))
        FileManager.default.createFile(atPath: path, contents: Data())
    }

    func write(_ path: String, _ contents: String) {
        mkdir(FileSystem.dirname(path))
        FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
    }

    /// Writes `kilobytes` of zeros, so the file has a known allocated size.
    func writeZeros(_ path: String, kilobytes: Int) {
        mkdir(FileSystem.dirname(path))
        FileManager.default.createFile(atPath: path, contents: Data(count: kilobytes * 1024))
    }

    func symlink(_ target: String, at path: String) {
        mkdir(FileSystem.dirname(path))
        try! FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    /// Sets a folder's modification time, like `touch -t`.
    func setModified(_ path: String, _ date: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmm"
        let seconds = Int(formatter.date(from: date)!.timeIntervalSince1970)
        var times = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
        utimes(path, &times)
    }

    /// Creates a build folder with the output xcodebuild leaves behind.
    func fillXcodeBuild(_ path: String) {
        fill("\(path)/App.build")
        mkdir("\(path)/XCBuildData")
    }

    /// Creates a fake Xcode app.
    func makeXcode(_ path: String, version: String, build: String) {
        write("\(path)/Contents/Info.plist", Self.plist("<key>CFBundleShortVersionString</key><string>\(version)</string>"))
        write("\(path)/Contents/version.plist", Self.plist("<key>ProductBuildVersion</key><string>\(build)</string>"))
    }

    /// Creates a Device Support folder modified at a `touch -t` time.
    func makeDeviceSupport(_ path: String, modified: String = "202601010000") {
        fill(path)
        setModified(path, modified)
    }

    /// Creates a DerivedData project folder.
    func makeDerivedData(_ folder: String, workspace: String, lastAccessed: String?) {
        fill(folder)
        let date = lastAccessed.map { "<key>LastAccessedDate</key><date>\($0)</date>" } ?? ""
        write("\(folder)/info.plist", Self.plist("\(date)<key>WorkspacePath</key><string>\(workspace)</string>"))
    }

    static func plist(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\(body)</dict></plist>\n"
    }

    func exists(_ path: String) -> Bool { FileSystem.existsOrIsSymlink(path) }
    func isDirectory(_ path: String) -> Bool { FileSystem.isDirectory(path) }
    func isFile(_ path: String) -> Bool { FileSystem.isRegularFile(path) }
    func isSymlink(_ path: String) -> Bool { FileSystem.isSymlink(path) }

    /// Runs git in a folder, for repositories the tests set up.
    func git(_ arguments: [String], environment: [String: String] = [:]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try! process.run()
        process.waitUntilExit()
    }

    /// The environment the bats suite sets up: this home, its Workspace as the
    /// only project folder, its Applications as the only place for Xcodes.
    var environment: [String: String] {
        [
            "HOME": home,
            "DEVCLEAN_PROJECT_DIRS": projects,
            "DEVCLEAN_APPLICATIONS_DIRS": path("Applications"),
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        ]
    }
}
