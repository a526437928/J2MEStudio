import Foundation
import CoreGraphics

@main enum PreferencesTests {
    static func main() throws {
        var checks = 0
        func require(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: label, code: 1) }; checks += 1
        }
        for area in [CGRect(x: 8, y: 44, width: 330, height: 430), CGRect(x: 180, y: 44, width: 300, height: 280)] {
            for canvas in [CGSize(width: 101, height: 80), CGSize(width: 240, height: 320), CGSize(width: 480, height: 800)] {
                for density: CGFloat in [1, 2, 3] {
                    for mode in PlayPreferences.Scaling.allCases {
                        let frame = PlayGeometry.screen(in: area, canvas: canvas, displayScale: density, mode: mode)
                        try require(area.insetBy(dx: -0.01, dy: -0.01).contains(frame), "Screen containment: \(area) \(canvas) \(density) \(mode) -> \(frame)")
                        try require(abs(frame.width/frame.height - canvas.width/canvas.height) < 0.0001, "Preserve aspect ratio")
                        let scale = frame.width * density / canvas.width
                        if mode == .integer && scale >= 1 { try require(abs(scale - scale.rounded()) < 0.0001, "Integer physical pixels") }
                        if mode == .original { try require(scale <= 1.0001, "Original physical pixels") }
                    }
                }
            }
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = PlayPreferenceStore(url: temp.appendingPathComponent("Configurations/test.json"))
        var preferences = PlayPreferences(); preferences.orientation = .portrait; preferences.scaling = .integer
        preferences.controls["portrait.joystick"] = ControlPlacement(x: 0.2, y: 0.8)
        preferences.keys["portrait.53"] = ControlPlacement(x: 0.5, y: 0.6, scale: 0.8)
        try store.save(preferences)
        let restored = try store.load()
        try require(restored.orientation == .portrait && restored.scaling == .integer && restored.keys["portrait.53"]?.scale == 0.8, "Persist per-game controls and scaling")
        preferences.opacity = -100; preferences.keyScale = 300; preferences.normalize()
        try require(preferences.opacity == 0.3 && preferences.keyScale == 1.25, "Clamp user-edited values")
        let save = temp.appendingPathComponent("Saves/A")
        let rms = save.appendingPathComponent("rms")
        try FileManager.default.createDirectory(at: rms, withIntermediateDirectories: true)
        let record = rms.appendingPathComponent("record")
        try Data("one".utf8).write(to: record)
        let backups = RMSSnapshots(saveRoot: save)
        _ = try backups.create()
        try Data("two".utf8).write(to: record); _ = try backups.create()
        try Data("three".utf8).write(to: record); try backups.restoreLatest()
        try require(try String(contentsOf: record, encoding: .utf8) == "two", "Restore the selected snapshot and first preserve current data")
        let other = temp.appendingPathComponent("Saves/B/rms")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: other.appendingPathComponent("record"))
        for _ in 0..<5 { _ = try backups.create() }
        let count = try FileManager.default.contentsOfDirectory(atPath: temp.appendingPathComponent("Backups/A").path).filter { !$0.hasPrefix(".") }.count
        try require(count == 3, "Keep three RMS snapshots")
        try require(try String(contentsOf: other.appendingPathComponent("record"), encoding: .utf8) == "other", "Never touch another game's save")
        print("PASS: \(checks) display/preferences/RMS backup checks")
    }
}
