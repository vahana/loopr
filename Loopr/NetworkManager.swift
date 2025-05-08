
import Foundation
import Network

class NetworkManager: ObservableObject {
    @Published var serverURL: URL?
    @Published var videos: [Video] = []
    @Published var isScanning = false
    @Published var error: String?
    
    // Mac's hostname or IP - you can set this manually or discover it
    var serverHost = "imac.local"
    var serverPort = 8080
    
    func scanForServer() {
        isScanning = true
        
        // Create a URL to test connection
        guard let url = URL(string: "http://\(serverHost):\(serverPort)/videos.json") else {
            error = "Invalid server URL"
            isScanning = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isScanning = false
                
                if let error = error {
                    self?.error = "Server connection error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, 
                      (200...299).contains(httpResponse.statusCode) else {
                    self?.error = "Server returned invalid response"
                    return
                }
                
                // Success - store the server URL
                self?.serverURL = URL(string: "http://\(self?.serverHost ?? ""):\(self?.serverPort ?? 8080)")
                self?.loadVideos()
            }
        }.resume()
    }
    
    func loadVideos() {
        guard let serverURL = serverURL else {
            error = "No server URL available"
            return
        }
        
        let videosURL = serverURL.appendingPathComponent("videos.json")
        
        URLSession.shared.dataTask(with: videosURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = "Failed to load videos: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.error = "No video data received"
                    return
                }
                
                do {
                    // Parse the video index JSON
                    let videoItems = try JSONDecoder().decode([VideoItem].self, from: data)
                    
                    // Convert to our Video model
                    self?.videos = videoItems.map { item in
                        let videoURL = serverURL.appendingPathComponent(item.path)
                        let thumbnailURL = item.thumbnail.map { serverURL.appendingPathComponent($0) }
                        
                        return Video(
                            title: item.title,
                            description: item.description,
                            thumbnailURL: thumbnailURL,
                            url: videoURL
                        )
                    }
                } catch {
                    self?.error = "Failed to parse videos: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    // Scan for Mac manually by IP range (optional)
    func scanLocalNetwork() {
        // Code to scan IP range would go here
        // This is more complex and requires Network framework
        // For simplicity, we're using manual host entry above
    }
}

// Model for parsing the video index JSON
struct VideoItem: Codable {
    let title: String
    let description: String
    let path: String
    let thumbnail: String?
    let duration: Double?
}
