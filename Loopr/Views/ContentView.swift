// File: Loopr/ContentView.swift
import SwiftUI
import AVKit

struct ContentView: View {
    // MARK: - State
    
    @State private var isShowingPlayer = false
    @State private var selectedVideo: Video?
    @State private var seekStepSize: Double = 5.0
    @State private var showingNetworkVideos = true
    
    // Add StateObject for network manager
    @StateObject private var networkManager = NetworkManager()
    
    // Keep sample videos for fallback
    private let sampleVideos = [
        Video(
            title: "Big Buck Bunny",
            description: "A short animated film",
            thumbnailName: "bunny_thumbnail",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
        )
    ]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isShowingPlayer {
                if let video = selectedVideo {
                    VideoPlayerView(
                        video: video,
                        onBack: { isShowingPlayer = false },
                        seekStepSize: seekStepSize,
                        networkManager: networkManager  // Pass the network manager
                    )
                }
            } else {
                VStack {
                    // Header with connection status
                    HStack {
                        Text("Video Library")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Connection status indicator
                        if networkManager.isScanning {
                            Text("Scanning...")
                                .foregroundColor(.yellow)
                        } else if networkManager.serverURL != nil {
                            Text("Connected")
                                .foregroundColor(.green)
                        } else if let error = networkManager.error {
                            Text(error)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                        
                        Button("Scan") {
                            networkManager.scanForServer()
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    
                    // Source selector
                    Picker("Video Source", selection: $showingNetworkVideos) {
                        Text("Network").tag(true)
                        Text("Samples").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Show either network or sample videos - Now using VideoListView instead of VideoGridView
                    VideoListView(
                        videos: showingNetworkVideos ? networkManager.videos : sampleVideos,
                        onSelectVideo: { video in
                            selectedVideo = video
                            isShowingPlayer = true
                        }
                    )
                }
            }
        }
        .onAppear {
            // Automatically scan for server when view appears
            networkManager.scanForServer()
            
            // Clean expired cache
            VideoCacheManager.shared.cleanExpiredCache()
        }
    }
}

// This lets us see the app in Xcode's preview canvas
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
