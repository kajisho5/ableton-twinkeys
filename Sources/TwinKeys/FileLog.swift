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
