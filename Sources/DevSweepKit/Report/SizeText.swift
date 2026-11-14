import Foundation

/// Sizes as Finder and System Settings write them: in thousands, rounded.
/// The app, the report and the bash script all write them this way, so the
/// numbers match the Mac's and each other.
public enum SizeText {
    /// Kilobytes as the kit measures them: 1024 bytes each, as `du -k` counts.
    public static func of(kilobytes: Int64) -> String {
        self.of(bytes: kilobytes * 1024)
    }

    /// "356.6 GB", "105 MB", "16 KB". A unit takes over where the one below
    /// would round to 1000.
    public static func of(bytes: Int64) -> String {
        let bytes = max(0, bytes)
        if bytes >= 999_500_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
        if bytes >= 999_500 {
            return "\((bytes + 500_000) / 1_000_000) MB"
        }
        return "\((bytes + 500) / 1000) KB"
    }
}
