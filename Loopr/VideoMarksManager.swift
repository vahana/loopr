import Foundation

// Manager class to handle persistence of video marks
class VideoMarksManager {
    static let shared = VideoMarksManager()
    
    private let userDefaults = UserDefaults.standard
    private let marksKeyPrefix = "VideoMarks_"
    
    private init() {}
    
    // Get marks for a specific video
    func getMarks(for videoURL: URL) -> [Double] {
        let key = marksKey(for: videoURL)
        if let marks = userDefaults.array(forKey: key) as? [Double] {
            return marks
        }
        return []
    }
    
    // Save marks for a specific video
    func saveMarks(_ marks: [Double], for videoURL: URL) {
        let key = marksKey(for: videoURL)
        userDefaults.set(marks, forKey: key)
    }
    
    // Clear marks for a specific video
    func clearMarks(for videoURL: URL) {
        let key = marksKey(for: videoURL)
        userDefaults.removeObject(forKey: key)
    }
    
    // Generate a unique key for each video URL
    private func marksKey(for videoURL: URL) -> String {
        return marksKeyPrefix + videoURL.absoluteString.replacingOccurrences(of: "/", with: "_")
    }
}
