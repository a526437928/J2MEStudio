import Foundation
import CoreGraphics

nonisolated struct ControlPlacement: Codable, Sendable {
    var x: Double
    var y: Double
    var scale: Double = 1
}

nonisolated struct PlayPreferences: Codable, Sendable {
    enum Orientation: String, Codable, CaseIterable, Sendable { case automatic, portrait, landscape }
    enum Scaling: String, Codable, CaseIterable, Sendable { case fit, integer, original }
    enum DirectionMode: String, Codable, CaseIterable, Sendable { case numericDirections, navigation, legacyNumeric }
    var orientation: Orientation = .automatic
    var scaling: Scaling = .fit
    var directionMode: DirectionMode = .numericDirections
    var keyScale: Double = 1
    var opacity: Double = 0.9
    var controls: [String: ControlPlacement] = [:]
    var keys: [String: ControlPlacement] = [:]

    private enum CodingKeys: String, CodingKey { case orientation, scaling, directionMode, keyScale, opacity, controls, keys }
    init() { }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        orientation = try values.decodeIfPresent(Orientation.self, forKey: .orientation) ?? .automatic
        scaling = try values.decodeIfPresent(Scaling.self, forKey: .scaling) ?? .fit
        directionMode = try values.decodeIfPresent(DirectionMode.self, forKey: .directionMode) ?? .numericDirections
        keyScale = try values.decodeIfPresent(Double.self, forKey: .keyScale) ?? 1
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.9
        controls = try values.decodeIfPresent([String: ControlPlacement].self, forKey: .controls) ?? [:]
        keys = try values.decodeIfPresent([String: ControlPlacement].self, forKey: .keys) ?? [:]
    }

    mutating func normalize() {
        keyScale = keyScale.isFinite ? min(1.25, max(0.65, keyScale)) : 1
        opacity = opacity.isFinite ? min(1, max(0.3, opacity)) : 0.9
        for key in Array(controls.keys) { controls[key] = Self.normalized(controls[key]!) }
        for key in Array(keys.keys) { keys[key] = Self.normalized(keys[key]!) }
    }

    private static func normalized(_ p: ControlPlacement) -> ControlPlacement {
        ControlPlacement(x: p.x.isFinite ? min(1, max(0, p.x)) : 0.5,
                         y: p.y.isFinite ? min(1, max(0, p.y)) : 0.5,
                         scale: p.scale.isFinite ? min(1.4, max(0.6, p.scale)) : 1)
    }
}

nonisolated enum JoystickMapping {
    private static let numeric: [Set<Int32>] = [[54], [54, 56], [56], [56, 52], [52], [52, 50], [50], [50, 54]]
    private static let navigation: [Set<Int32>] = [[-4], [-4, -2], [-2], [-2, -3], [-3], [-3, -1], [-1], [-1, -4]]
    private static let legacy: [Set<Int32>] = [[54], [57], [56], [55], [52], [49], [50], [51]]
    /// Clockwise sectors starting at right, matching atan2 in UIKit coordinates.
    static func codes(sector: Int, mode: PlayPreferences.DirectionMode) -> Set<Int32> {
        guard (0..<8).contains(sector) else { return [] }
        switch mode {
        case .numericDirections:
            return numeric[sector]
        case .navigation:
            return navigation[sector]
        case .legacyNumeric:
            return legacy[sector]
        }
    }
}

nonisolated struct JoystickKeyState {
    private(set) var held: Set<Int32> = []
    mutating func transition(to next: Set<Int32>) -> (pressed: [Int32], released: [Int32]) {
        let change = (pressed: next.subtracting(held).sorted(), released: held.subtracting(next).sorted())
        held = next
        return change
    }
}

nonisolated struct PlayPreferenceStore {
    let url: URL
    func load() throws -> PlayPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return PlayPreferences() }
        var value = try JSONDecoder().decode(PlayPreferences.self, from: Data(contentsOf: url))
        value.normalize()
        return value
    }
    func save(_ input: PlayPreferences) throws {
        var value = input; value.normalize()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

nonisolated enum PlayGeometry {
    /// Scale is measured in physical display pixels per logical J2ME pixel.
    static func screen(in area: CGRect, canvas: CGSize, displayScale: CGFloat, mode: PlayPreferences.Scaling) -> CGRect {
        guard canvas.width > 0, canvas.height > 0, area.width > 0, area.height > 0, displayScale > 0 else { return .zero }
        let fit = min(area.width * displayScale / canvas.width, area.height * displayScale / canvas.height)
        let physical: CGFloat
        switch mode {
        case .fit: physical = fit
        case .integer: physical = fit >= 1 ? floor(fit) : fit
        case .original: physical = min(1, fit)
        }
        let size = CGSize(width: canvas.width * physical / displayScale, height: canvas.height * physical / displayScale)
        // Floating-point fit widths can be one ULP wider than the area; a raw
        // floor then shifts the left edge by a whole physical pixel.
        let frame = CGRect(x: floor((area.midX - size.width / 2) * displayScale + 0.000001) / displayScale,
                           y: floor((area.midY - size.height / 2) * displayScale + 0.000001) / displayScale,
                           width: size.width, height: size.height)
        return clamp(frame, to: area)
    }

    static func clamp(_ frame: CGRect, to area: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
        return CGRect(x: min(max(frame.minX, area.minX), area.maxX - size.width),
                      y: min(max(frame.minY, area.minY), area.maxY - size.height), width: size.width, height: size.height)
    }
}
