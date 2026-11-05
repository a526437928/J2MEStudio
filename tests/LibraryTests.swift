import Foundation

@main enum LibraryTests {
    static var checks = 0
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw NSError(domain: "LibraryTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
    }
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let validate = JARMetadata.validate
        for n in ["empty.jar", "short.jar", "truncated.jar", "missing-class.jar", "empty-deflate.jar", "oversize-entry.jar", "stored-mismatch.jar", "wrong-magic.jar"] {
            do { try validate(fixtures.appendingPathComponent(n)); throw NSError(domain: "Accepted invalid JAR", code: 1) }
            catch GameLibraryError.invalidMIDlet { checks += 1 }
        }
        let a = fixtures.appendingPathComponent("A/游戏.jar")
        let b = fixtures.appendingPathComponent("B/游戏.jar")
        try require(JARMetadata.read(from: a.path)?.midletName == "中文诊断甲", "Chinese manifest")
        let library = GameLibrary(documents: temp.appendingPathComponent("main"))
        let first = try library.importGame(from: a, validate: validate)
        let second = try library.importGame(from: b, validate: validate)
        try require(first.id != second.id, "Same filename must not overwrite")
        let duplicate = try library.importGame(from: a, validate: validate)
        try require(duplicate.id == first.id && library.games.count == 2, "Exact-content deduplication")
        let reopened = GameLibrary(documents: library.documents)
        try reopened.load()
        try require(reopened.games.map(\.id) == library.games.map(\.id), "Stable IDs after reopening")
        for record in [first, second] {
            try fm.createDirectory(at: library.saveURL(for: record), withIntermediateDirectories: true)
            try Data(record.sha256.utf8).write(to: library.saveURL(for: record).appendingPathComponent("rms-test"))
        }
        try fm.removeItem(at: library.jarURL(for: second))
        let restored = try library.importGame(from: b, validate: validate)
        try require(restored.id == second.id, "Re-import must reconnect the existing save identity")
        try library.clearData(for: first)
        try require(fm.fileExists(atPath: library.saveURL(for: second).appendingPathComponent("rms-test").path), "Clear must preserve other games")
        try library.delete(first)
        try require(library.games.count == 1 && fm.fileExists(atPath: library.jarURL(for: second).path), "Delete must preserve other JARs")
        try require(fm.fileExists(atPath: a.path), "Imported source must be preserved")
        for i in 0..<100 {
            _ = try library.importGame(from: fixtures.appendingPathComponent("many/\(i).JAR"), validate: validate)
        }
        try require(library.games.count == 101, "No artificial 64/100-game cap; uppercase extension")

        let legacy = GameLibrary(documents: temp.appendingPathComponent("legacy"))
        try legacy.load()
        for (source, name) in [(a, "天神.jar"), (b, "战魂.jar"), (fixtures.appendingPathComponent("many/0.JAR"), "unique.jar")] {
            try fm.copyItem(at: source, to: legacy.documents.appendingPathComponent("games/" + name))
        }
        for key in ["__", "unique"] {
            let save = legacy.documents.appendingPathComponent("Games Data/" + key)
            try fm.createDirectory(at: save, withIntermediateDirectories: true)
            try Data("old-save".utf8).write(to: save.appendingPathComponent("original"))
        }
        let notices = try legacy.adoptLegacyFiles(validate: validate)
        // identical bytes deduplicate; use the distinct colliding records for migration checks.
        try require(!notices.isEmpty, "Ambiguous legacy saves must be reported")
        try require(fm.fileExists(atPath: legacy.documents.appendingPathComponent("Games Data/__/original").path), "Ambiguous originals must remain")
        try require(legacy.games.contains { $0.migrationNotice != nil }, "Persist ambiguous ownership notice")
        let unique = legacy.games.first { $0.fileName == "unique.jar" }!
        try require(fm.fileExists(atPath: legacy.saveURL(for: unique).appendingPathComponent("original").path), "Unambiguous save must be copied")
        try require(fm.fileExists(atPath: legacy.documents.appendingPathComponent("Games Data/unique/original").path), "Keep the original migration backup")

        let rollback = GameLibrary(documents: temp.appendingPathComponent("rollback"))
        try rollback.load()
        try fm.createDirectory(at: rollback.documents.appendingPathComponent("library.json"), withIntermediateDirectories: false)
        do {
            _ = try rollback.importGame(from: a, validate: validate)
            throw NSError(domain: "Expected write failure", code: 1)
        } catch {
            try require(rollback.games.isEmpty, "Failed write must not change live index")
            let files = try fm.contentsOfDirectory(atPath: rollback.documents.appendingPathComponent("games").path)
            try require(files.isEmpty, "Failed write must roll back its new JAR")
        }
        let broken = GameLibrary(documents: temp.appendingPathComponent("broken"))
        try fm.createDirectory(at: broken.documents, withIntermediateDirectories: true)
        let badIndex = broken.documents.appendingPathComponent("library.json")
        try Data("not json".utf8).write(to: badIndex)
        do { try broken.load(); throw NSError(domain: "Accepted damaged index", code: 1) }
        catch GameLibraryError.invalidLibrary { checks += 1 }
        let unchanged = try String(contentsOf: badIndex, encoding: .utf8)
        try require(unchanged == "not json", "Corrupt index must never reset silently")
        print("PASS: \(checks) Swift library/ZIP regression checks")
    }
}
