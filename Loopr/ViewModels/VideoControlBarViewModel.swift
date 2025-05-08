// File: Loopr/VideoControlBarView.swift
import SwiftUI
import AVKit

// View model for video controls to share state between views
class VideoControlBarViewModel: ObservableObject {
    // Playback state
    @Published var isPlaying = true
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    // Seek step size (can be changed during playback)
    @Published var seekStepSize: Double = 5.0
    
    // Loop feature states
    @Published var loopStartTime: Double = 0
    @Published var loopEndTime: Double = 0
    @Published var isLooping = false
    
    // Timer feature states
    @Published var timerSeconds: Int = 0
    @Published var isTimerRunning = false
    @Published var timerStartDate: Date? = nil
    
    @Published var loopTimerActive: Bool = false
    @Published var loopTimeRemaining: Double = 30.0 // 30 seconds default
    
    // Reference to player
    var player: AVPlayer
    
    // MARK: - Initialization
    init(player: AVPlayer) {
        self.player = player
    }
    
    // MARK: - Control Methods
    
    // Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    // Set loop start point
    func setLoopStart() {
        loopStartTime = currentTime
        // Make sure end is after start
        if loopEndTime < loopStartTime {
            loopEndTime = min(loopStartTime + 10, duration)
        }
    }
    
    // Set loop end point
    func setLoopEnd() {
        loopEndTime = currentTime
        // Make sure start is before end
        if loopEndTime < loopStartTime {
            loopStartTime = max(loopEndTime - 10, 0)
        }
    }
    
    // Toggle looping
    func toggleLoop() {
        isLooping.toggle()
        
        if isLooping {
            // Start loop timer when loop is enabled
            loopTimerActive = true
            loopTimeRemaining = 30.0
            
            // Resume playback if it was paused
            if !isPlaying {
                player.play()
                isPlaying = true
            }
            
            // Jump to start point if needed (existing code)
            if currentTime < loopStartTime || currentTime > loopEndTime {
                player.seek(to: CMTime(seconds: loopStartTime, preferredTimescale: 600))
            }
        } else {
            // Cancel timer when loop is disabled
            loopTimerActive = false
        }
    }
    // Seek backward by configurable step size
    func seekBackward() {
        let newTime = max(0, currentTime - seekStepSize)
        seekToTime(newTime)
    }
    
    // Seek forward by configurable step size
    func seekForward() {
        let newTime = min(duration, currentTime + seekStepSize)
        seekToTime(newTime)
    }
    
    // Seek to a specific time
    func seekToTime(_ time: Double) {
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    // Start or reset timer
    func startTimer() {
        // Reset timer to 0
        timerSeconds = 0
        
        // Set timer to running state
        isTimerRunning = true
        
        // Record start time
        timerStartDate = Date()
    }
    
    // Update timer state (called by timer)
    func updateTimerState() {
        if isTimerRunning, let startDate = timerStartDate {
            // Calculate elapsed time
            timerSeconds = Int(Date().timeIntervalSince(startDate))
        }
    }
    
    // Update player state (called by timer)
    func updatePlayerState() {
        currentTime = CMTimeGetSeconds(player.currentTime())
        
        if isLooping && currentTime >= loopEndTime {
            player.seek(to: CMTime(seconds: loopStartTime, preferredTimescale: 600))
        }
        
        if loopTimerActive && isLooping && isPlaying {
            loopTimeRemaining -= 0.5 // Since timer fires every 0.5 seconds
            
            // When countdown reaches zero, disable looping and pause the video
            if loopTimeRemaining <= 0 {
                isLooping = false
                loopTimerActive = false
                
                // Pause the video
                if isPlaying {
                    player.pause()
                    isPlaying = false
                }
            }
        }
    }
    
    // Format time in seconds to MM:SS or HH:MM:SS
    func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    // Format timer time as MM:SS
    func formatTimerTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    func formatLoopTimeRemaining() -> String {
        return "\(Int(loopTimeRemaining))s"
    }
}

// Focus state enum (important for tvOS navigation)
enum VideoControlFocus: Int {
    case seekBackward, play, seekForward
    case loopStart, loopEnd, toggleLoop
    case startTimer
}


struct VideoControlBarView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample player and view model for preview
        let player = AVPlayer()
        let viewModel = VideoControlBarViewModel(player: player)
        
        // Return the view with the sample view model
        // Use a State variable to create a proper binding for the FocusState
        VideoControlBarView(viewModel: viewModel)
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}
