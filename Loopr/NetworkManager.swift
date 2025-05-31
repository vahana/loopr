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
            loadOfflineVideos()
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isScanning = false
                
                if let error = error {
                    self?.error = "Server connection error: \(error.localizedDescription)"
                    // Load cached videos first, then sample videos
                    self?.loadOfflineVideos()
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    self?.error = "Server returned invalid response"
                    self?.loadOfflineVideos()
                    return
                }
                
                // Success - store the server URL
                self?.serverURL = URL(string: "http://\(self?.serverHost ?? ""):\(self?.serverPort ?? 8080)")
                self?.loadVideos()
            }
        }
        
        // Set a timeout for the connection
        task.resume()
        
        // Optional: Set a timeout to cancel the task if it takes too long
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.isScanning {
                task.cancel()
                self.isScanning = false
                self.error = "Connection timed out"
                self.loadOfflineVideos()
            }
        }
    }
    
    // New method to load offline videos (cached + sample)
    private func loadOfflineVideos() {
        var offlineVideos: [Video] = []
        
        // First, load cached videos
        let cachedVideos = loadCachedVideos()
        offlineVideos.append(contentsOf: cachedVideos)
        
        // If no cached videos, fall back to sample videos
        if cachedVideos.isEmpty {
            offlineVideos = getSampleVideos()
        }
        
        self.videos = offlineVideos
    }
    
    // Load videos from cache
    private func loadCachedVideos() -> [Video] {
        let cacheManager = VideoCacheManager.shared
        var cachedVideos: [Video] = []
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: cacheManager.cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in fileURLs {
                // Extract original filename from cached filename
                let filename = fileURL.lastPathComponent
                let components = filename.components(separatedBy: "_")
                let displayName = components.count > 1 ? String(components.dropFirst().joined(separator: "_")) : filename
                
                // Create Video object for cached file
                let video = Video(
                    title: displayName.replacingOccurrences(of: ".mp4", with: ""),
                    description: "Cached Video",
                    url: fileURL
                )
                cachedVideos.append(video)
            }
            
            // Sort by modification date (newest first)
            cachedVideos.sort { video1, video2 in
                guard let date1 = cacheManager.getLastPlayed(for: video1.url),
                      let date2 = cacheManager.getLastPlayed(for: video2.url) else {
                    return false
                }
                return date1 > date2
            }
            
        } catch {
            print("Error loading cached videos: \(error)")
        }
        
        return cachedVideos
    }
    
    private func getSampleVideos() -> [Video] {
        return [
            Video(
                title: "Big Buck Bunny",
                description: "A short animated film",
                thumbnailName: "bunny_thumbnail",
                url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
            )
            // Add more sample videos if needed
        ]
    }
    
    func loadSampleVideos() {
        self.videos = getSampleVideos()
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
    
    // New method for handling video URLs with caching
    func loadVideoWithCache(from url: URL, completion: @escaping (URL) -> Void) {
        // First check if caching is enabled
        if VideoCacheManager.shared.isCachingEnabled {
            // Check if video is cached
            if let cachedURL = VideoCacheManager.shared.getCachedURL(for: url) {
                print("Loading video from cache: \(cachedURL.lastPathComponent)")
                completion(cachedURL)
                return
            }
            
            // Not cached, download and cache
            print("Caching video: \(url.lastPathComponent)")
            VideoCacheManager.shared.cacheVideo(from: url) { cachedURL in
                if let cachedURL = cachedURL {
                    print("Video cached successfully: \(cachedURL.lastPathComponent)")
                    completion(cachedURL)
                } else {
                    print("Video caching failed, using original URL")
                    // Fallback to original URL if caching fails
                    completion(url)
                }
            }
        } else {
            // Caching is disabled, use original URL
            print("Video caching is disabled, using original URL")
            completion(url)
        }
    }
    
    // Add method to check if a specific video is cached
    func isVideoCached(video: Video) -> Bool {
        return VideoCacheManager.shared.isVideoCached(for: video.url)
    }
    
    // Add method to cache a specific video
    func cacheVideo(video: Video, completion: @escaping (Bool) -> Void) {
        VideoCacheManager.shared.cacheVideo(from: video.url) { cachedURL in
            completion(cachedURL != nil)
        }
    }
    
    // Add method to delete cache for a specific video
    func deleteCacheForVideo(video: Video) {
        let cachedURL = VideoCacheManager.shared.cachedFileURL(for: video.url)
        try? FileManager.default.removeItem(at: cachedURL)
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
