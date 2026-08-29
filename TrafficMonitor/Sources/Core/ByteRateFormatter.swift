import Foundation

public enum ByteRateFormatter {
    public static func string(from bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0 KB/s" }

        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = bytesPerSecond
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if value >= 100 || unitIndex == 0 {
            return "\(Int(value.rounded())) \(units[unitIndex])"
        }
        if value >= 10 {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
        return String(format: "%.2f %@", value, units[unitIndex])
    }

    public static func compactString(from bytesPerSecond: Double) -> String {
        string(from: bytesPerSecond).replacingOccurrences(of: "/s", with: "")
    }
}
