// J2ME Studio additions, Apache-2.0.
import Foundation
import CryptoKit

nonisolated struct GameRecord: Codable, Sendable, Equatable {
    let id: UUID
    let fileName: String
    let sha256: String
    let importedAt: Date
    var legacySettingsKey: String?
    var migrationNotice: String?
}

nonisolated enum GameLibraryError: LocalizedError {
    case invalidMIDlet, invalidLibrary, missingGame
    var errorDescription: String? {
        switch self {
        case .invalidMIDlet: return "文件不是有效的 J2ME MIDlet JAR，或缺少入口类。"
        case .invalidLibrary: return "游戏库索引损坏。原文件已保留，请先备份 Documents 再排查。"
        case .missingGame: return "游戏文件已被移走或删除，请重新导入。"
        }
    }
}

/// All access is serialized by the caller's library queue. No UIKit or JVM state.
nonisolated final class GameLibrary: @unchecked Sendable {
    private struct Index: Codable { var version = 1; var games: [GameRecord] = [] }
    let documents: URL
    private let fm = FileManager.default
    private var index = Index()
    private var loaded = false
    var games: [GameRecord] { index.games }
    private var indexURL: URL { documents.appendingPathComponent("library.json") }
    private var gameDirectory: URL { documents.appendingPathComponent("games", isDirectory: true) }

    init(documents: URL) { self.documents = documents }

    func jarURL(for game: GameRecord) -> URL {
        gameDirectory.appendingPathComponent(game.id.uuidString + ".jar")
    }

    func saveURL(for game: GameRecord) -> URL {
        documents.appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent(game.id.uuidString, isDirectory: true)
    }

    func load() throws {
        guard !loaded else { return }
        try fm.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: indexURL.path) {
            do {
                index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
                guard index.version == 1, Set(index.games.map(\.id)).count == index.games.count else {
                    throw GameLibraryError.invalidLibrary
                }
            } catch { throw GameLibraryError.invalidLibrary }
        }
        loaded = true
    }

    private func persist(_ candidate: Index) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(candidate).write(to: indexURL, options: .atomic)
        index = candidate
    }

    private func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func importGame(from source: URL, validate: (URL) throws -> Void) throws -> GameRecord {
        try load()
        guard source.pathExtension.lowercased() == "jar",
              try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw GameLibraryError.invalidMIDlet
        }
        try validate(source)
        let hash = try digest(source)
        if let existing = index.games.first(where: { $0.sha256 == hash }) {
            if !fm.fileExists(atPath: jarURL(for: existing).path) {
                try fm.copyItem(at: source, to: jarURL(for: existing))
            }
            return existing
        }
        // UUID file paths never contain the user's filename or overwrite another game.
        let game = GameRecord(id: UUID(), fileName: source.lastPathComponent, sha256: hash, importedAt: Date())
        let destination = jarURL(for: game)
        try fm.copyItem(at: source, to: destination)
        do {
            var candidate = index
            candidate.games.append(game)
            try persist(candidate)
        } catch {
            try? fm.removeItem(at: destination) // Only this transaction's newly generated file.
            throw error
        }
        return game
    }

    static func legacyKey(_ filename: String) -> String {
        URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    /// Preserve old JARs and save folders; never guess ownership when names collide.
    func adoptLegacyFiles(validate: (URL) throws -> Void) throws -> [String] {
        try load()
        let managed = Set(index.games.map { jarURL(for: $0).standardizedFileURL.path })
        let files = try [gameDirectory, documents].flatMap {
            try fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.isRegularFileKey])
        }.filter { $0.pathExtension.lowercased() == "jar" && !managed.contains($0.standardizedFileURL.path) }
        let groups = Dictionary(grouping: files, by: { Self.legacyKey($0.lastPathComponent) })
        var notices: [String] = []
        for source in files.sorted(by: { $0.path < $1.path }) {
            do {
                let game = try importGame(from: source, validate: validate)
                let key = Self.legacyKey(source.lastPathComponent)
                if let position = index.games.firstIndex(where: { $0.id == game.id }), index.games[position].legacySettingsKey == nil {
                    var candidate = index
                    let ambiguous = groups[key, default: []].count > 1 || index.games.contains {
                        $0.id != game.id && Self.legacyKey($0.fileName) == key
                    }
                    let old = documents.appendingPathComponent("Games Data", isDirectory: true).appendingPathComponent(key)
                    let target = saveURL(for: game)
                    if !ambiguous {
                        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: target.path) {
                            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try fm.copyItem(at: old, to: target)
                        }
                        candidate.games[position].legacySettingsKey = key
                    } else {
                        candidate.games[position].migrationNotice = "旧版存档名称冲突，未自动归属。原件保留在 Games Data，请备份后手动恢复。"
                        notices.append(source.lastPathComponent + "：旧存档归属不明确，已保留原件。")
                    }
                    try persist(candidate)
                }
                let backup = documents.appendingPathComponent("Import Backups", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: backup.appendingPathComponent(source.lastPathComponent))
            } catch { notices.append(source.lastPathComponent + "：" + error.localizedDescription) }
        }
        return notices
    }

    func clearData(for game: GameRecord) throws {
        let url = saveURL(for: game)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    func delete(_ game: GameRecord) throws {
        guard index.games.contains(where: { $0.id == game.id }) else { throw GameLibraryError.missingGame }
        // Stage before changing the index, so failed index writes can roll back.
        let trash = documents.appendingPathComponent(".deleting-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        var moved: [(URL, URL)] = []
        do {
            for source in [jarURL(for: game), saveURL(for: game)] where fm.fileExists(atPath: source.path) {
                let target = trash.appendingPathComponent(source.lastPathComponent)
                try fm.moveItem(at: source, to: target)
                moved.append((source, target))
            }
            var candidate = index
            candidate.games.removeAll { $0.id == game.id }
            try persist(candidate)
        } catch {
            for (source, target) in moved.reversed() { try? fm.moveItem(at: target, to: source) }
            throw error
        }
        try fm.removeItem(at: trash)
    }
}
