// File: Loopr/VideoGridView.swift
import SwiftUI

// Grid view that shows all available videos
struct VideoGridView: View {
    // MARK: - Properties
    
    // List of videos to display
    let videos: [Video]
    
    // Function to call when a video is selected
    // This is called a "closure" in Swift - like a function pointer
    let onSelectVideo: (Video) -> Void
    
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
            
            // Create a scrollable grid of videos
            ScrollView {
                // Define the grid layout (adaptive columns)
                // This makes the grid adjust based on screen size
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 30)],
                    spacing: 40
                ) {
                    // Loop through each video
                    ForEach(videos) { video in
                        // Create a button for each video
                        Button {
                            // When clicked, call the onSelectVideo function
                            onSelectVideo(video)
                        } label: {
                            // Use our custom thumbnail view for each video
                            VideoThumbnailView(video: video)
                        }
                        // Use the card button style (specific to tvOS)
                        // This gives us the nice tvOS focus effect
                        .buttonStyle(.card)
                    }
                }
                .padding()
            }
        }
    }
}
