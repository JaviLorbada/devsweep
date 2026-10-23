import Darwin
import Foundation

/// `YYYY-MM-DD` days, formatted with the C library so they match `plutil`,
/// `mdls` and `stat -t %Y-%m-%d` exactly.
public enum DayFormat {
    /// The day in UTC, as `plutil -extract ... raw` and `mdls` print dates.
    public static func utc(_ date: Date) -> String {
        var seconds = time_t(date.timeIntervalSince1970.rounded(.down))
        var parts = tm()
        gmtime_r(&seconds, &parts)
        return self.format(&parts)
    }

    /// The day in the local time zone, as `stat -f %Sm -t %Y-%m-%d` prints it.
    public static func local(secondsSince1970: Int) -> String {
        var seconds = time_t(secondsSince1970)
        var parts = tm()
        localtime_r(&seconds, &parts)
        return self.format(&parts)
    }

    private static func format(_ parts: inout tm) -> String {
        var buffer = [CChar](repeating: 0, count: 32)
        let count = strftime(&buffer, buffer.count, "%Y-%m-%d", &parts)
        return String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
