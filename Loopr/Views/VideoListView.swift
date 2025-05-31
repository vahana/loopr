import SwiftUI

struct VideoListView: View {
    let onSelectVideo: (Video) -> Void
    
    @State private var localVideos: [Video] = []
    @State private var isLoading = true
    
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
            loadVideoLibrary()
        }
    }
    
    private func loadVideoLibrary() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let cacheManager = VideoCacheManager.shared
            
            print("Cache directory: \(cacheManager.cacheDirectory.path)")
            
            // First, migrate old cached files
            self.migrateCachedFiles()
            
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
                    print("Processing file: \(filename)")
                    
                    // Debug: Check if this video has marks
                    let marks = VideoMarksManager.shared.getMarks(for: fileURL)
                    let position = VideoPositionManager.shared.getPosition(for: fileURL)
                    let lastPlayed = cacheManager.getLastPlayed(for: fileURL)
                    
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
                            // Clean name exists, remove the hash-prefixed version
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
        // Migrate marks using the actual key format from VideoMarksManager
        let oldMarksKey = "VideoMarks_" + oldURL.absoluteString.replacingOccurrences(of: "/", with: "_")
        let newMarksKey = "VideoMarks_" + newURL.absoluteString.replacingOccurrences(of: "/", with: "_")
        
        if let marks = UserDefaults.standard.array(forKey: oldMarksKey) as? [Double] {
            UserDefaults.standard.set(marks, forKey: newMarksKey)
            UserDefaults.standard.removeObject(forKey: oldMarksKey)
            print("Migration: Migrated \(marks.count) marks from \(oldMarksKey) to \(newMarksKey)")
        }
        
        // Migrate video position using VideoPositionManager key format
        let oldPositionKey = oldURL.absoluteString
        let newPositionKey = newURL.absoluteString
        
        var positions = UserDefaults.standard.dictionary(forKey: "video_positions") as? [String: Double] ?? [:]
        if let position = positions[oldPositionKey] {
            positions[newPositionKey] = position
            positions.removeValue(forKey: oldPositionKey)
            UserDefaults.standard.set(positions, forKey: "video_positions")
            print("Migration: Migrated position \(position)")
        }
        
        // Migrate last played date using VideoCacheManager key format
        var lastPlayedDict = UserDefaults.standard.dictionary(forKey: "videoLastPlayed") as? [String: Double] ?? [:]
        if let lastPlayedTimestamp = lastPlayedDict[oldURL.absoluteString] {
            lastPlayedDict[newURL.absoluteString] = lastPlayedTimestamp
            lastPlayedDict.removeValue(forKey: oldURL.absoluteString)
            UserDefaults.standard.set(lastPlayedDict, forKey: "videoLastPlayed")
            print("Migration: Migrated last played date")
        }
    }
    
    private func deleteVideo(_ video: Video) {
        do {
            try FileManager.default.removeItem(at: video.url)
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
