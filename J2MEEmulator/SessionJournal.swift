import Foundation

/// A durable lifecycle record. A missing finish is evidence of interruption,
/// not proof of a native crash or a replacement for Apple's crash reports.
nonisolated enum SessionJournal {
    static func write(saveRoot: String, status: String, detail: String) throws {
        let url = URL(fileURLWithPath: saveRoot).appendingPathComponent("last-session.json")
        if status == "running", FileManager.default.fileExists(atPath: url.path) {
            let history = URL(fileURLWithPath: saveRoot).appendingPathComponent("Sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            let session = UUID().uuidString
            try FileManager.default.copyItem(at: url, to: history.appendingPathComponent(session + ".json"))
            let native = URL(fileURLWithPath: saveRoot).appendingPathComponent("last-run.log")
            if FileManager.default.fileExists(atPath: native.path) {
                try FileManager.default.copyItem(at: native, to: history.appendingPathComponent(session + ".log"))
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "status": status, "detail": detail,
            "time": ISO8601DateFormatter().string(from: Date())
        ], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
