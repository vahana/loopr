import SwiftUI

struct VideoListView: View {
    let onSelectVideo: (Video) -> Void
    
    @State private var localVideos: [Video] = []
    @State private var isLoading = true
    
    private let migrationKey = "videoDataMigrated_v1"
    
    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView("Loading videos...")
                    .foregroundColor(.white)
                Spacer()
            } else if localVideos.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No Downloaded Videos")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text("Go to Settings to download videos")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(localVideos) { video in
                            VideoRow(
                                video: video,
                                onSelectVideo: onSelectVideo,
                                onDeleteVideo: { deleteVideo(video) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            //UserDefaults.standard.removeObject(forKey: "videoDataMigrated_v1")
            loadVideoLibrary()
        }
    }
    
    private func loadVideoLibrary() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let cacheManager = VideoCacheManager.shared
            
            print("Cache directory: \(cacheManager.cacheDirectory.path)")
            
            // Migrate old cached files and marks to file-based system
            if self.shouldRunMigration() {
                self.migrateCachedFiles()
                self.markMigrationComplete()
            }
            
            var videos: [Video] = []
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: cacheManager.cacheDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                print("Found \(fileURLs.count) files in cache directory")
                
                for fileURL in fileURLs {
                    let filename = fileURL.lastPathComponent
                    
                    // Skip .marks files
                    if filename.hasSuffix(".marks") {
                        continue
                    }
                    
                    print("Processing file: \(filename)")
                    
                    // Debug: Check if this video has marks
                    let marks = VideoMarksManager.shared.getMarks(for: fileURL)
                    let position = VideoPositionManager.shared.getPosition(for: fileURL)
                    let lastPlayed = cacheManager.getLastPlayed(for: fileURL)
                    let marksFilePath = fileURL.appendingPathExtension("marks").path
                    
                    print("  - Video path: \(fileURL.path)")
                    print("  - Marks file path: \(marksFilePath)")
                    print("  - Marks file exists: \(FileManager.default.fileExists(atPath: marksFilePath))")
                    print("  - Marks: \(marks.count) segments")
                    if !marks.isEmpty {
                        print("  - Mark times: \(marks)")
                    }
                    if let pos = position {
                        print("  - Saved position: \(pos)")
                    }
                    if let played = lastPlayed {
                        print("  - Last played: \(played)")
                    }
                    
                    // Skip old hash-prefixed files (they should be migrated)
                    if filename.contains("_") && filename.split(separator: "_").first?.allSatisfy({ $0.isNumber || $0 == "-" }) == true {
                        print("Skipping old hash file: \(filename)")
                        continue
                    }
                    
                    let displayName = filename.replacingOccurrences(of: ".mp4", with: "")
                    
                    let video = Video(
                        title: displayName,
                        description: "Downloaded Video",
                        url: fileURL
                    )
                    
                    videos.append(video)
                    print("Added video: \(displayName)")
                }
                
                print("Total videos loaded: \(videos.count)")
                
                // Sort by last played date
                videos.sort { video1, video2 in
                    let date1 = cacheManager.getLastPlayed(for: video1.url) ?? .distantPast
                    let date2 = cacheManager.getLastPlayed(for: video2.url) ?? .distantPast
                    return date1 > date2
                }
                
            } catch {
                print("Error loading videos: \(error)")
            }
            
            DispatchQueue.main.async {
                self.localVideos = videos
                self.isLoading = false
            }
        }
    }
    
    private func shouldRunMigration() -> Bool {
        return !UserDefaults.standard.bool(forKey: migrationKey)
    }
    
    private func markMigrationComplete() {
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
    
    private func migrateCachedFiles() {
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
                
                // Skip .marks files
                if filename.hasSuffix(".marks") {
                    continue
                }
                
                print("Migration: Checking file: \(filename)")
                
                // Check if this is an old hash-prefixed file
                if filename.contains("_") {
                    let components = filename.components(separatedBy: "_")
                    if components.count > 1 {
                        let cleanName = components.dropFirst().joined(separator: "_")
                        let newURL = cacheManager.cacheDirectory.appendingPathComponent(cleanName)
                        
                        print("Migration: Attempting to rename \(filename) -> \(cleanName)")
                        
                        // Only migrate if the clean name doesn't already exist
                        if !FileManager.default.fileExists(atPath: newURL.path) {
                            try? FileManager.default.moveItem(at: fileURL, to: newURL)
                            print("Migration: SUCCESS - Migrated: \(filename) -> \(cleanName)")
                            
                            // Migrate marks and position data
                            migrateVideoData(from: fileURL, to: newURL)
                        } else {
                            // Clean name exists, migrate data first then remove duplicate
                            print("Migration: Clean file exists, migrating data from duplicate")
                            migrateVideoData(from: fileURL, to: newURL)
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
    
    private func migrateVideoData(from oldURL: URL, to newURL: URL) {
        let filename = oldURL.lastPathComponent
        let cleanFilename = filename.components(separatedBy: "_").dropFirst().joined(separator: "_")
        
        // Find marks by searching for keys that contain the clean filename
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.starts(with: "VideoMarks_") }
        
        for key in allKeys {
            if key.contains(cleanFilename) {
                if let marks = UserDefaults.standard.array(forKey: key) as? [Double], !marks.isEmpty {
                    // Save marks to file
                    VideoMarksManager.shared.saveMarks(marks, for: newURL)
                    print("Migration: Found and migrated \(marks.count) marks from \(key) to file")
                    break
                }
            }
        }
        
        // Migrate positions and last played to UserDefaults (these work fine)
        var positions = UserDefaults.standard.dictionary(forKey: "video_positions") as? [String: Double] ?? [:]
        for (key, position) in positions {
            if key.contains(cleanFilename) {
                positions[newURL.absoluteString] = position
                positions.removeValue(forKey: key)
                UserDefaults.standard.set(positions, forKey: "video_positions")
                print("Migration: Migrated position \(position)")
                break
            }
        }
        
        var lastPlayedDict = UserDefaults.standard.dictionary(forKey: "videoLastPlayed") as? [String: Double] ?? [:]
        for (key, timestamp) in lastPlayedDict {
            if key.contains(cleanFilename) {
                lastPlayedDict[newURL.absoluteString] = timestamp
                lastPlayedDict.removeValue(forKey: key)
                UserDefaults.standard.set(lastPlayedDict, forKey: "videoLastPlayed")
                print("Migration: Migrated last played date")
                break
            }
        }
    }
    
    private func deleteVideo(_ video: Video) {
        do {
            // Delete video file
            try FileManager.default.removeItem(at: video.url)
            
            // Delete marks file
            VideoMarksManager.shared.clearMarks(for: video.url)
            
            localVideos.removeAll { $0.id == video.id }
        } catch {
            print("Error deleting video: \(error)")
        }
    }
}

struct VideoRow: View {
    let video: Video
    let onSelectVideo: (Video) -> Void
    let onDeleteVideo: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Button {
            onSelectVideo(video)
        } label: {
            HStack(spacing: 16) {
                // Thumbnail placeholder
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 180, height: 100)
                        .cornerRadius(8)
                    
                    // Play icon overlay
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                
                // Video info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        // Downloaded indicator
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
                    // Last played date
                    if let lastPlayed = VideoCacheManager.shared.getLastPlayed(for: video.url) {
                        Text("Last played: \(formatDate(lastPlayed))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Text(video.description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Delete button
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.title3)
                        .padding(8)
                }
                .buttonStyle(.borderless)
                .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        onDeleteVideo()
                    }
                } message: {
                    Text("Are you sure you want to delete this downloaded video?")
                }
            }
            .padding(12)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
        }
        .buttonStyle(.card)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
