import SwiftUI

struct VideoListView: View {
    let onSelectVideo: (Video) -> Void
    let refreshTrigger: Bool
    
    @State private var localVideos: [Video] = []
    @State private var isLoading = true
    @FocusState private var focusedVideoIndex: Int?
    
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
                    
                    Text("No Videos")
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
        let downloadManager = VideoDownloadManager.shared
        var videos: [Video] = []
        
        // Load from downloads directory only (all videos are now stored here)
        videos.append(contentsOf: await loadVideosFromDirectory(downloadManager.downloadsDirectory))
        
        // Remove duplicates and sort
        let uniqueVideos = Dictionary(grouping: videos, by: { $0.title }).compactMap { $1.first }
        
        return uniqueVideos.sorted { video1, video2 in
            let date1 = downloadManager.getLastPlayed(for: video1.url) ?? .distantPast
            let date2 = downloadManager.getLastPlayed(for: video2.url) ?? .distantPast
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
            
            // Load video metadata for descriptions
            let videoMetadata = UserDefaults.standard.dictionary(forKey: "videoMetadata") as? [String: [String: String]] ?? [:]
            
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
                
                // Get description from metadata, fallback to title lookup, then default
                var videoDescription = "Downloaded Video"
                
                // First try direct title match
                if let metadata = videoMetadata[displayName] {
                    videoDescription = metadata["description"] ?? "Downloaded Video"
                } else {
                    // Try to find by filename match
                    for (title, metadata) in videoMetadata {
                        if let metadataFilename = metadata["filename"],
                           metadataFilename == filename {
                            videoDescription = metadata["description"] ?? title
                            break
                        }
                    }
                }
                
                let video = Video(
                    title: displayName,
                    description: videoDescription,
                    url: fileURL
                )
                
                videos.append(video)
            }
            
        } catch {
            print("Error loading videos from \(directory.path): \(error)")
        }
        
        return videos
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
                    
                    if let lastPlayed = VideoDownloadManager.shared.getLastPlayed(for: video.url) {
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
