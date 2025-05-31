import SwiftUI

struct RemoteVideoView: View {
    @ObservedObject var networkManager: NetworkManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var downloadingVideoID: UUID? = nil
    @State private var downloadProgress: Float = 0.0
    @State private var downloadTask: URLSessionDownloadTask? = nil
    @State private var observation: NSKeyValueObservation? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header with title and close button
                HStack {
                    Text("Download Videos")
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
                
                // Connection status
                HStack {
                    connectionStatusView
                    Spacer()
                    Button("Scan") {
                        networkManager.scanForServer()
                    }
                    .padding(.horizontal)
                }
                .padding()
                
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
                        
                        Text("No Remote Videos")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        if let error = networkManager.error {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Connect to server to see available videos")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(networkManager.videos) { video in
                                RemoteVideoRow(
                                    video: video,
                                    networkManager: networkManager,
                                    downloadingVideoID: $downloadingVideoID,
                                    downloadProgress: $downloadProgress,
                                    downloadVideo: { downloadVideo(video) },
                                    cancelDownload: cancelDownload
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .onAppear {
                networkManager.scanForServer()
            }
            .onDisappear {
                cancelDownload()
            }
        }
    }
    
    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .foregroundColor(statusColor)
                .font(.caption)
        }
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
    
    private func downloadVideo(_ video: Video) {
        downloadingVideoID = video.id
        downloadProgress = 0.0
        
        let url = video.url
        let request = URLRequest(url: url)
        
        let task = URLSession.shared.downloadTask(with: request) { localURL, response, error in
            guard let localURL = localURL, error == nil else {
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                }
                return
            }
            
            let cachedURL = VideoCacheManager.shared.cachedFileURL(for: url)
            
            do {
                if FileManager.default.fileExists(atPath: cachedURL.path) {
                    try FileManager.default.removeItem(at: cachedURL)
                }
                
                try FileManager.default.moveItem(at: localURL, to: cachedURL)
                
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                }
            } catch {
                print("Error saving downloaded file: \(error)")
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                }
            }
        }
        
        let obs = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                self.downloadProgress = Float(progress.fractionCompleted)
            }
        }
        
        self.downloadTask = task
        self.observation = obs
        
        task.resume()
    }
    
    private func cancelDownload() {
        downloadTask?.cancel()
        observation?.invalidate()
        downloadingVideoID = nil
        downloadTask = nil
        observation = nil
    }
}

struct RemoteVideoRow: View {
    let video: Video
    let networkManager: NetworkManager
    @Binding var downloadingVideoID: UUID?
    @Binding var downloadProgress: Float
    let downloadVideo: () -> Void
    let cancelDownload: () -> Void
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                if !isDownloaded && downloadingVideoID != video.id {
                    downloadVideo()
                }
            } label: {
                HStack(spacing: 16) {
                    // Thumbnail
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 180, height: 100)
                            .cornerRadius(8)
                        
                        if let image = thumbnailImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 180, height: 100)
                                .cornerRadius(8)
                                .clipped()
                        } else if isLoadingThumbnail {
                            ProgressView()
                        } else {
                            Text(String(video.title.prefix(1)))
                                .font(.largeTitle)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Circle().fill(Color.blue.opacity(0.6)))
                        }
                        
                        // Download/Downloaded icon
                        Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.title3)
                            .foregroundColor(isDownloaded ? .green : .white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    
                    // Video info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(video.description)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(3)
                        
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
                            .padding(.trailing, 16)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
            }
            .buttonStyle(.card)
            .disabled(isDownloaded || downloadingVideoID == video.id)
            
            // Progress bar
            if downloadingVideoID == video.id {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading... \(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 8)
                                .cornerRadius(4)
                            
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: CGFloat(downloadProgress) * geometry.size.width, height: 8)
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 8)
                    
                    Button("Cancel") {
                        cancelDownload()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding(.horizontal, 12)
            }
        }
        .onAppear {
            if let thumbnailURL = video.thumbnailURL {
                loadNetworkImage(from: thumbnailURL)
            }
        }
    }
    
    private var isDownloaded: Bool {
        networkManager.isVideoCached(video: video)
    }
    
    private func loadNetworkImage(from url: URL) {
        isLoadingThumbnail = true
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoadingThumbnail = false
                
                if let data = data, let image = UIImage(data: data) {
                    self.thumbnailImage = image
                }
            }
        }.resume()
    }
}
