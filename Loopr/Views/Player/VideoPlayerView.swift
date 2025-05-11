import SwiftUI
import AVKit

/// Full-screen video player with controls
struct VideoPlayerView: View {
    // MARK: - Properties
    let video: Video
    let onBack: () -> Void
    let networkManager: NetworkManager
    
    // MARK: - State
    @State var player: AVPlayer
    @StateObject private var viewModel: VideoControlBarViewModel
    @State private var lastMenuPressTime: Date? = nil
    @FocusState private var focusedControl: VideoControlFocus?
    
    // MARK: - Constants
    private enum UI {
        static let aspectRatio: CGFloat = 16/9
        static let topBarPadding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        static let doublePressThreshold: TimeInterval = 1.0
        static let initialFocusDelay: TimeInterval = 0.2
        static let timerInterval: TimeInterval = 0.5
        static let defaultSeekStep: Double = 5.0
        static let minimumTimeFromEnd: Double = 10.0
    }
    
    // Timer to update player state
    let timer = Timer.publish(every: UI.timerInterval, on: .main, in: .common).autoconnect()
    
    // MARK: - Initialization
    init(video: Video, onBack: @escaping () -> Void, seekStepSize: Double = UI.defaultSeekStep, networkManager: NetworkManager) {
        self.video = video
        self.onBack = onBack
        self.networkManager = networkManager
        
        // Initialize with placeholder player
        let initialPlayer = AVPlayer()
        _player = State(initialValue: initialPlayer)
        
        // Create view model
        let viewModel = VideoControlBarViewModel(player: initialPlayer, videoURL: video.url)
        viewModel.seekStepSize = seekStepSize
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                videoTitleBar
                videoPlayer
                VideoProgressBarView(viewModel: viewModel)
                VideoControlBarView(viewModel: viewModel, focusedControl: _focusedControl)
            }
            .ignoresSafeArea(edges: [.horizontal])
        }
        .onExitCommand(perform: handleMenuButtonPress)
        .onPlayPauseCommand(perform: viewModel.togglePlayPause)
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
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
            viewModel.toggleMark()
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
            viewModel.clearMarks()
            return .handled
        }
        .onKeyPress("t") {
            viewModel.startTimer()
            return .handled
        }
        .onKeyPress(.escape) {
                    handleMenuButtonPress()
                    return .handled
                }
                .onKeyPress(.space) {
                    viewModel.togglePlayPause()
                    return .handled
                }
            }
            
            // MARK: - UI Components
            
            /// Video title bar at the top
            private var videoTitleBar: some View {
                HStack {
                    Text(video.title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(UI.topBarPadding)
                .background(Color.black.opacity(0.8))
            }
            
            /// Main video player component
            private var videoPlayer: some View {
                VideoPlayer(player: player) {
                    EmptyView()
                }
                .aspectRatio(UI.aspectRatio, contentMode: .fit)
                .onTapGesture(count: 1) {
                    viewModel.togglePlayPause()
                }
            }
            
            // MARK: - Event Handlers
            
            /// Handle view appearance
            private func handleAppear() {
                setupPlayer()
                recordVideoPlayed()
                setInitialFocus()
            }
            
            /// Handle view disappearance
            private func handleDisappear() {
                player.pause()
                saveVideoPosition()
            }
            
            /// Handle menu button press (with double-press detection for loop mode)
            private func handleMenuButtonPress() {
                saveVideoPosition()
                
                if viewModel.isLooping {
                    if let lastPress = lastMenuPressTime,
                       Date().timeIntervalSince(lastPress) < UI.doublePressThreshold {
                        // Double-press detected, exit video
                        onBack()
                    } else {
                        // First press, just disable looping
                        viewModel.isLooping = false
                        lastMenuPressTime = Date()
                    }
                } else {
                    // Not in loop mode, exit immediately
                    onBack()
                }
            }
            
            // MARK: - Helper Methods
            
            /// Set up the player and load video
            private func setupPlayer() {
                networkManager.loadVideoWithCache(from: video.url) { finalURL in
                    // Create player with final URL (cached or original)
                    let player = AVPlayer(url: finalURL)
                    self.player = player
                    self.viewModel.player = player
                    
                    // Load video metadata asynchronously
                    loadVideoMetadata(player: player)
                    
                    // Start playback
                    player.play()
                }
            }
            
            /// Load video metadata (duration, marks)
            private func loadVideoMetadata(player: AVPlayer) {
                guard let asset = player.currentItem?.asset else { return }
                
                Task {
                    do {
                        let durationValue = try await asset.load(.duration)
                        let seconds = durationValue.seconds
                        
                        if isValidDuration(seconds) {
                            viewModel.duration = seconds
                            setupDefaultMarksIfNeeded(duration: seconds)
                            restorePreviousPosition(duration: seconds)
                        } else {
                            handleInvalidDuration(seconds)
                        }
                    } catch {
                        print("Failed to load duration: \(error)")
                        viewModel.duration = 0
                    }
                }
            }
            
            /// Check if duration is valid and usable
            private func isValidDuration(_ duration: Double) -> Bool {
                return duration.isFinite && !duration.isNaN && duration > 0
            }
            
            /// Initialize default marks at start and end if none exist
            private func setupDefaultMarksIfNeeded(duration: Double) {
                if viewModel.loopMarks.isEmpty {
                    viewModel.loopMarks = [0, duration]
                }
            }
            
            /// Restore previous position if available
            private func restorePreviousPosition(duration: Double) {
                guard let savedPosition = VideoPositionManager.shared.getPosition(for: video.url),
                      savedPosition > 0 && savedPosition < (duration - UI.minimumTimeFromEnd) else {
                    return
                }
                
                Task {
                    // Capture player reference before async operation
                    let playerRef = player
                    await playerRef.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600))
                    viewModel.currentTime = savedPosition
                    print("Restored video position to \(viewModel.formatTime(savedPosition))")
                }
            }
            
            /// Handle case where duration is invalid
            private func handleInvalidDuration(_ duration: Double) {
                viewModel.duration = 0
                print("Warning: Invalid duration value: \(duration)")
            }
            
            /// Record that this video was played in history
            private func recordVideoPlayed() {
                VideoCacheManager.shared.updateLastPlayed(for: video.url)
            }
            
            /// Set initial focus on seek button
            private func setInitialFocus() {
                DispatchQueue.main.asyncAfter(deadline: .now() + UI.initialFocusDelay) {
                    focusedControl = .seekForward
                }
            }
            
            /// Save current position before exiting
            private func saveVideoPosition() {
                if viewModel.currentTime > 0 {
                    VideoPositionManager.shared.savePosition(viewModel.currentTime, for: video.url)
                }
            }
        }
