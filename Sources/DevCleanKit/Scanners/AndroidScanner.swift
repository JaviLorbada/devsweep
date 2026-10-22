import Foundation

/// Android Studio installs; the SDK's system images, platforms, build tools
/// and other parts; emulators; and Gradle's shared caches. Listed, never
/// deleted.
///
/// Built like the item scanners: everything inside home passes the path
/// policy and is measured with the context's measurer, so a clean step can
/// take these paths later. Only a scan with `includeAndroid` runs it, which
/// the command line never asks for.
struct AndroidScanner: ListingScanner {
    func scan(in context: ScanContext) async -> AndroidReport {
        await scan(in: context, now: Date())
    }

    func scan(in context: ScanContext, now: Date) async -> AndroidReport {
        var found: [AndroidEntry] = studios(in: context)
        let sdk = context.existing(["\(context.home)/Library/Android/sdk"]).first
        if let sdk {
            found += sdkParts(in: sdk, context: context)
        }
        found += emulators(in: context)
        found += gradleCaches(in: context)

        // One measuring pass over everything, so the context can measure
        // several folders at once.
        let measured = await context.measure(found.map(\.path)) { _ in }
        for (index, measurement) in zip(found.indices, measured) {
            found[index].kilobytes = measurement.kilobytes
        }

        let emulators = found.filter { $0.kind == .emulator }
        var images = found.filter { $0.kind == .systemImage }
        // An image counts as used when an emulator on it was.
        for index in images.indices {
            let users = emulators.filter { emulatorUses($0, image: images[index], sdk: sdk) }
            images[index].emulatorCount = users.count
            images[index].lastUsed = ([images[index].lastUsed] + users.map(\.lastUsed)).compactMap { $0 }.max()
        }

        func largestFirst(_ kind: AndroidEntry.Kind, _ entries: [AndroidEntry]? = nil) -> [AndroidEntry] {
            (entries ?? found.filter { $0.kind == kind }).sorted {
                $0.kilobytes != $1.kilobytes ? $0.kilobytes > $1.kilobytes : $0.path.utf8.lexicographicallyPrecedes($1.path.utf8)
            }
        }
        return AndroidReport(
            studios: largestFirst(.studio),
            sdk: sdk,
            systemImages: largestFirst(.systemImage, images),
            platforms: largestFirst(.platform),
            buildTools: largestFirst(.buildTools),
            otherSDKParts: largestFirst(.sdkPart),
            emulators: largestFirst(.emulator),
            gradleCaches: largestFirst(.gradleCache)
        )
    }

    // MARK: Android Studio

    func studios(in context: ScanContext) -> [AndroidEntry] {
        var result: [AndroidEntry] = []
        for directory in context.config.applicationsDirectories where !directory.isEmpty {
            let folder = context.policy.expandTilde(directory)
            for name in FileSystem.globNames(folder) where FileSystem.matches(name, pattern: "Android Studio*.app") {
                let app = "\(folder)/\(name)"
                guard FileSystem.isDirectory(app), !FileSystem.isSymlink(app) else { continue }
                let info = "\(app)/Contents/Info.plist"
                let version = PropertyList.string(at: info, key: "CFBundleShortVersionString")
                result.append(AndroidEntry(
                    kind: .studio,
                    path: app,
                    title: [name.removingSuffix(".app"), version].compactMap { $0 }.joined(separator: " "),
                    detail: PropertyList.string(at: info, key: "CFBundleVersion") ?? "",
                    kilobytes: 0,
                    lastUsed: context.tools.lastUsedDates.lastUsedDate(of: app)
                ))
            }
        }
        return result
    }

    // MARK: SDK

    func sdkParts(in sdk: String, context: ScanContext) -> [AndroidEntry] {
        var result: [AndroidEntry] = []
        for name in FileSystem.globNames(sdk) {
            let path = "\(sdk)/\(name)"
            switch name {
            case "system-images":
                result += systemImages(in: path, context: context)
            case "platforms":
                for platform in safeChildren(of: path, context: context) {
                    let properties = Properties.read("\(platform)/source.properties")
                    let folder = FileSystem.basename(platform)
                    let title: String = if let version = properties["Platform.Version"], let level = properties["AndroidVersion.ApiLevel"] {
                        "Android \(version) (API \(level))"
                    } else {
                        folder
                    }
                    result.append(AndroidEntry(kind: .platform, path: platform, title: title, detail: folder, kilobytes: 0))
                }
            case "build-tools":
                for tools in safeChildren(of: path, context: context) {
                    result.append(AndroidEntry(kind: .buildTools, path: tools, title: "Build tools \(FileSystem.basename(tools))", kilobytes: 0))
                }
            default:
                guard let part = context.policy.safePath(path) else { continue }
                result.append(AndroidEntry(kind: .sdkPart, path: part, title: Self.sdkPartName(name), detail: name, kilobytes: 0))
            }
        }
        return result
    }

