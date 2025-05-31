import Foundation

// Manager class to handle persistence of video marks using files
class VideoMarksManager {
    static let shared = VideoMarksManager()
    
    private init() {}
    
    // Get marks for a specific video from .marks file
    func getMarks(for videoURL: URL) -> [Double] {
        let marksURL = videoURL.appendingPathExtension("marks")
        
        do {
            let marksData = try String(contentsOf: marksURL, encoding: .utf8)
            return marksData.components(separatedBy: "\n").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        } catch {
            return []
        }
    }
    
    // Save marks for a specific video to .marks file
    func saveMarks(_ marks: [Double], for videoURL: URL) {
        let marksURL = videoURL.appendingPathExtension("marks")
        let marksData = marks.map { String($0) }.joined(separator: "\n")
        
        do {
            try marksData.write(to: marksURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving marks to file: \(error)")
        }
    }
    
    // Clear marks for a specific video
    func clearMarks(for videoURL: URL) {
        let marksURL = videoURL.appendingPathExtension("marks")
        try? FileManager.default.removeItem(at: marksURL)
    }
}
