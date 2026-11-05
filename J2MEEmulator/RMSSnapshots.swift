import Foundation

nonisolated struct RMSSnapshots {
    let saveRoot: URL
    private var directory: URL {
        saveRoot.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Backups").appendingPathComponent(saveRoot.lastPathComponent)
    }

    @discardableResult func create() throws -> URL? {
        let fm = FileManager.default
        let rms = saveRoot.appendingPathComponent("rms")
        guard fm.fileExists(atPath: rms.path) else { return nil }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let completed = try fm.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".") }
        let next = (completed.compactMap { Int64($0.prefix(20)) }.max() ?? 0) + 1
        let name = String(format: "%020lld", next) + "-" + UUID().uuidString
        let staging = directory.appendingPathComponent(".pending-" + name)
        let destination = directory.appendingPathComponent(name)
        do { try fm.copyItem(at: rms, to: staging); try fm.moveItem(at: staging, to: destination) }
        catch { try? fm.removeItem(at: staging); throw error }
        // Retain the newest three completed RMS snapshots, not a game-count cap.
        let copies = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in copies.dropFirst(3) { try fm.removeItem(at: old) }
        return destination
    }

    func restoreLatest() throws {
        let fm = FileManager.default
        let copies = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let latest = copies.first else { throw CocoaError(.fileNoSuchFile) }
        // Preserve the chosen recovery point before backing up the current state.
        let staging = saveRoot.appendingPathComponent("restore-" + UUID().uuidString)
        try fm.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        try fm.copyItem(at: latest, to: staging)
        do {
            _ = try create()
            let rms = saveRoot.appendingPathComponent("rms")
            let old = saveRoot.appendingPathComponent("rms-before-restore-" + UUID().uuidString)
            if fm.fileExists(atPath: rms.path) { try fm.moveItem(at: rms, to: old) }
            do { try fm.moveItem(at: staging, to: rms) }
            catch { if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: rms) }; throw error }
            if fm.fileExists(atPath: old.path) { try fm.removeItem(at: old) }
        } catch { try? fm.removeItem(at: staging); throw error }
    }
}
