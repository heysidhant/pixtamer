import Foundation
import PixtamerKit

enum Formatting {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "68% smaller" / "12% larger" / "Same size". Nil fraction → nil.
    static func savings(_ fraction: Double?) -> String? {
        guard let fraction else { return nil }
        let percent = Int((abs(fraction) * 100).rounded())
        if percent == 0 { return "Same size" }
        return fraction > 0 ? "\(percent)% smaller" : "\(percent)% larger"
    }

    /// Compact signed form for table cells: "−68%" / "+12%".
    static func signedPercent(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        if percent == 0 { return "±0%" }
        return percent > 0 ? "−\(percent)%" : "+\(-percent)%"
    }

    static func fraction(original: Int64, output: Int64) -> Double? {
        guard original > 0 else { return nil }
        return Double(original - output) / Double(original)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(seconds, seconds < 1 ? 0 : 1)) ?? "\(Int(seconds))s"
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}
