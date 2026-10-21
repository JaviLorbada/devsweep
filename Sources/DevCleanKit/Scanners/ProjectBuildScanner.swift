/// Build folders in the project folders: `.build` next to a `Package.swift`,
/// `build` folders Xcode wrote, and `build` folders next to a Gradle file.
/// Each is listed only when git provably tracks nothing in it.
public struct ProjectBuildScanner: Scanner {
    public let item: Item
    let folderName: String
    let describe: String
    let qualifies: @Sendable (String) -> Bool

    public func location(in context: ScanContext) async -> String {
        describe
    }

    public func collect(in context: ScanContext) async -> [String] {
        var result: [String] = []
        for folder in await context.projects.folders(named: folderName) {
            guard let real = context.policy.safePath(folder), qualifies(real) else { continue }
            if await GitTracking.isUntracked(
                real,
                environment: context.config.environment,
                git: context.tools.git,
                policy: context.policy,
                warn: context.warn
            ) {
                result.append(real)
            }
        }
        return result
    }

    public static let swiftpm = ProjectBuildScanner(
        item: .swiftpmBuilds,
        folderName: ".build",
        describe: ".build next to a Package.swift, in project folders",
        qualifies: isSwiftPMBuild
    )

    public static let xcode = ProjectBuildScanner(
        item: .xcodeBuilds,
        folderName: "build",
        describe: "build with Xcode output next to a project or Package.swift, in project folders",
        qualifies: isXcodeBuild
    )

    public static let gradle = ProjectBuildScanner(
        item: .gradleBuilds,
        folderName: "build",
        describe: "build next to a Gradle build file, in project folders",
        qualifies: isGradleBuild
    )

    static func isSwiftPMBuild(_ folder: String) -> Bool {
        FileSystem.isRegularFile("\(FileSystem.dirname(folder))/Package.swift")
    }

    static func isGradleBuild(_ folder: String) -> Bool {
        let parent = FileSystem.dirname(folder)
        return ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
            .contains { FileSystem.isRegularFile("\(parent)/\($0)") }
    }

    /// A build folder Xcode wrote (xcodebuild or the legacy build location): it
    /// sits next to a project, workspace or package, and holds Xcode's build
    /// output. A Gradle build folder never counts, so none is counted twice.
    static func isXcodeBuild(_ folder: String) -> Bool {
        if isGradleBuild(folder) { return false }
        let parent = FileSystem.dirname(folder)
        let besideProject = FileSystem.isRegularFile("\(parent)/Package.swift")
            || hasChild(parent, matching: ["*.xcodeproj", "*.xcworkspace"])
        return besideProject
            && hasChild(folder, matching: ["XCBuildData", "*.build", "EagerLinkingTBDs", "*-iphoneos", "*-iphonesimulator"])
    }

    /// Whether any entry directly inside `folder`, of any kind, matches one of the patterns.
    static func hasChild(_ folder: String, matching patterns: [String]) -> Bool {
        FileSystem.childNames(folder).contains { name in
            patterns.contains { FileSystem.matches(name, pattern: $0) }
        }
    }
}
