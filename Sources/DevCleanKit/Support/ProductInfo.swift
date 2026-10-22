import Foundation

/// The product's names, in one place with `version.env`, so a new name is a
/// change to these two files.
public enum ProductInfo {
    /// The app's name, in the menu bar, the window and the text.
    public static let name = "DevClean"
    /// The command line tool's name, in its usage and messages.
    public static let cliName = "devclean"
    public static let bundleIdentifier = "com.javilorbada.devclean"
    /// The folder in `~/Library/Application Support` the app keeps its last scan in.
    public static let applicationSupportFolder = name
    /// The app's UserDefaults domain: its bundle's standard defaults.
    public static let defaultsSuite = bundleIdentifier

    /// The version the bundle was packaged with, from `version.env`.
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
