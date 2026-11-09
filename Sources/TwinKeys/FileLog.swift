#if os(macOS)
import Foundation

/// Appends timestamped lines to ~/Library/Logs/TwinKeys/TwinKeys-YYYY-MM-DD.log.
final class FileLog {
    private let dir: URL
    private let queue = DispatchQueue(label: "TwinKeys.log", qos: .utility)
    private let dayFormat: DateFormatter
    private let timeFormat: ISO8601DateFormatter

    init(dir: URL) {
        self.dir = dir
        dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        timeFormat = ISO8601DateFormatter()
        timeFormat.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        prune(keepDays: 30)
    }

    /// Deletes log files older than `keepDays` days so the folder cannot grow without limit.
    private func prune(keepDays: Int) {
        let fm = FileManager.default
        let limit = Date().addingTimeInterval(-Double(keepDays) * 86_400)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in files where f.lastPathComponent.hasPrefix("TwinKeys-") && f.pathExtension == "log" {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if date < limit { try? fm.removeItem(at: f) }
        }
    }

    func write(_ message: String) {
        let now = Date()
        queue.async { [self] in
            let line = "\(timeFormat.string(from: now)) \(message)\n"
            let file = dir.appendingPathComponent("TwinKeys-\(dayFormat.string(from: now)).log")
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
    }
}
#endif