    /// `system-images/<api>/<tag>/<abi>`, one entry per ABI folder.
    func systemImages(in folder: String, context: ScanContext) -> [AndroidEntry] {
        var result: [AndroidEntry] = []
        for api in safeChildren(of: folder, context: context) {
            for tag in safeChildren(of: api, context: context) {
                for abi in safeChildren(of: tag, context: context) {
                    let properties = Properties.read("\(abi)/source.properties")
                    let level = properties["AndroidVersion.ApiLevel"] ?? FileSystem.basename(api).removingPrefix("android-")
                    // Several tags come as one list: "Google APIs PlayStore,Page Size 16KB".
                    let tagName = (properties["SystemImage.TagDisplay"] ?? FileSystem.basename(tag))
                        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
                    result.append(AndroidEntry(
                        kind: .systemImage,
                        path: abi,
                        title: "API \(level), \(tagName)",
                        detail: properties["SystemImage.Abi"] ?? FileSystem.basename(abi),
                        kilobytes: 0,
                        lastUsed: Self.date(FileSystem.modificationTime(abi))
                    ))
                }
            }
        }
        return result
    }

    static func sdkPartName(_ folder: String) -> String {
        switch folder {
        case "emulator": "Emulator"
        case "platform-tools": "Platform tools"
        case "cmdline-tools": "Command-line tools"
        case "sources": "Sources"
        case "ndk", "ndk-bundle": "NDK"
        case "cmake": "CMake"
        case "extras": "Extras"
        case "skins": "Device skins"
        case "fonts": "Fonts"
        case "licenses": "Licenses"
        case "patcher": "Patcher"
        case "tools": "SDK tools, old"
        default: folder
        }
    }

    // MARK: Emulators

    func emulators(in context: ScanContext) -> [AndroidEntry] {
        let folder = "\(context.home)/.android/avd"
        return safeChildren(of: folder, context: context).filter { $0.hasSuffix(".avd") }.map { avd in
            let config = Properties.read("\(avd)/config.ini")
            let name = FileSystem.basename(avd).removingSuffix(".avd")
            let target = config["target"].map { $0.removingPrefix("android-") }.map { "API \($0)" }
            return AndroidEntry(
                kind: .emulator,
                path: avd,
                title: config["avd.ini.displayname"] ?? name.replacingOccurrences(of: "_", with: " "),
                detail: [target, config["tag.display"]].compactMap { $0 }.joined(separator: ", "),
                kilobytes: 0,
                lastUsed: Self.date(Self.newestChange(in: avd))
            )
        }
    }

    /// An emulator's `image.sysdir.1` names its system image relative to the SDK.
    func emulatorUses(_ emulator: AndroidEntry, image: AndroidEntry, sdk: String?) -> Bool {
        guard let sdk, let sysdir = Properties.read("\(emulator.path)/config.ini")["image.sysdir.1"] else { return false }
        return "\(sdk)/\(sysdir.removingSuffix("/"))" == image.path
    }

    /// The newest modification time of a folder and what sits directly in it.
    /// Running an emulator rewrites its disk images, so this is when it last ran.
    static func newestChange(in folder: String) -> Int {
        FileSystem.childNames(folder).map { FileSystem.modificationTime("\(folder)/\($0)") }
            .reduce(FileSystem.modificationTime(folder), max)
    }

    // MARK: Gradle

    func gradleCaches(in context: ScanContext) -> [AndroidEntry] {
        safeChildren(of: "\(context.home)/.gradle", context: context).map { folder in
            let name = FileSystem.basename(folder)
            var detail = name
            if name == "wrapper" {
                let versions = FileSystem.globNames("\(folder)/dists").map {
                    $0.removingPrefix("gradle-").removingSuffix("-bin").removingSuffix("-all")
                }
                if !versions.isEmpty { detail = versions.joined(separator: ", ") }
            }
            return AndroidEntry(kind: .gradleCache, path: folder, title: Self.gradleFolderName(name), detail: detail, kilobytes: 0)
        }
    }

    static func gradleFolderName(_ folder: String) -> String {
        switch folder {
        case "caches": "Dependency and build caches"
        case "wrapper": "Gradle versions"
        case "daemon": "Daemon logs"
        case "jdks": "Downloaded JDKs"
        case "native": "Native libraries"
        case "build-scan-data": "Build scan data"
        case "kotlin-profile": "Kotlin build reports"
        case "nodejs": "Node.js downloads"
        case "android": "Android caches, old"
        default: folder
        }
    }

    // MARK: Helpers

    /// The folders in `folder` that pass the path policy, sorted.
    private func safeChildren(of folder: String, context: ScanContext) -> [String] {
        FileSystem.globNames(folder).compactMap { name in
            let path = "\(folder)/\(name)"
            guard FileSystem.isDirectory(path) else { return nil }
            return context.policy.safePath(path)
        }
    }

    private static func date(_ seconds: Int) -> Date? {
        seconds > 0 ? Date(timeIntervalSince1970: TimeInterval(seconds)) : nil
    }
}

/// `key=value` files: the SDK's `source.properties` and an emulator's `config.ini`.
enum Properties {
    static func read(_ path: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, values[key] == nil { values[key] = value }
        }
        return values
    }
}
