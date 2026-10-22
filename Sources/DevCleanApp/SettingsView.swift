import AppKit
import DevCleanKit
import SwiftUI

/// The Settings window: what to scan, how cleaning starts out, and when
/// something counts as unused. The command line keeps its own flags and
/// environment variables.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Folders", systemImage: "folder") { FolderSettings() }
            Tab("Items", systemImage: "checklist") { ItemSettings() }
        }
        .frame(width: 540)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = self.model.preferences
        Form {
            Section {
                Toggle("Scan when \(ProductInfo.name) opens", isOn: $preferences.scanOnLaunch)
                Picker("Cleaning", selection: $preferences.moveToTrash) {
                    Text("Moves to the Trash").tag(true)
                    Text("Deletes for good, after asking").tag(false)
                }
            } footer: {
                Text(
                    "Where cleaning starts out each time \(ProductInfo.name) opens; the window's checkbox changes it for one session.")
                    .settingsFooter()
            }
            Section {
                Stepper(value: $preferences.staleDays, in: Preferences.staleDaysRange, step: 1) {
                    LabeledContent(
                        "Flag as unused after",
                        value: preferences.staleDays == 1 ? "1 day" : "\(preferences.staleDays) days")
                }
            } footer: {
                Text(
                    "Simulator runtimes, system images and emulators untouched this long are flagged. They are only ever listed.")
                    .settingsFooter()
            }
            Section {
                Stepper(value: $preferences.derivedDataGrowthGigabytes, in: Preferences.growthRange, step: 1) {
                    LabeledContent(
                        "Notify when DerivedData grows by",
                        value: "\(preferences.derivedDataGrowthGigabytes) GB")
                }
            } footer: {
                Text(
                    "While \(ProductInfo.name) runs it scans again once a day, and says so when DerivedData grew by more than this since the scan before.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.moveToTrash) { _, moveToTrash in self.model.moveToTrash = moveToTrash }
    }
}

private struct FolderSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []

    var body: some View {
        let preferences = self.model.preferences
        Form {
            Section {
                List(selection: self.$selection) {
                    ForEach(preferences.projectFolders, id: \.self) { folder in
                        Label(folder, systemImage: "folder").tag(folder)
                    }
                }
                .frame(minHeight: 170)
                .accessibilityLabel("Project folders")
                HStack(spacing: 8) {
                    Button("Add Folder…", systemImage: "plus") { self.addFolders() }
                    Button("Remove", systemImage: "minus") {
                        preferences.projectFolders.removeAll(where: self.selection.contains)
                        self.selection = []
                    }
                    .disabled(self.selection.isEmpty)
                    Spacer()
                    Button("Use Defaults") { preferences.restoreDefaultProjectFolders() }
                        .disabled(preferences.usesDefaultProjectFolders)
                }
            } header: {
                Text("Project folders")
            } footer: {
                Text(self.footer).settingsFooter()
            }
        }
        .formStyle(.grouped)
    }

    private var footer: String {
        var text = "Searched for .build folders, Xcode build folders and Gradle build folders next to their projects. "
            + "Changes apply from the next scan."
        if !(ProcessInfo.processInfo.environment["DEVCLEAN_PROJECT_DIRS"] ?? "").isEmpty {
            text += " DEVCLEAN_PROJECT_DIRS is set, so DevClean searches those folders instead."
        }
        return text
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        let home = self.model.engine?.config.home ?? NSHomeDirectory()
        panel.directoryURL = URL(fileURLWithPath: home)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            self.model.preferences.addProjectFolder(url.path(percentEncoded: false).removingTrailingSlash, home: home)
        }
    }
}

private struct ItemSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let preferences = self.model.preferences
        Form {
            ForEach(Family.allCases) { family in
                Section(family.name) {
                    ForEach(family.items) { item in
                        Toggle(item.name, isOn: Binding(
                            get: { !preferences.skippedItems.contains(item) },
                            set: { scanned in
                                if scanned { preferences.skippedItems.remove(item) }
                                else { preferences.skippedItems.insert(item) }
                            }))
                            .help(item.whatHappens)
                    }
                }
            }
            Section {} footer: {
                Text(
                    "Items turned off are left out of the window's scans, from the next one. The command line has its own --skip.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }
}

extension Text {
    fileprivate func settingsFooter() -> some View {
        font(.callout).foregroundStyle(.muted).fixedSize(horizontal: false, vertical: true)
    }
}

extension String {
    fileprivate var removingTrailingSlash: String {
        count > 1 && hasSuffix("/") ? String(dropLast()) : self
    }
}
