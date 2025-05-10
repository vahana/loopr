// File: Loopr/VideoPlayerView.swift
import SwiftUI
import AVKit

// Full-screen video player with controls below video
struct VideoPlayerView: View {
    // MARK: - Properties
    
    // The video to play
    let video: Video
    
    // Function to call when back button is pressed
    let onBack: () -> Void
    
    // MARK: - State Variables
    
    // The video player
    @State private var player: AVPlayer
    
    // View model for controls
    @StateObject private var viewModel: VideoControlBarViewModel
    
    // Track the last time menu button was pressed for double-press detection
    @State private var lastMenuPressTime: Date? = nil
    
    // Focus state (important for tvOS navigation)
    @FocusState private var focusedControl: VideoControlFocus?
    
    // Timer to update player state
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    let networkManager: NetworkManager
    
    // MARK: - Initialization
    
    // Custom initializer to set up the player
    init(video: Video, onBack: @escaping () -> Void, seekStepSize: Double = 5.0, networkManager: NetworkManager) {
        self.video = video
        self.onBack = onBack
        self.networkManager = networkManager
        
        // Initialize with placeholder player first
        let initialPlayer = AVPlayer()
        _player = State(initialValue: initialPlayer)
        
        // Create view model with video URL
        let viewModel = VideoControlBarViewModel(player: initialPlayer, videoURL: video.url)
        viewModel.seekStepSize = seekStepSize
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Top bar with video title
                HStack {
                    // Video title
                    Text(video.title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.8))
                
                // Standard VideoPlayer from AVKit
                VideoPlayer(player: player) {
                    // Overlay
                    EmptyView()
                }
                .aspectRatio(16/9, contentMode: .fit)
                .onTapGesture(count: 1) {
                    viewModel.togglePlayPause()
                }
                
                // Progress bar component
                VideoProgressBarView(viewModel: viewModel)
                
                // Control bar component
                VideoControlBarView(viewModel: viewModel, focusedControl: _focusedControl)
            }
            .ignoresSafeArea(edges: [.horizontal])
        }
        // Handle tvOS Menu button press - custom handler for loop state
        .onExitCommand {
            handleMenuButtonPress()
        }
        // Handle tvOS Play/Pause button press
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
        }
        .onAppear {
            // When the view appears, set up the player
            setupPlayer()
            
            // Record that this video was played
            VideoCacheManager.shared.updateLastPlayed(for: video.url)
            
            // Set initial focus to play button
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focusedControl = .play
            }
        }
        .onDisappear {
            // When the view disappears, pause the player
            player.pause()
        }
        // Update player state on timer
        .onReceive(timer) { _ in
            viewModel.updatePlayerState()
            viewModel.updateTimerState()
        }
        // Keyboard shortcuts
        .onKeyPress(.leftArrow) {
            if focusedControl == nil {
                viewModel.seekBackward()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if focusedControl == nil {
                viewModel.seekForward()
                return .handled
            }
            return .ignored
        }
        .onKeyPress("m") {
            viewModel.addMark()
            return .handled
        }
        .onKeyPress("d") {
            viewModel.removeMark()
            return .handled
        }
        .onKeyPress("[") {
            viewModel.previousSegment()
            return .handled
        }
        .onKeyPress("]") {
            viewModel.nextSegment()
            return .handled
        }
        .onKeyPress("l") {
            viewModel.toggleLoop()
            return .handled
        }
        .onKeyPress("c") {
            // Clear marks shortcut - use a local variable to avoid binding issues
            let vm = viewModel
            vm.clearMarks()
            return .handled
        }
        .onKeyPress("t") {
            // Shortcut for timer
            viewModel.startTimer()
            return .handled
        }
        .onKeyPress(.escape) {
            // Use the same handler for escape key (for debugging on Mac)
            handleMenuButtonPress()
            return .handled
        }
        .onKeyPress(.space) {
            // Space key toggles play/pause too
            viewModel.togglePlayPause()
            return .handled
        }
    }
    
    // MARK: - Menu Button Handler
    
    // Handle menu button press with special behavior for looping
    private func handleMenuButtonPress() {
        // If looping is active, first press turns it off
        if viewModel.isLooping {
            // Check if this is a double-press (within 1 second)
            if let lastPress = lastMenuPressTime, Date().timeIntervalSince(lastPress) < 1.0 {
                // Double-press detected, go back to video list
                onBack()
            } else {
                // First press, turn off looping
                viewModel.isLooping = false
                
                // Record the time of this press
                lastMenuPressTime = Date()
            }
        } else {
            // Not looping, so just go back
            onBack()
        }
    }
    
    // MARK: - Setup Methods
    
    // Set up the player initially
    private func setupPlayer() {
        // Try to load from cache
        networkManager.loadVideoWithCache(from: video.url) { finalURL in
            // Create player with the cached URL or original if caching failed
            let player = AVPlayer(url: finalURL)
            self.player = player
            self.viewModel.player = player
            
            // Load duration
            if let asset = player.currentItem?.asset {
                Task {
                    do {
                        let durationValue = try await asset.load(.duration)
                        // Ensure duration is valid before using it
                        let seconds = durationValue.seconds
                        if seconds.isFinite && !seconds.isNaN && seconds > 0 {
                            self.viewModel.duration = seconds
                            
                            // Only add default marks if no saved marks were loaded
                            if self.viewModel.loopMarks.isEmpty {
                                // Add default marks at start and end of video
                                self.viewModel.loopMarks = [0, seconds]
                            }
                        } else {
                            // Set a default duration if the actual one is invalid
                            self.viewModel.duration = 0
                            print("Warning: Invalid duration value: \(seconds)")
                        }
                    } catch {
                        print("Failed to load duration: \(error)")
                        // Set default values on error
                        self.viewModel.duration = 0
                    }
                }
            }
            
            // Start playing
            player.play()
        }
    }
}
