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
                    totalSize += UInt64(fileSize)
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
                    files.append((fileURL, date, UInt64(size)))
                }
            } catch {
                print("Error getting file attributes: \(error)")
            }
        }
        
        // Sort by date (oldest first)
        files.sort { $0.date < $1.date }
        
        // Remove files until we're under the limit
        var sizeToFree = currentSize - (cacheSizeLimit * 3 / 4) // Free up to 75% of limit
        
        for file in files {
            if sizeToFree <= 0 {
                break
            }
            
            do {
                try fileManager.removeItem(at: file.url)
                sizeToFree -= file.size
            } catch {
                print("Error removing cache file: \(error)")
            }
        }
    }
    
    func deleteCache(for url: URL) {
        try? fileManager.removeItem(at: url)
    }
}

// Extension to check if UserDefaults contains a key
extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}
