import SwiftUI
import AVKit

// View Model for the Settings View
class SettingsViewModel: ObservableObject {
    @Published var cachedVideos: [CachedVideoItem] = []
    @Published var isLoading = false
    @Published var totalCacheSize = "0 MB"
    @Published var isCachingEnabled = true
    
    private let cacheManager = VideoCacheManager.shared
    private let formatter = ByteCountFormatter()
    private let dateFormatter = DateFormatter()
    
    init() {
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        
        // Load saved preferences
        isCachingEnabled = UserDefaults.standard.bool(forKey: "videoCachingEnabled")
    }
    
    func toggleCaching(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "videoCachingEnabled")
        if !enabled {
            // Optionally clear cache when disabling
            // clearAllCache()
        }
    }
    
    func loadCachedVideos() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: self.cacheManager.cacheDirectory,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                var videos: [CachedVideoItem] = []
                var totalSize: Int64 = 0
                
                for url in fileURLs {
                    do {
                        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                        let fileSize = resourceValues.fileSize ?? 0
                        let modificationDate = resourceValues.contentModificationDate ?? Date()
                        
                        totalSize += Int64(fileSize)
                        
                        videos.append(CachedVideoItem(
                            filename: url.lastPathComponent,
                            url: url,
                            size: self.formatter.string(fromByteCount: Int64(fileSize)),
                            date: modificationDate
                        ))
                    } catch {
                        print("Error getting file info: \(error)")
                    }
                }
                
                // Sort by date, newest first
                videos.sort { $0.date > $1.date }
                
                DispatchQueue.main.async {
                    self.cachedVideos = videos
                    self.totalCacheSize = self.formatter.string(fromByteCount: totalSize)
                    self.isLoading = false
                }
                
            } catch {
                print("Error loading cached videos: \(error)")
                DispatchQueue.main.async {
                    self.cachedVideos = []
                    self.isLoading = false
                }
            }
        }
    }
    
    func deleteCache(for video: CachedVideoItem) {
        do {
            try FileManager.default.removeItem(at: video.url)
            
            // Update UI
            DispatchQueue.main.async {
                self.cachedVideos.removeAll { $0.id == video.id }
                self.updateTotalCacheSize()
            }
        } catch {
            print("Error deleting cache: \(error)")
        }
    }
    
    func clearAllCache() {
        cacheManager.clearCache()
        
        // Update UI
        DispatchQueue.main.async {
            self.cachedVideos = []
            self.totalCacheSize = "0 MB"
        }
    }
    
    private func updateTotalCacheSize() {
        var totalSize: Int64 = 0
        
        for video in cachedVideos {
            do {
                let resourceValues = try video.url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                print("Error getting file size: \(error)")
            }
        }
        
        totalCacheSize = formatter.string(fromByteCount: totalSize)
    }
    
    func formatDate(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }
}

// Preview provider
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(networkManager: NetworkManager())
    }
}
