import Foundation
import AVKit

class VideoCacheManager {
    static let shared = VideoCacheManager()
    
    // Make cacheDirectory accessible for the settings view
    let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    // Cache TTL in seconds (7 days by default)
    var cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    
    // Cache size limit in bytes (1GB by default)
    var cacheSizeLimit: UInt64 = 1024 * 1024 * 1024
    
    // UserDefaults key for caching enabled setting
    private let cachingEnabledKey = "videoCachingEnabled"
    
    // Check if caching is enabled in user settings
    var isCachingEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: cachingEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: cachingEnabledKey)
        }
    }
    
    private init() {
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        cacheDirectory = URL(fileURLWithPath: cachePath).appendingPathComponent("VideoCache")
        createCacheDirectoryIfNeeded()
        
        // Set default caching to enabled if it hasn't been set yet
        if !UserDefaults.standard.contains(key: cachingEnabledKey) {
            UserDefaults.standard.set(true, forKey: cachingEnabledKey)
        }
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    func cachedFileURL(for url: URL) -> URL {
        // Create a unique filename based on the URL to avoid collisions
        let urlHash = url.absoluteString.hash
        let filename = "\(abs(urlHash))_\(url.lastPathComponent)"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    func isVideoCached(for url: URL) -> Bool {
        let cachedFile = cachedFileURL(for: url)
        return fileManager.fileExists(atPath: cachedFile.path)
    }
    
    func getCachedURL(for url: URL) -> URL? {
        // Skip cache if caching is disabled
        if !isCachingEnabled {
            return nil
        }
        
        if isVideoCached(for: url) {
            let cachedFile = cachedFileURL(for: url)
            
            // Verify file exists and is readable
            guard fileManager.fileExists(atPath: cachedFile.path) else {
                return nil
            }
            
            // Check file size to ensure it's not corrupted
            do {
                let attributes = try fileManager.attributesOfItem(atPath: cachedFile.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                if fileSize == 0 {
                    // File is empty, remove it
                    try? fileManager.removeItem(at: cachedFile)
                    return nil
                }
            } catch {
                // Can't read file attributes, remove it
                try? fileManager.removeItem(at: cachedFile)
                return nil
            }
            
            // Check if cached file is too old
            if let attributes = try? fileManager.attributesOfItem(atPath: cachedFile.path),
               let modificationDate = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modificationDate) < cacheTTL {
                
                // Update last access time to keep track of recently used files
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: cachedFile.path)
                
                return cachedFile
            } else {
                // Delete expired cache file
                try? fileManager.removeItem(at: cachedFile)
                return nil
            }
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
    
    func cacheVideo(from url: URL, completion: @escaping (URL?) -> Void) {
        // Skip caching if disabled
        if !isCachingEnabled {
            completion(url)
            return
        }
        
        let cachedFile = cachedFileURL(for: url)
        
        // Check if we need to free up space
        Task {
            await self.enforceStorageLimits()
        }
        
        let downloadTask = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            do {
                // Remove existing file if it exists
                if self.fileManager.fileExists(atPath: cachedFile.path) {
                    try self.fileManager.removeItem(at: cachedFile)
                }
                
                // Move downloaded file to cache
                try self.fileManager.moveItem(at: tempURL, to: cachedFile)
                
                // Verify the cached file is valid
                if !self.verifyVideoFile(at: cachedFile) {
                    try? self.fileManager.removeItem(at: cachedFile)
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    completion(cachedFile)
                }
            } catch {
                print("Caching error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        downloadTask.resume()
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        createCacheDirectoryIfNeeded()
    }
    
    func cleanExpiredCache() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let currentDate = Date()
        
        for fileURL in fileURLs {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modificationDate = attributes[.modificationDate] as? Date else {
                continue
            }
            
            if currentDate.timeIntervalSince(modificationDate) > cacheTTL {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    func calculateCacheSize() -> UInt64 {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
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
                        print("Cache size calculation would overflow, returning max")
                        return UInt64.max
                    }
                }
            } catch {
                print("Error calculating size: \(error)")
            }
        }
        
        return totalSize
    }
    
    // Enforce storage limits by removing least recently used files
    private func enforceStorageLimits() async {
        let currentSize = calculateCacheSize()
        
        // If we're under the limit, no need to clean up
        if currentSize < cacheSizeLimit {
            return
        }
        
        // Calculate target size safely (75% of limit)
        let targetSize: UInt64
        if cacheSizeLimit <= UInt64.max / 4 {
            targetSize = (cacheSizeLimit * 3) / 4
        } else {
            // Prevent overflow in calculation
            targetSize = cacheSizeLimit - (cacheSizeLimit / 4)
        }
        
        print("Cache size \(currentSize) exceeds limit \(cacheSizeLimit), cleaning to \(targetSize)")
        
        // Get all cached files with their modification dates
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        // Create array of (URL, date, size) tuples to sort
        var files: [(url: URL, date: Date, size: UInt64)] = []
        
        for fileURL in fileURLs {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                if let date = resourceValues.contentModificationDate,
                   let size = resourceValues.fileSize {
                    let sizeUInt64 = UInt64(max(0, size))
                    files.append((fileURL, date, sizeUInt64))
                }
            } catch {
                print("Error getting file attributes: \(error)")
            }
        }
        
        // Sort by date (oldest first)
        files.sort { $0.date < $1.date }
        
        // Calculate how much we need to free up safely
        var sizeToFree: UInt64 = 0
        if currentSize > targetSize {
            sizeToFree = currentSize - targetSize
        }
        
        print("Need to free up \(sizeToFree) bytes")
        
        // Remove files until we're under the target
        var freedSize: UInt64 = 0
        for file in files {
            if freedSize >= sizeToFree {
                break
            }
            
            do {
                try fileManager.removeItem(at: file.url)
                print("Removed cache file: \(file.url.lastPathComponent) (\(file.size) bytes)")
                
                // Safely add to freed size
                if freedSize <= UInt64.max - file.size {
                    freedSize += file.size
                } else {
                    freedSize = UInt64.max
                    break
                }
            } catch {
                print("Error removing cache file: \(error)")
            }
        }
        
        print("Cache cleanup complete. Freed \(freedSize) bytes")
    }
    
    func deleteCache(for url: URL) {
        let cachedFile = cachedFileURL(for: url)
        try? fileManager.removeItem(at: cachedFile)
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
