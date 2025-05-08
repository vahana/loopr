import SwiftUI
import AVKit

struct Video: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let thumbnailName: String?
    let thumbnailURL: URL?
    let url: URL
    
    // For local videos (backward compatibility)
    init(title: String, description: String, thumbnailName: String, url: URL) {
        self.title = title
        self.description = description
        self.thumbnailName = thumbnailName
        self.thumbnailURL = nil
        self.url = url
    }
    
    // For network videos
    init(title: String, description: String, thumbnailURL: URL? = nil, url: URL) {
        self.title = title
        self.description = description
        self.thumbnailName = nil
        self.thumbnailURL = thumbnailURL
        self.url = url
    }
}
