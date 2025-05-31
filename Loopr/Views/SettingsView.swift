import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var networkManager: NetworkManager
    
    @State private var selectedTab = 0
    @State private var downloadingVideoID: UUID?
    @State private var downloadProgress: Float = 0.0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var localVideos: [LocalVideo] = []
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: LocalVideo?
    @FocusState private var focusedVideoIndex: Int?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                header
                tabSelector
                
                if selectedTab == 0 {
                    libraryTab
                } else {
                    downloadTab
                }
            }
        }
        .onAppear {
            loadLocalVideos()
            if selectedTab == 1 {
                networkManager.scanForServer()
            }
        }
        .onDisappear {
            cancelDownload()
        }
    }
    
    private var header: some View {
        HStack {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private var tabSelector: some View {
        HStack(spacing: 20) {
            Button("Library") {
                selectedTab = 0
                loadLocalVideos()
            }
            .foregroundColor(selectedTab == 0 ? .blue : .gray)
            .fontWeight(selectedTab == 0 ? .bold : .regular)
            
            Button("Download") {
                selectedTab = 1
                networkManager.scanForServer()
            }
            .foregroundColor(selectedTab == 1 ? .blue : .gray)
            .fontWeight(selectedTab == 1 ? .bold : .regular)
        }
        .padding()
    }
    
    private var libraryTab: some View {
        VStack {
            if localVideos.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No Downloaded Videos")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(localVideos.indices, id: \.self) { index in
                            LocalVideoRow(
                                video: localVideos[index],
                                onDelete: {
                                    videoToDelete = localVideos[index]
                                    showingDeleteConfirmation = true
                                }
                            )
                            .focused($focusedVideoIndex, equals: index)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if !localVideos.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedVideoIndex = 0
                        }
                    }
                }
            }
        }
        .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let video = videoToDelete {
                    deleteVideo(video)
                }
            }
        } message: {
            Text("Are you sure you want to delete this video?")
        }
    }
    
    private var downloadTab: some View {
        VStack {
            connectionStatus
            
            if networkManager.isScanning {
                Spacer()
                ProgressView("Scanning for server...")
                    .foregroundColor(.white)
                Spacer()
            } else if networkManager.videos.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No Server Videos")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    if let error = networkManager.error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(networkManager.videos) { video in
                            RemoteVideoRow(
                                video: video,
                                isDownloaded: isVideoDownloaded(video),
                                isDownloading: downloadingVideoID == video.id,
                                downloadProgress: downloadProgress,
                                onDownload: { downloadVideo(video) },
                                onCancel: cancelDownload
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var connectionStatus: some View {
        HStack {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .foregroundColor(statusColor)
                    .font(.caption)
            }
            
            Spacer()
            
            Button("Scan") {
                networkManager.scanForServer()
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private var statusColor: Color {
        if networkManager.isScanning {
            return .yellow
        } else if networkManager.serverURL != nil {
            return .green
        } else {
            return .red
        }
    }
    
    private var statusText: String {
        if networkManager.isScanning {
            return "Scanning..."
        } else if networkManager.serverURL != nil {
            return "Connected"
        } else {
            return "Disconnected"
        }
    }
    
    private func loadLocalVideos() {
        Task {
            let videos = await loadAllVideos()
            await MainActor.run {
                self.localVideos = videos.map { video in
                    let attributes = try? FileManager.default.attributesOfItem(atPath: video.url.path)
                    let fileSize = attributes?[.size] as? Int64 ?? 0
                    let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
                    
                    return LocalVideo(
                        id: UUID(),
                        title: video.title,
                        url: video.url,
                        size: ByteCountFormatter().string(fromByteCount: fileSize),
                        date: modificationDate
                    )
                }
            }
        }
    }
    
    private func loadAllVideos() async -> [Video] {
        let cacheManager = VideoCacheManager.shared
        var videos: [Video] = []
        
        // Load from cache directory
        videos.append(contentsOf: await loadVideosFromDirectory(cacheManager.cacheDirectory))
        
        // Load from documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        videos.append(contentsOf: await loadVideosFromDirectory(documentsPath))
        
        // Remove duplicates
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
    
    private func isVideoDownloaded(_ video: Video) -> Bool {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "\(video.title).mp4"
        let localURL = documentsPath.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: localURL.path)
    }
    
    private func downloadVideo(_ video: Video) {
        downloadingVideoID = video.id
        downloadProgress = 0.0
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "\(video.title).mp4"
        let destinationURL = documentsPath.appendingPathComponent(filename)
        
        let task = URLSession.shared.downloadTask(with: video.url) { localURL, response, error in
            guard let localURL = localURL, error == nil else {
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                }
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                try FileManager.default.moveItem(at: localURL, to: destinationURL)
                
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.loadLocalVideos()
                }
            } catch {
                print("Error saving downloaded file: \(error)")
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                }
            }
        }
        
        observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                self.downloadProgress = Float(progress.fractionCompleted)
            }
        }
        
        downloadTask = task
        task.resume()
    }
    
    private func cancelDownload() {
        downloadTask?.cancel()
        observation?.invalidate()
        downloadingVideoID = nil
        downloadTask = nil
        observation = nil
    }
    
    private func deleteVideo(_ video: LocalVideo) {
        do {
            try FileManager.default.removeItem(at: video.url)
            loadLocalVideos()
        } catch {
            print("Error deleting video: \(error)")
        }
    }
}

struct LocalVideo: Identifiable {
    let id: UUID
    let title: String
    let url: URL
    let size: String
    let date: Date
}

struct LocalVideoRow: View {
    let video: LocalVideo
    let onDelete: () -> Void
    
    var body: some View {
        Button {
            onDelete()
        } label: {
            HStack(spacing: 16) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 68)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("Size: \(video.size)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("Downloaded: \(RelativeDateTimeFormatter().localizedString(for: video.date, relativeTo: Date()))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
        }
        .buttonStyle(.card)
    }
}

struct RemoteVideoRow: View {
    let video: Video
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Float
    let onDownload: () -> Void
    let onCancel: () -> Void
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                if !isDownloaded && !isDownloading {
                    onDownload()
                }
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 68)
                            .cornerRadius(8)
                        
                        if let image = thumbnailImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 68)
                                .cornerRadius(8)
                                .clipped()
                        } else {
                            Text(String(video.title.prefix(1)))
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.title3)
                            .foregroundColor(isDownloaded ? .green : .white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(video.description)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                        
                        if isDownloaded {
                            Text("Downloaded")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Spacer()
                    
                    if !isDownloaded {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.blue)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            }
            .buttonStyle(.card)
            .disabled(isDownloaded || isDownloading)
            
            if isDownloading {
                VStack(spacing: 4) {
                    Text("Downloading... \(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 6)
                                .cornerRadius(3)
                            
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: CGFloat(downloadProgress) * geometry.size.width, height: 6)
                                .cornerRadius(3)
                        }
                    }
                    .frame(height: 6)
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)
            }
        }
        .onAppear {
            if let thumbnailURL = video.thumbnailURL {
                loadThumbnail(from: thumbnailURL)
            }
        }
    }
    
    private func loadThumbnail(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.thumbnailImage = image
                }
            }
        }.resume()
    }
}
