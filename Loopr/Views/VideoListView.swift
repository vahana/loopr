//
//  VideoListView.swift
//  Loopr
//
//  Created by vahan on 2025-05-02.
//


// File: Loopr/VideoListView.swift
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
                        // Create a button for each video
                        Button {
                            // When clicked, call the onSelectVideo function
                            onSelectVideo(video)
                        } label: {
                            // Custom list item for each video
                            VideoListItemView(video: video, networkManager: networkManager)
                        }
                        // Use the card button style (specific to tvOS)
                        .buttonStyle(.card)
                    }
                }
                .padding()
            }
        }
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
