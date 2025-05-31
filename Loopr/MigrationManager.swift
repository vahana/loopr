//
//  MigrationManager.swift
//  Loopr
//
//  Created by vahan on 2025-05-31.
//


import Foundation

/// Temporary migration manager - DELETE THIS FILE after migration is complete
class MigrationManager {
    static let shared = MigrationManager()    
    private init() {}
    
    
    func migrateCachedFiles() async {
        let cacheManager = VideoCacheManager.shared
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: cacheManager.cacheDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            print("Migration: Found \(fileURLs.count) files to check")
            
            for fileURL in fileURLs {
                let filename = fileURL.lastPathComponent
                
                if filename.hasSuffix(".marks") {
                    continue
                }
                
                print("Migration: Checking file: \(filename)")
                
                if filename.contains("_") {
                    let components = filename.components(separatedBy: "_")
                    if components.count > 1 {
                        let cleanName = components.dropFirst().joined(separator: "_")
                        let newURL = cacheManager.cacheDirectory.appendingPathComponent(cleanName)
                        
                        print("Migration: Attempting to rename \(filename) -> \(cleanName)")
                        
                        if !FileManager.default.fileExists(atPath: newURL.path) {
                            try? FileManager.default.moveItem(at: fileURL, to: newURL)
                            print("Migration: SUCCESS - Migrated: \(filename) -> \(cleanName)")
                            await migrateVideoData(from: fileURL, to: newURL)
                        } else {
                            print("Migration: Clean file exists, migrating data from duplicate")
                            await migrateVideoData(from: fileURL, to: newURL)
                            try? FileManager.default.removeItem(at: fileURL)
                            print("Migration: Removed duplicate: \(filename)")
                        }
                    }
                }
            }
        } catch {
            print("Migration error: \(error)")
        }
    }
    
    private func migrateVideoData(from oldURL: URL, to newURL: URL) async {
        let filename = oldURL.lastPathComponent
        let cleanFilename = filename.components(separatedBy: "_").dropFirst().joined(separator: "_")
        
        // Get original title from metadata
        let videoMetadata = UserDefaults.standard.dictionary(forKey: "videoMetadata") as? [String: [String: String]] ?? [:]
        let originalTitle = videoMetadata.first { $0.value["filename"] == cleanFilename }?.key ?? cleanFilename.replacingOccurrences(of: ".mp4", with: "")
        
        print("Migration: Using title '\(originalTitle)' for file \(cleanFilename)")
        
        // Create final URL with proper title
        let finalURL = newURL.deletingLastPathComponent().appendingPathComponent("\(originalTitle).mp4")
        
        if finalURL != newURL && !FileManager.default.fileExists(atPath: finalURL.path) {
            do {
                try FileManager.default.moveItem(at: newURL, to: finalURL)
                print("Migration: Renamed to proper title: \(finalURL.lastPathComponent)")
            } catch {
                print("Migration: Failed to rename to title: \(error)")
            }
        }
        
        let targetURL = FileManager.default.fileExists(atPath: finalURL.path) ? finalURL : newURL
        
        // Migrate marks
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.starts(with: "VideoMarks_") }
        for key in allKeys {
            if key.contains(cleanFilename) {
                if let marks = UserDefaults.standard.array(forKey: key) as? [Double], !marks.isEmpty {
                    VideoMarksManager.shared.saveMarks(marks, for: targetURL)
                    print("Migration: Found and migrated \(marks.count) marks from \(key) to file")
                    break
                }
            }
        }
        
        // Migrate positions
        var positions = UserDefaults.standard.dictionary(forKey: "video_positions") as? [String: Double] ?? [:]
        for (key, position) in positions {
            if key.contains(cleanFilename) {
                positions[targetURL.absoluteString] = position
                positions.removeValue(forKey: key)
                UserDefaults.standard.set(positions, forKey: "video_positions")
                print("Migration: Migrated position \(position)")
                break
            }
        }
        
        // Migrate last played
        var lastPlayedDict = UserDefaults.standard.dictionary(forKey: "videoLastPlayed") as? [String: Double] ?? [:]
        for (key, timestamp) in lastPlayedDict {
            if key.contains(cleanFilename) {
                lastPlayedDict[targetURL.absoluteString] = timestamp
                lastPlayedDict.removeValue(forKey: key)
                UserDefaults.standard.set(lastPlayedDict, forKey: "videoLastPlayed")
                print("Migration: Migrated last played date")
                break
            }
        }
    }
}
