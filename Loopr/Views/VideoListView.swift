import SwiftUI

// List view that shows all available videos
struct VideoListView: View {
    // MARK: - Properties
    
    // List of videos to display
    let videos: [Video]
    
    // Function to call when a video is selected
    let onSelectVideo: (Video) -> Void
    
    // Network manager for checking cache status
    let networkManager: NetworkManager
    
    // Track which video is currently downloading and its progress
    @State private var downloadingVideoID: UUID? = nil
    @State private var downloadProgress: Float = 0.0
    @State private var downloadTask: URLSessionDownloadTask? = nil
    @State private var observation: NSKeyValueObservation? = nil
    
    // MARK: - Body
    
    var body: some View {
        VStack {
            // Title at the top
            Text("Video Library")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 40)
                .padding(.bottom, 20)
            
            // Create a scrollable list of videos
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Loop through each video
                    ForEach(videos) { video in
                        VStack(spacing: 0) {
                            // Create a button for each video
                            Button {
                                // Check if the video is cached
                                if networkManager.isVideoCached(video: video) {
                                    // If cached, play it immediately
                                    onSelectVideo(video)
                                } else {
                                    // If not cached, start downloading
                                    downloadVideo(video)
                                }
                            } label: {
                                // Custom list item for each video
                                VideoListItemView(video: video, networkManager: networkManager)
                            }
                            .buttonStyle(.card)
                            
                            // Show progress bar if this video is being downloaded
                            if downloadingVideoID == video.id {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Downloading...")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                    
                                    // Progress bar
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            // Background
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 8)
                                                .cornerRadius(4)
                                            
                                            // Progress fill
                                            Rectangle()
                                                .fill(Color.blue)
                                                .frame(width: CGFloat(downloadProgress) * geometry.size.width, height: 8)
                                                .cornerRadius(4)
                                        }
                                    }
                                    .frame(height: 8)
                                    
                                    // Cancel button
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
                    }
                }
                .padding()
            }
        }
        .onDisappear {
            // Clean up when the view disappears
            cancelDownload()
        }
    }
    
    // Function to start downloading a video
    private func downloadVideo(_ video: Video) {
        // Set the current downloading video
        downloadingVideoID = video.id
        downloadProgress = 0.0
        
        // Create a download task with progress tracking
        let url = video.url
        let request = URLRequest(url: url)
        
        let task = URLSession.shared.downloadTask(with: request) { localURL, response, error in
            guard let localURL = localURL, error == nil else {
                // Handle download error
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                }
                return
            }
            
            // Get the destination path for the cached file
            let cachedURL = VideoCacheManager.shared.cachedFileURL(for: url)
            
            do {
                // Remove existing file if necessary
                if FileManager.default.fileExists(atPath: cachedURL.path) {
                    try FileManager.default.removeItem(at: cachedURL)
                }
                
                // Move downloaded file to cache
                try FileManager.default.moveItem(at: localURL, to: cachedURL)
                
                // Play the video after download completes
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                    self.onSelectVideo(video)
                }
            } catch {
                print("Error saving downloaded file: \(error)")
                DispatchQueue.main.async {
                    self.downloadingVideoID = nil
                }
            }
        }
        
        // Add progress observation
        let obs = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                self.downloadProgress = Float(progress.fractionCompleted)
            }
        }
        
        // Store the observation and task to cancel later if needed
        self.downloadTask = task
        self.observation = obs
        
        task.resume()
    }
    
    // Function to cancel current download
    private func cancelDownload() {
        downloadTask?.cancel()
        observation?.invalidate()
        downloadingVideoID = nil
        
        // Clear references
        downloadTask = nil
        observation = nil
    }
}

// List item view for an individual video
struct VideoListItemView: View {
    let video: Video
    let networkManager: NetworkManager
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail section
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 180, height: 100)
                    .cornerRadius(8)
                
                if let image = thumbnailImage {
                    // Display loaded image
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 100)
                        .cornerRadius(8)
                        .clipped()
                } else if let thumbnailName = video.thumbnailName,
                          UIImage(named: thumbnailName) != nil {
                    // Local image from assets
                    Image(thumbnailName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 100)
                        .cornerRadius(8)
                        .clipped()
                } else if isLoadingThumbnail {
                    // Loading indicator
                    ProgressView()
                } else {
                    // Placeholder
                    Text(String(video.title.prefix(1)))
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.blue.opacity(0.6)))
                }
                
                // Play icon overlay
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .frame(width: 180, height: 100)
            
            // Video info section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Video title
                    Text(video.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Cache indicator
                    if networkManager.isVideoCached(video: video) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                // Video description
                Text(video.description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(3)
            }
            
            Spacer()
            
            // Arrow icon
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .padding(.trailing, 16)
        }
        .padding(12)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .onAppear {
            // Load network thumbnail if available
            if let thumbnailURL = video.thumbnailURL {
                loadNetworkImage(from: thumbnailURL)
            }
        }
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
