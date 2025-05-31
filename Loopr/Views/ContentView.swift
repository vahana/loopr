import SwiftUI
import AVKit

struct ContentView: View {
    @State private var isShowingPlayer = false
    @State private var selectedVideo: Video?
    @State private var showingSettings = false
    
    @StateObject private var networkManager = NetworkManager()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isShowingPlayer {
                if let video = selectedVideo {
                    VideoPlayerView(
                        video: video,
                        onBack: { isShowingPlayer = false },
                        seekStepSize: 5.0,
                        networkManager: networkManager
                    )
                }
            } else {
                VStack {
                    HStack {
                        Text("Downloaded Videos")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    
                    VideoListView(
                        onSelectVideo: { video in
                            selectedVideo = video
                            isShowingPlayer = true
                        },
                        refreshTrigger: showingSettings
                    )
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(networkManager: networkManager)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
