/// Build folders in the project folders: `.build` next to a `Package.swift`,
/// `build` folders Xcode wrote, `build` folders next to a Gradle file, and
/// other languages' folders next to their project's file. Each is listed
/// only when git provably tracks nothing in it, and it holds no git
/// repository.
public struct ProjectBuildScanner: Scanner {
    public let item: Item
    let folderName: String
    let describe: String
    let qualifies: @Sendable (String) -> Bool
    /// Finds a git repository that keeps the folder.
    let repositories: RepositorySearch

    public func location(in context: ScanContext) async -> String {
        self.describe
    }

    public func collect(in context: ScanContext) async -> [String] {
        var result: [String] = []
        for folder in await context.projects.folders(named: self.folderName) {
            guard let real = context.policy.safePath(folder), qualifies(real) else {
                continue
            }
            if await GitTracking.isUntracked(
                real,
                environment: context.config.environment,
                git: context.tools.git,
                policy: context.policy,
                warn: context.warn)
            {
                result.append(real)
            }
        }
        return result
    }

    /// Lists and measures, one walk per folder. A folder holding a git
    /// repository is kept, with its size: left out with a warning, or for
    /// the app listed with the others.
    public func scan(in context: ScanContext, progress: @escaping @Sendable (Int64) -> Void) async -> ItemResult {
        let folders = await collect(in: context).sortedUniqueBytewise()
        let search = context.config.keepsFoldersWithRepositories ? self.repositories : nil
        let sizes = await context.measure(folders, search: search, progress: progress)
        let measured = Array(zip(folders, sizes))
        let kept = measured.compactMap { folder, measurement in
            measurement.repository.map {
                KeptFolder(path: folder, repository: $0, kilobytes: measurement.kilobytes)
            }
        }
        if context.config.listsKeptFolders {
            return await self.result(folders, measured: sizes, kept: kept, in: context)
        }
        for folder in kept {
            context.warn(self.warning(folder, policy: context.policy))
        }
        let listed = measured.filter { $0.1.repository == nil }
        return await self.result(listed.map(\.0), measured: listed.map(\.1), kept: kept, in: context)
    }

    /// Why a folder holding a git repository is kept.
    func warning(_ folder: KeptFolder, policy: PathPolicy) -> String {
        let reason = folder.repositoryInside.map { "it holds a git repository, \($0)" } ?? "it is a git repository"
        return "Skipped \(policy.tilde(folder.path)): \(reason)."
    }

    public static let swiftpm = ProjectBuildScanner(
        item: .swiftpmBuilds,
        folderName: ".build",
        describe: ".build next to a Package.swift, in project folders",
        qualifies: beside("Package.swift"),
        repositories: RepositorySearch(skipsPackageClones: true))

    public static let xcode = ProjectBuildScanner(
        item: .xcodeBuilds,
        folderName: "build",
        describe: "build with Xcode output next to a project or Package.swift, in project folders",
        qualifies: isXcodeBuild,
        repositories: RepositorySearch(skipsPackageClones: true))

    public static let gradle = ProjectBuildScanner(
        item: .gradleBuilds,
        folderName: "build",
        describe: "build next to a Gradle build file, in project folders",
        qualifies: isGradleBuild,
        repositories: RepositorySearch())

    // Other languages' folders of installed packages and build output, each
    // next to the file it comes back from.

    public static let cocoapods = ProjectBuildScanner(
        item: .cocoapodsPods,
        folderName: "Pods",
        describe: "Pods next to a Podfile.lock, in project folders",
        qualifies: beside("Podfile.lock"),
        repositories: RepositorySearch())

    public static let cargo = ProjectBuildScanner(
        item: .cargoBuilds,
        folderName: "target",
        describe: "target next to a Cargo.toml, in project folders",
        qualifies: beside("Cargo.toml"),
        repositories: RepositorySearch())

    public static let nodeModules = ProjectBuildScanner(
        item: .nodeModules,
        folderName: "node_modules",
        describe: "node_modules next to a package.json, in project folders",
        qualifies: beside("package.json"),
        repositories: RepositorySearch())

    /// Whether a file called `name` sits next to the folder.
    static func beside(_ name: String) -> @Sendable (String) -> Bool {
        { folder in FileSystem.isRegularFile("\(FileSystem.dirname(folder))/\(name)") }
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
        if self.isGradleBuild(folder) {
            return false
        }
        let parent = FileSystem.dirname(folder)
        let besideProject = FileSystem.isRegularFile("\(parent)/Package.swift")
            || self.hasChild(parent, matching: ["*.xcodeproj", "*.xcworkspace"])
        return besideProject
            && self.hasChild(
                folder,
                matching: ["XCBuildData", "*.build", "EagerLinkingTBDs", "*-iphoneos", "*-iphonesimulator"])
    }

    /// Whether any entry directly inside `folder`, of any kind, matches one of the patterns.
    static func hasChild(_ folder: String, matching patterns: [String]) -> Bool {
        FileSystem.childNames(folder).contains { name in
            patterns.contains { FileSystem.matches(name, pattern: $0) }
        }
    }
}
