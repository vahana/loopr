import Foundation
import Network

class NetworkManager: ObservableObject {
    @Published var serverURL: URL?
    @Published var videos: [Video] = []
    @Published var isScanning = false
    @Published var error: String?
    
    var serverHost = "imac.local"
    var serverPort = 8080
    
    func scanForServer() {
        isScanning = true
        
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
                    self?.loadOfflineVideos()
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    self?.error = "Server returned invalid response"
                    self?.loadOfflineVideos()
                    return
                }
                
                self?.serverURL = URL(string: "http://\(self?.serverHost ?? ""):\(self?.serverPort ?? 8080)")
                self?.loadVideos()
            }
        }
        
        task.resume()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.isScanning {
                task.cancel()
                self.isScanning = false
                self.error = "Connection timed out"
                self.loadOfflineVideos()
            }
        }
    }
    
    private func loadOfflineVideos() {
        var offlineVideos: [Video] = []
        
        let cachedVideos = loadCachedVideos()
        offlineVideos.append(contentsOf: cachedVideos)
        
        let documentsVideos = loadDocumentsVideos()
        offlineVideos.append(contentsOf: documentsVideos)
        
        let uniqueVideos = Dictionary(grouping: offlineVideos, by: { $0.title }).compactMap { $1.first }
        
        if uniqueVideos.isEmpty {
            offlineVideos = getSampleVideos()
        } else {
            offlineVideos = uniqueVideos
        }
        
        self.videos = offlineVideos
    }
    
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
                let filename = fileURL.lastPathComponent
                let components = filename.components(separatedBy: "_")
                let displayName = components.count > 1 ? String(components.dropFirst().joined(separator: "_")) : filename
                
                let video = Video(
                    title: displayName.replacingOccurrences(of: ".mp4", with: ""),
                    description: "Cached Video",
                    url: fileURL
                )
                cachedVideos.append(video)
            }
            
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
    
    private func loadDocumentsVideos() -> [Video] {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            return fileURLs.compactMap { url in
                guard url.pathExtension.lowercased() == "mp4" else { return nil }
                
                return Video(
                    title: url.deletingPathExtension().lastPathComponent,
                    description: "Downloaded Video",
                    url: url
                )
            }
        } catch {
            return []
        }
    }
    
    private func getSampleVideos() -> [Video] {
        return [
            Video(
                title: "Big Buck Bunny",
                description: "A short animated film",
                thumbnailName: "bunny_thumbnail",
                url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
            )
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
                    let videoItems = try JSONDecoder().decode([VideoItem].self, from: data)
                    
                    // Store filename to title mapping for migration
                    var titleMapping: [String: String] = [:]
                    for item in videoItems {
                        let filename = URL(string: item.path)?.lastPathComponent ?? item.path
                        titleMapping[filename] = item.title
                    }
                    UserDefaults.standard.set(titleMapping, forKey: "videoTitleMapping")
                    
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
    
    func loadVideoWithCache(from url: URL, completion: @escaping (URL) -> Void) {
        if VideoCacheManager.shared.isCachingEnabled {
            if let cachedURL = VideoCacheManager.shared.getCachedURL(for: url) {
                completion(cachedURL)
                return
            }
            
            VideoCacheManager.shared.cacheVideo(from: url) { cachedURL in
                if let cachedURL = cachedURL {
                    completion(cachedURL)
                } else {
                    completion(url)
                }
            }
        } else {
            completion(url)
        }
    }
    
    func isVideoCached(video: Video) -> Bool {
        return VideoCacheManager.shared.isVideoCached(for: video.url)
    }
    
    func cacheVideo(video: Video, completion: @escaping (Bool) -> Void) {
        VideoCacheManager.shared.cacheVideo(from: video.url) { cachedURL in
            completion(cachedURL != nil)
        }
    }
    
    func deleteCacheForVideo(video: Video) {
        let cachedURL = VideoCacheManager.shared.cachedFileURL(for: video.url)
        try? FileManager.default.removeItem(at: cachedURL)
    }
    
    func scanLocalNetwork() {
        // Implementation for local network scanning if needed
    }
}

struct VideoItem: Codable {
    let title: String
    let description: String
    let path: String
    let thumbnail: String?
    let duration: Double?
}
