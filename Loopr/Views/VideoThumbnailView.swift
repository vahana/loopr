// Thumbnail view for an individual video
import SwiftUI
import AVKit


struct VideoThumbnailView: View {
    let video: Video
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    
    var body: some View {
        VStack(alignment: .leading) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(8)
                
                if let image = thumbnailImage {
                    // Display loaded image
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .cornerRadius(8)
                        .clipped()
                } else if let thumbnailName = video.thumbnailName,
                          UIImage(named: thumbnailName) != nil {
                    // Local image from assets
                    Image(thumbnailName)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
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
                    .font(.title)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            
            // Video title and description
            Text(video.title)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.top, 8)
            
            Text(video.description)
                .font(.body)
                .foregroundColor(.gray)
                .lineLimit(2)
                .padding(.top, 2)
        }
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
