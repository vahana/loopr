import SwiftUI

struct VideoListView: View {
    let onSelectVideo: (Video) -> Void
    let refreshTrigger: Bool
    
    @State private var localVideos: [Video] = []
    @State private var isLoading = true
    @FocusState private var focusedVideoIndex: Int?
    
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
                        ForEach(localVideos.indices, id: \.self) { index in
                            VideoRow(
                                video: localVideos[index],
                                onSelectVideo: onSelectVideo
                            )
                            .focused($focusedVideoIndex, equals: index)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
//            UserDefaults.standard.removeObject(forKey: "videoDataMigrated_v1")
            loadVideoLibrary()
        }
        .onChange(of: refreshTrigger) { _, _ in
            if !refreshTrigger {
                loadVideoLibrary()
            }
        }
    }
    
    private func loadVideoLibrary() {
        isLoading = true
        
        Task {
            let videos = await loadVideosInBackground()
            
            await MainActor.run {
                self.localVideos = videos
                self.isLoading = false
                
                if !videos.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedVideoIndex = 0
                    }
                }
            }
        }
    }
    
    private func loadVideosInBackground() async -> [Video] {
        let cacheManager = VideoCacheManager.shared
        
        if shouldRunMigration() {
            await migrateCachedFiles()
            markMigrationComplete()
        }
        
        var videos: [Video] = []
        
        // Load from cache directory (migrated files)
        videos.append(contentsOf: await loadVideosFromDirectory(cacheManager.cacheDirectory))
        
        // Load from documents directory (new downloads)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        videos.append(contentsOf: await loadVideosFromDirectory(documentsPath))
        
        // Remove duplicates and sort
        let uniqueVideos = Dictionary(grouping: videos, by: { $0.title }).compactMap { $1.first }
        
        return uniqueVideos.sorted { video1, video2 in
            let date1 = cacheManager.getLastPlayed(for: video1.url) ?? .distantPast
            let date2 = cacheManager.getLastPlayed(for: video2.url) ?? .distantPast
            return date1 > date2
        }
    }
    
    private func loadVideosFromDirectory(_ directory: URL) async -> [Video] {
        var videos: [Video] = []
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in fileURLs {
                let filename = fileURL.lastPathComponent
                
                if filename.hasSuffix(".marks") {
                    continue
                }
                
                // Skip old hash files in cache directory only
                if directory.lastPathComponent == "VideoCache" &&
                   filename.contains("_") &&
                   filename.split(separator: "_").first?.allSatisfy({ $0.isNumber || $0 == "-" }) == true {
                    continue
                }
                
                guard filename.hasSuffix(".mp4") else { continue }
                
                let displayName = filename.replacingOccurrences(of: ".mp4", with: "")
                
                let video = Video(
                    title: displayName,
                    description: "Downloaded Video",
                    url: fileURL
                )
                
                videos.append(video)
            }
            
        } catch {
            print("Error loading videos from \(directory.path): \(error)")
        }
        
        return videos
    }
    
    private func shouldRunMigration() -> Bool {
        return !UserDefaults.standard.bool(forKey: migrationKey)
    }
    
    private func markMigrationComplete() {
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
    
    private func migrateCachedFiles() async {
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
        
        // Get original title from mapping, fallback to clean filename
        let titleMapping = UserDefaults.standard.dictionary(forKey: "videoTitleMapping") as? [String: String] ?? [:]
        let originalTitle = titleMapping[cleanFilename] ?? cleanFilename.replacingOccurrences(of: ".mp4", with: "")
        
        print("Migration: Using title '\(originalTitle)' for file \(cleanFilename)")
        
        // Create final URL with proper title
        let finalURL = newURL.deletingLastPathComponent().appendingPathComponent("\(originalTitle).mp4")
        
        if finalURL != newURL && !FileManager.default.fileExists(atPath: finalURL.path) {
            do {
                try FileManager.default.moveItem(at: newURL, to: finalURL)
                print("Migration: Renamed to proper title: \(finalURL.lastPathComponent)")
            } catch {
                print("Migration: Failed to rename to title: \(error)")
                // Use newURL if rename fails
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

struct VideoRow: View {
    let video: Video
    let onSelectVideo: (Video) -> Void
    
    var body: some View {
        Button {
            onSelectVideo(video)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 180, height: 100)
                        .cornerRadius(8)
                    
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
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
