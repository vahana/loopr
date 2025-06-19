import Foundation
import AVKit

class VideoDownloadManager {
    static let shared = VideoDownloadManager()
    
    let downloadsDirectory: URL
    private let fileManager = FileManager.default
    
    // UserDefaults key for downloads enabled setting
    private let downloadsEnabledKey = "videoDownloadsEnabled"
    
    // Check if downloads are enabled in user settings
    var isDownloadsEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: downloadsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: downloadsEnabledKey)
        }
    }
    
    private init() {
        // Use Caches directory which is writable on tvOS
        let cachesPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        downloadsDirectory = URL(fileURLWithPath: cachesPath).appendingPathComponent("VideoDownloads")
        createDownloadsDirectoryIfNeeded()
        
        // Set default downloads to enabled if it hasn't been set yet
        if !UserDefaults.standard.contains(key: downloadsEnabledKey) {
            UserDefaults.standard.set(true, forKey: downloadsEnabledKey)
        }
    }
    
    private func createDownloadsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: downloadsDirectory.path) {
            do {
                try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Created downloads directory: \(downloadsDirectory.path)")
            } catch {
                print("Failed to create downloads directory: \(error)")
            }
        }
    }
    
    func downloadedFileURL(for url: URL) -> URL {
        // Create a unique filename based on the URL to avoid collisions
        let urlHash = url.absoluteString.hash
        let filename = "\(abs(urlHash))_\(url.lastPathComponent)"
        return downloadsDirectory.appendingPathComponent(filename)
    }
    
    func isVideoDownloaded(for url: URL) -> Bool {
        let downloadedFile = downloadedFileURL(for: url)
        return fileManager.fileExists(atPath: downloadedFile.path)
    }
    
    func getDownloadedURL(for url: URL) -> URL? {
        // Skip if downloads are disabled
        if !isDownloadsEnabled {
            return nil
        }
        
        if isVideoDownloaded(for: url) {
            let downloadedFile = downloadedFileURL(for: url)
            
            // Verify file exists and is readable
            guard fileManager.fileExists(atPath: downloadedFile.path) else {
                return nil
            }
            
            // Check file size to ensure it's not corrupted
            do {
                let attributes = try fileManager.attributesOfItem(atPath: downloadedFile.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                if fileSize == 0 {
                    // File is empty, remove it
                    try? fileManager.removeItem(at: downloadedFile)
                    return nil
                }
            } catch {
                // Can't read file attributes, remove it
                try? fileManager.removeItem(at: downloadedFile)
                return nil
            }
            
            // Update last access time to keep track of recently used files
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: downloadedFile.path)
            
            return downloadedFile
        }
        return nil
    }
    
    func verifyVideoFile(at url: URL) -> Bool {
        // Check if file exists
        guard fileManager.fileExists(atPath: url.path) else { return false }
        
        // Check file size
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            if fileSize < 1024 { // File too small to be a valid video
                return false
            }
        } catch {
            return false
        }
        
        // Quick AVAsset validation
        let asset = AVAsset(url: url)
        return asset.isReadable
    }
    
    func downloadVideo(from url: URL, completion: @escaping (URL?) -> Void) {
        // Skip downloading if disabled
        if !isDownloadsEnabled {
            completion(url)
            return
        }
        
        let downloadedFile = downloadedFileURL(for: url)
        
        let downloadTask = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            do {
                // Ensure downloads directory exists
                self.createDownloadsDirectoryIfNeeded()
                
                // Remove existing file if it exists
                if self.fileManager.fileExists(atPath: downloadedFile.path) {
                    try self.fileManager.removeItem(at: downloadedFile)
                }
                
                // Move downloaded file to downloads directory
                try self.fileManager.moveItem(at: tempURL, to: downloadedFile)
                
                // Verify the downloaded file is valid
                if !self.verifyVideoFile(at: downloadedFile) {
                    try? self.fileManager.removeItem(at: downloadedFile)
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    completion(downloadedFile)
                }
            } catch {
                print("Download error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        downloadTask.resume()
    }
    
    func clearAllDownloads() {
        try? fileManager.removeItem(at: downloadsDirectory)
        createDownloadsDirectoryIfNeeded()
    }
    
    func calculateDownloadsSize() -> UInt64 {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: downloadsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: UInt64 = 0
        
        for fileURL in fileURLs {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    // Use overflow-safe addition
                    let fileSizeUInt64 = UInt64(max(0, fileSize))
                    if totalSize <= UInt64.max - fileSizeUInt64 {
                        totalSize += fileSizeUInt64
                    } else {
                        // If we would overflow, just return max value
                        print("Downloads size calculation would overflow, returning max")
                        return UInt64.max
                    }
                }
            } catch {
                print("Error calculating size: \(error)")
            }
        }
        
        return totalSize
    }
    
    func deleteDownload(for url: URL) {
        let downloadedFile = downloadedFileURL(for: url)
        try? fileManager.removeItem(at: downloadedFile)
    }
    
    func updateLastPlayed(for url: URL) {
        let timestamp = Date().timeIntervalSince1970
        
        // Get the existing dictionary or create a new one
        var lastPlayed = UserDefaults.standard.dictionary(forKey: "videoLastPlayed") as? [String: Double] ?? [:]
        
        // Use the URL string as key
        let key = url.absoluteString
        lastPlayed[key] = timestamp
        
        // Save back to UserDefaults
        UserDefaults.standard.set(lastPlayed, forKey: "videoLastPlayed")
    }

    // Get when a video was last played (returns nil if never played)
    func getLastPlayed(for url: URL) -> Date? {
        guard let lastPlayed = UserDefaults.standard.dictionary(forKey: "videoLastPlayed") as? [String: Double] else {
            return nil
        }
        
        let key = url.absoluteString
        guard let timestamp = lastPlayed[key] else {
            return nil
        }
        
        return Date(timeIntervalSince1970: timestamp)
    }
}

// Extension to check if UserDefaults contains a key
extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}