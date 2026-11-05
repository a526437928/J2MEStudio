import Foundation

nonisolated struct StandaloneProfile: Codable, Sendable {
    let name: String
    let jarResource: String
    let screenWidth: Int
    let screenHeight: Int
    let fps: Int
    let render3dScale: Int
    var controls: PlayPreferences

    static func read(from url: URL) throws -> StandaloneProfile {
        let profile = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard !profile.name.isEmpty, profile.jarResource == URL(fileURLWithPath: profile.jarResource).lastPathComponent,
              profile.screenWidth > 0, profile.screenHeight > 0, profile.screenWidth <= 2048, profile.screenHeight <= 2048,
              [0, 15, 20, 30, 60].contains(profile.fps), [1, 2, 3].contains(profile.render3dScale) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return profile
    }
}
