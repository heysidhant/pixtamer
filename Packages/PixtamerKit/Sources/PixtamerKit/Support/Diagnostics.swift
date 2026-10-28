import Foundation

/// Plain-text report users can copy into a bug report. Contains versions, format support and
/// error codes. Never contains image data; home-directory paths are redacted.
public enum Diagnostics {
    public static func report(
        appVersion: String,
        build: String,
        capabilities: FormatCapabilities,
        lastSummary: BatchSummary?,
        recentFailures: [ExportFailure]
    ) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        var lines = [
            "Pixtamer \(appVersion) (\(build))",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(arch) · \(ProcessInfo.processInfo.activeProcessorCount) cores",
            "Parallel export jobs: \(BatchExporter.defaultConcurrency)",
            "",
            "Output formats:",
        ]
        for probe in capabilities.probes {
            lines.append("  \(probe.format.displayName): \(probe.available ? "available" : "unavailable") — \(probe.encoderName); \(probe.detail)")
        }
        let inputs = capabilities.readableTypeIdentifiers.compactMap { FormatCapabilities.supportedInputTypes[$0] }.sorted()
        lines.append("Input formats: \(inputs.joined(separator: ", "))")
        if let s = lastSummary {
            lines += [
                "",
                "Last export: \(s.writtenCount) written, \(s.skippedCount) skipped, \(s.failedCount) failed, \(s.cancelledCount) cancelled",
                "  bytes: \(s.originalBytes) original → \(s.outputBytes) output",
            ]
        }
        if !recentFailures.isEmpty {
            lines.append("")
            lines.append("Recent errors:")
            var counts: [ExportFailure.Code: Int] = [:]
            for failure in recentFailures { counts[failure.code, default: 0] += 1 }
            for (code, count) in counts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let example = recentFailures.first { $0.code == code }?.message ?? ""
                lines.append("  \(code.rawValue) ×\(count): \(redact(example))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Replaces the user's home directory and `/Users/<name>` prefixes with `~`.
    public static func redact(_ text: String) -> String {
        var result = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if let regex = try? NSRegularExpression(pattern: "/Users/[^/\\s]+") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "~")
        }
        return result
    }
}
