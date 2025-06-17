import SwiftUI
import AVKit

// View Model for the Settings View
class SettingsViewModel: ObservableObject {
    @Published var downloadedVideos: [CachedVideoItem] = []
    @Published var isLoading = false
    @Published var totalDownloadsSize = "0 MB"
    @Published var isDownloadsEnabled = true
    
    private let downloadManager = VideoDownloadManager.shared
    private let formatter = ByteCountFormatter()
    private let dateFormatter = DateFormatter()
    
    init() {
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        
        // Load saved preferences
        isDownloadsEnabled = UserDefaults.standard.bool(forKey: "videoDownloadsEnabled")
    }
    
    func toggleDownloads(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "videoDownloadsEnabled")
        if !enabled {
            // Optionally clear downloads when disabling
            // clearAllDownloads()
        }
    }
    
    func loadDownloadedVideos() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: self.downloadManager.downloadsDirectory,
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
                    self.downloadedVideos = videos
                    self.totalDownloadsSize = self.formatter.string(fromByteCount: totalSize)
                    self.isLoading = false
                }
                
            } catch {
                print("Error loading downloaded videos: \(error)")
                DispatchQueue.main.async {
                    self.downloadedVideos = []
                    self.isLoading = false
                }
            }
        }
    }
    
    func deleteDownload(for video: CachedVideoItem) {
        do {
            try FileManager.default.removeItem(at: video.url)
            
            // Update UI
            DispatchQueue.main.async {
                self.downloadedVideos.removeAll { $0.id == video.id }
                self.updateTotalDownloadsSize()
            }
        } catch {
            print("Error deleting download: \(error)")
        }
    }
    
    func clearAllDownloads() {
        downloadManager.clearAllDownloads()
        
        // Update UI
        DispatchQueue.main.async {
            self.downloadedVideos = []
            self.totalDownloadsSize = "0 MB"
        }
    }
    
    private func updateTotalDownloadsSize() {
        var totalSize: Int64 = 0
        
        for video in downloadedVideos {
            do {
                let resourceValues = try video.url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                print("Error getting file size: \(error)")
            }
        }
        
        totalDownloadsSize = formatter.string(fromByteCount: totalSize)
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