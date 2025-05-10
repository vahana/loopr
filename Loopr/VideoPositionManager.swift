import Foundation

class VideoPositionManager {
    static let shared = VideoPositionManager()
    
    private let userDefaults = UserDefaults.standard
    private let positionKey = "video_positions"
    
    private init() {}
    
    // Save position for a video URL
    func savePosition(_ position: Double, for videoURL: URL) {
        var positions = getPositions()
        positions[videoURL.absoluteString] = position
        userDefaults.set(positions, forKey: positionKey)
    }
    
    // Get saved position for a video URL
    func getPosition(for videoURL: URL) -> Double? {
        let positions = getPositions()
        return positions[videoURL.absoluteString]
    }
    
    // Clear position for a video URL
    func clearPosition(for videoURL: URL) {
        var positions = getPositions()
        positions.removeValue(forKey: videoURL.absoluteString)
        userDefaults.set(positions, forKey: positionKey)
    }
    
    // Get all saved positions
    private func getPositions() -> [String: Double] {
        return userDefaults.dictionary(forKey: positionKey) as? [String: Double] ?? [:]
    }
    
    // Clear all saved positions
    func clearAllPositions() {
        userDefaults.removeObject(forKey: positionKey)
    }
}
