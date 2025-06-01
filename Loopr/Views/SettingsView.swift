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
            // App version and migration status
            VStack(spacing: 8) {
                HStack {
                    Text("App Version: 1.0")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                }
                
                Button("Migrate") {
                    Task {
                        await MigrationManager.shared.migrateCachedFiles()
                        loadLocalVideos()
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(8)
            .padding(.horizontal)
            
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(networkManager.videos.enumerated()), id: \.element.id) { index, video in
                                RemoteVideoRow(
                                    video: video,
                                    isDownloaded: isVideoDownloaded(video),
                                    isDownloading: downloadingVideoID == video.id,
                                    downloadProgress: downloadProgress,
                                    onDownload: {
                                        downloadVideo(video)
                                        // Maintain focus on the downloading item
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                proxy.scrollTo(video.id, anchor: .center)
                                            }
                                        }
                                    },
                                    onCancel: cancelDownload
                                )
                                .id(video.id)
                                .focused($focusedVideoIndex, equals: index)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: downloadingVideoID) { _, newValue in
                        // When download starts, scroll to and focus on that item
                        if let downloadingID = newValue,
                           let downloadingIndex = networkManager.videos.firstIndex(where: { $0.id == downloadingID }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedVideoIndex = downloadingIndex
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(downloadingID, anchor: .center)
                                }
                            }
                        }
                    }
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
        
        // Load from cache directory only (all videos are now stored here)
        videos.append(contentsOf: await loadVideosFromDirectory(cacheManager.cacheDirectory))
        
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
        // Check cache directory instead of documents
        let cacheManager = VideoCacheManager.shared
        let filename = "\(video.title).mp4"
        let localURL = cacheManager.cacheDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: localURL.path)
    }
    
    private func downloadVideo(_ video: Video) {
        downloadingVideoID = video.id
        downloadProgress = 0.0
        
        print("=== DOWNLOAD DEBUG INFO ===")
        print("Video title: \(video.title)")
        print("Video URL: \(video.url)")
        print("Video description: \(video.description)")
        
        // Test if the URL is reachable first
        testVideoURL(video.url) { reachable in
            if !reachable {
                print("ERROR: Video URL is not reachable!")
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.downloadProgress = 0.0
                }
                return
            }
            
            print("Video URL is reachable, starting download...")
            self.performActualDownload(video)
        }
    }
    
    private func testVideoURL(_ url: URL, completion: @escaping (Bool) -> Void) {
        print("Testing URL reachability: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"  // Just check if file exists, don't download
        request.timeoutInterval = 30
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("URL test failed: \(error)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("URL test response code: \(httpResponse.statusCode)")
                print("Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
                print("Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                
                completion(httpResponse.statusCode == 200)
            } else {
                print("No HTTP response received")
                completion(false)
            }
        }.resume()
    }
    
    private func performActualDownload(_ video: Video) {
        print("Starting actual download...")
        
        // Use cache directory
        let cacheManager = VideoCacheManager.shared
        let filename = "\(video.title).mp4"
        let destinationURL = cacheManager.cacheDirectory.appendingPathComponent(filename)
        
        print("Destination: \(destinationURL.path)")
        
        // Try with simpler URLSession configuration first
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60    // Start with shorter timeout
        config.timeoutIntervalForResource = 600  // 10 minutes total
        config.allowsCellularAccess = false
        config.waitsForConnectivity = true
        
        let session = URLSession(configuration: config)
        
        // Use simple URL, not URLRequest
        let task = session.downloadTask(with: video.url) { localURL, response, error in
            print("=== DOWNLOAD COMPLETION ===")
            
            if let error = error {
                print("Download failed with error: \(error)")
                
                if let urlError = error as? URLError {
                    print("URLError code: \(urlError.code.rawValue)")
                    print("URLError description: \(urlError.localizedDescription)")
                    
                    switch urlError.code {
                    case .timedOut:
                        print("TIMEOUT: Server took too long to respond")
                    case .cannotConnectToHost:
                        print("CONNECTION: Cannot reach server")
                    case .networkConnectionLost:
                        print("NETWORK: Connection was lost during download")
                    case .badURL:
                        print("URL: The download URL is malformed")
                    default:
                        print("OTHER: \(urlError.code)")
                    }
                }
                
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.downloadProgress = 0.0
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Download response code: \(httpResponse.statusCode)")
                print("Response headers: \(httpResponse.allHeaderFields)")
            }
            
            guard let localURL = localURL else {
                print("ERROR: No temporary file URL received")
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.downloadProgress = 0.0
                }
                return
            }
            
            print("Downloaded to: \(localURL.path)")
            
            // Check file size
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("Downloaded file size: \(fileSize) bytes")
                
                if fileSize == 0 {
                    print("ERROR: Downloaded file is empty!")
                    DispatchQueue.main.async {
                        self.downloadingVideoID = nil
                        self.downloadProgress = 0.0
                    }
                    return
                }
            } catch {
                print("ERROR: Cannot read downloaded file: \(error)")
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.downloadProgress = 0.0
                }
                return
            }
            
            // Move to final destination
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                    print("Removed existing file")
                }
                
                try FileManager.default.moveItem(at: localURL, to: destinationURL)
                print("SUCCESS: File moved to \(destinationURL.path)")
                
                // Verify final file
                let finalAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                let finalSize = finalAttributes[.size] as? Int64 ?? 0
                print("Final file size: \(finalSize) bytes")
                
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.downloadProgress = 1.0
                    self.loadLocalVideos()
                    print("Download completed successfully!")
                }
            } catch {
                print("ERROR: Failed to move file: \(error)")
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.downloadProgress = 0.0
                }
            }
        }
        
        // Simpler progress observation
        observation = task.progress.observe(\.fractionCompleted, options: [.new, .initial]) { progress, _ in
            let progressValue = Float(progress.fractionCompleted)
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            
            print("Progress: \(Int(progressValue * 100))% (\(completed)/\(total) bytes)")
            
            DispatchQueue.main.async {
                self.downloadProgress = progressValue
            }
        }
        
        downloadTask = task
        task.resume()
        
        print("Download task started")
    }
    
    private func cancelDownload() {
        print("Cancelling download")
        downloadTask?.cancel()
        observation?.invalidate()
        downloadingVideoID = nil
        downloadTask = nil
        observation = nil
        downloadProgress = 0.0
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
