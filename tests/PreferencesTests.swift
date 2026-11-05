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
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as! [String: Any]
        oldJSON.removeValue(forKey: "directionMode")
        let migrated = try JSONDecoder().decode(PlayPreferences.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        try require(migrated.directionMode == .numericDirections && migrated.keys["portrait.53"]?.scale == 0.8 && migrated.controls["portrait.joystick"]?.x == 0.2 && migrated.orientation == .portrait && migrated.scaling == .integer, "Migrate 0.4.1 settings without losing layout")
        preferences.directionMode = .legacyNumeric; try store.save(preferences)
        try require(try store.load().directionMode == .legacyNumeric, "Persist per-game legacy joystick option")
        try require(JoystickMapping.codes(sector: 5, mode: .numericDirections) == Set([50, 52]), "Upper-left holds 2 and 4 instead of skill 1")
        let legacyCodes: [Int32] = [54, 57, 56, 55, 52, 49, 50, 51]
        for sector in 0..<8 {
            let codes = JoystickMapping.codes(sector: sector, mode: .numericDirections)
            try require(codes.isSubset(of: Set([50, 52, 54, 56])) && codes.count == (sector % 2 == 0 ? 1 : 2), "Every numeric diagonal is a directional chord")
            let navigation = JoystickMapping.codes(sector: sector, mode: .navigation)
            try require(navigation.isSubset(of: Set([-1, -2, -3, -4])) && navigation.count == codes.count, "Independent navigation preserves diagonal chords")
            try require(JoystickMapping.codes(sector: sector, mode: .legacyNumeric) == Set([legacyCodes[sector]]), "Preserve original eight-way mode")
        }
        var held = JoystickKeyState()
        let first = held.transition(to: JoystickMapping.codes(sector: 5, mode: .numericDirections))
        try require(first.pressed == [50, 52] && first.released.isEmpty, "Diagonal presses both directions")
        let unchanged = held.transition(to: [50, 52])
        try require(unchanged.pressed.isEmpty && unchanged.released.isEmpty, "Stationary thumb does not repeat key-down")
        let up = held.transition(to: [50])
        try require(up.pressed.isEmpty && up.released == [52], "Diagonal to up keeps up held without repressing")
        let cancelled = held.transition(to: [])
        try require(cancelled.released == [50] && held.held.isEmpty, "Cancellation releases remaining directions")
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
