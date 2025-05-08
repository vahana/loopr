import Foundation
import AVKit

class VideoCacheManager {
    static let shared = VideoCacheManager()
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    // Cache TTL in seconds (7 days by default)
    var cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    
    private init() {
        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        cacheDirectory = URL(fileURLWithPath: cachePath).appendingPathComponent("VideoCache")
        createCacheDirectoryIfNeeded()
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    func cachedFileURL(for url: URL) -> URL {
        let filename = url.lastPathComponent
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    func isVideoCached(for url: URL) -> Bool {
        let cachedFile = cachedFileURL(for: url)
        return fileManager.fileExists(atPath: cachedFile.path)
    }
    
    func getCachedURL(for url: URL) -> URL? {
        if isVideoCached(for: url) {
            let cachedFile = cachedFileURL(for: url)
            
            // Check if cached file is too old
            if let attributes = try? fileManager.attributesOfItem(atPath: cachedFile.path),
               let modificationDate = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modificationDate) < cacheTTL {
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
        let cachedFile = cachedFileURL(for: url)
        
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
}
