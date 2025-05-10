// File: Loopr/ViewModels/VideoControlBarViewModel.swift
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
    @Published var loopMarks: [Double] = [] {
        didSet {
            // Save marks when they change
            if let videoURL = videoURL {
                VideoMarksManager.shared.saveMarks(loopMarks, for: videoURL)
            }
        }
    }
    @Published var currentSegmentIndex: Int = 0
    @Published var isLooping = false
    
    // Timer feature states
    @Published var timerSeconds: Int = 0
    @Published var isTimerRunning = false
    @Published var timerStartDate: Date? = nil
    
    @Published var loopTimerActive: Bool = false
    @Published var loopTimeRemaining: Double = 30.0 // 30 seconds default
    
    private var lastSeekDirection: SeekDirection = .none
    private var lastSeekTime: Date = Date.distantPast
    private var consecutiveSeekCount: Int = 0

    // Reference to player
    var player: AVPlayer
    
    // Reference to current video URL for saving marks
    var videoURL: URL?
    
    // MARK: - Initialization
    init(player: AVPlayer, videoURL: URL? = nil) {
        self.player = player
        self.videoURL = videoURL
        
        // Load marks if URL is provided
        if let url = videoURL {
            loopMarks = VideoMarksManager.shared.getMarks(for: url)
        }
    }
    
    // MARK: - Control Methods
    
    // Define seek direction enum
    private enum SeekDirection {
        case forward, backward, none
    }
    
    // Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    // Add a new mark at current time or remove if already present
    func addMark() {
        // Always pause the video when adding/removing marks
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        // Check if we're very close to an existing mark (within 0.5 seconds)
        if let index = loopMarks.firstIndex(where: { abs($0 - currentTime) < 0.5 }) {
            // We're at a mark, so remove it
            loopMarks.remove(at: index)
            
            // Update current segment after removing mark
            updateCurrentSegmentIndex()
        } else {
            // Add a new mark
            loopMarks.append(currentTime)
            // Sort marks in ascending order
            loopMarks.sort()
            
            // Update current segment based on where we are
            updateCurrentSegmentIndex()
        }
    }
    
    // Remove the nearest mark to current time
    func removeMark() {
        guard !loopMarks.isEmpty else { return }
        
        // Find the closest mark to current time
        let closestMarkIndex = loopMarks.indices.min(by: { abs(loopMarks[$0] - currentTime) < abs(loopMarks[$1] - currentTime) }) ?? 0
        loopMarks.remove(at: closestMarkIndex)
        
        // Update current segment after removing mark
        updateCurrentSegmentIndex()
    }
    
    // Clear all marks
    func clearMarks() {
        // Always pause the video when clearing marks
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        // Clear the marks array
        loopMarks = []
        
        // If looping was active, disable it
        if isLooping {
            isLooping = false
            loopTimerActive = false
        }
        
        // Reset current segment index
        currentSegmentIndex = 0
        
        // Clear marks from persistent storage
        if let url = videoURL {
            VideoMarksManager.shared.clearMarks(for: url)
        }
    }
    
    // Toggle looping
    func toggleLoop() {
        // Need at least 2 marks to create a segment
        guard loopMarks.count >= 2 else {
            isLooping = false
            return
        }
        
        isLooping.toggle()
        
        if isLooping {
            // Start loop timer when loop is enabled
            loopTimerActive = true
            loopTimeRemaining = 30.0
            
            // Set the current segment based on current position
            updateCurrentSegmentIndex()
            
            // Jump to start of current segment if needed
            moveToCurrentSegment()
            
            // Only start playing if the user explicitly presses play
            // Don't auto-start when enabling loop mode
        } else {
            // Cancel timer when loop is disabled
            loopTimerActive = false
        }
    }
    
    // Move to next segment
    func nextSegment() {
        guard loopMarks.count >= 2 else { return }
        
        // Always pause the video when moving to a new segment
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        // The last valid segment index is (loopMarks.count - 2)
        // Because a segment is defined by two marks
        if currentSegmentIndex < loopMarks.count - 2 {
            currentSegmentIndex += 1
        } else {
            // Wrap around to first segment
            currentSegmentIndex = 0
        }
        
        // Reset loop timer
        loopTimerActive = true
        loopTimeRemaining = 30.0
        
        // Move to start of new segment
        moveToCurrentSegment()
    }
    
    // Move to previous segment
    func previousSegment() {
        guard loopMarks.count >= 2 else { return }
        
        // Always pause the video when moving to a new segment
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        if currentSegmentIndex > 0 {
            currentSegmentIndex -= 1
        } else {
            // Wrap around to last segment
            currentSegmentIndex = loopMarks.count - 2
        }
        
        // Reset loop timer
        loopTimerActive = true
        loopTimeRemaining = 30.0
        
        // Move to start of new segment
        moveToCurrentSegment()
    }
    
    // Jump to the next mark if available
    func jumpToNextMark() {
        guard !loopMarks.isEmpty else { return }
        
        // Find the next mark that's after current time
        if let nextMark = loopMarks.first(where: { $0 > currentTime }) {
            seekToTime(nextMark)
        }
    }
    
    // Jump to the previous mark if available
    func jumpToPreviousMark() {
        guard !loopMarks.isEmpty else { return }
        
        // Find the nearest mark that's before current time
        if let prevMark = loopMarks.filter({ $0 < currentTime }).max() {
            seekToTime(prevMark)
        }
    }
    
    // Perform a large seek (used for long press)
    func seekLargeBackward() {
        let newTime = max(0, currentTime - 10.0)
        seekToTime(newTime)
    }
    
    // Perform a large seek (used for long press)
    func seekLargeForward() {
        let newTime = min(duration, currentTime + 10.0)
        seekToTime(newTime)
    }
    
    // Helper to move to the start of current segment
    private func moveToCurrentSegment() {
        guard loopMarks.count >= 2 && currentSegmentIndex < loopMarks.count - 1 else { return }
        
        let segmentStart = loopMarks[currentSegmentIndex]
        
        // If we're already at this time (within a small threshold), don't seek
        if abs(currentTime - segmentStart) < 0.1 {
            return
        }
        
        seekToTime(segmentStart)
    }
    
    // Update current segment index based on where we are in the video
    private func updateCurrentSegmentIndex() {
        guard loopMarks.count >= 2 else {
            currentSegmentIndex = 0
            return
        }
        
        // Find which segment contains current time
        for i in 0..<(loopMarks.count - 1) {
            if currentTime >= loopMarks[i] && currentTime < loopMarks[i + 1] {
                currentSegmentIndex = i
                return
            }
        }
        
        // If we're past the last mark, use the last segment
        if currentTime >= loopMarks.last! {
            currentSegmentIndex = loopMarks.count - 2
        } else {
            // Otherwise default to first segment
            currentSegmentIndex = 0
        }
    }
    
    // Get the start time of current segment
    func getCurrentSegmentStart() -> Double {
        guard loopMarks.count >= 2 && currentSegmentIndex < loopMarks.count - 1 else {
            return 0
        }
        return loopMarks[currentSegmentIndex]
    }
    
    // Get the end time of current segment
    func getCurrentSegmentEnd() -> Double {
        guard loopMarks.count >= 2 && currentSegmentIndex < loopMarks.count - 1 else {
            return duration
        }
        return loopMarks[currentSegmentIndex + 1]
    }
    
    // Seek backward by configurable step size
    func seekBackward() {
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastSeekTime)
        
        // Check if this is a consecutive click (within 0.8 seconds)
        if timeInterval < 0.3 && lastSeekDirection == .backward {
            consecutiveSeekCount += 1
        } else {
            consecutiveSeekCount = 0
        }
        
        // Calculate dynamic seek amount based on consecutive clicks
        let seekAmount = calculateProgressiveSeekAmount(clicks: consecutiveSeekCount)
        
        // Perform the seek
        let newTime = max(0, currentTime - seekAmount)
        
        // Check if we're about to seek past a mark
        if !loopMarks.isEmpty {
            // Find the nearest mark that's less than current time
            let nearestMarkBefore = loopMarks.filter { $0 < currentTime }.max()
            
            // If newTime would skip over a mark, stop at the mark instead
            if let mark = nearestMarkBefore, newTime < mark && currentTime >= mark {
                // Seek to the mark
                seekToTime(mark)
                return
            }
        }
        
        seekToTime(newTime)
        
        // Update tracking state
        lastSeekDirection = .backward
        lastSeekTime = now
    }
    
    // Seek forward by configurable step size
    func seekForward() {
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastSeekTime)
        
        // Check if this is a consecutive click (within 0.8 seconds)
        if timeInterval < 0.3 && lastSeekDirection == .forward {
            consecutiveSeekCount += 1
        } else {
            consecutiveSeekCount = 0
        }
        
        // Calculate dynamic seek amount based on consecutive clicks
        let seekAmount = calculateProgressiveSeekAmount(clicks: consecutiveSeekCount)
        
        // Perform the seek
        let newTime = min(duration, currentTime + seekAmount)
        
        // Check if we're about to seek past a mark
        if !loopMarks.isEmpty {
            // Find the nearest mark that's greater than current time
            let nearestMarkAfter = loopMarks.filter { $0 > currentTime }.min()
            
            // If newTime would skip over a mark, stop at the mark instead
            if let mark = nearestMarkAfter, newTime > mark && currentTime <= mark {
                // Seek to the mark
                seekToTime(mark)
                return
            }
        }
        
        seekToTime(newTime)
        
        // Update tracking state
        lastSeekDirection = .forward
        lastSeekTime = now
    }
    
    // Seek to a specific time
    func seekToTime(_ time: Double) {
        // Always pause when directly seeking to a time
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        
        // Update current segment index
        if isLooping {
            updateCurrentSegmentIndex()
        }
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
        
        // Check if we've reached a mark during normal playback
        if isPlaying && !isLooping {
            for mark in loopMarks {
                // If we just passed a mark (within 0.2 seconds), pause at that mark
                if abs(currentTime - mark) < 0.2 && currentTime > mark {
                    player.pause()
                    isPlaying = false
                    player.seek(to: CMTime(seconds: mark, preferredTimescale: 600))
                    currentTime = mark
                    break
                }
            }
        }
        
        if isLooping && loopMarks.count >= 2 {
            // Get current segment boundaries
            let segmentStart = getCurrentSegmentStart()
            let segmentEnd = getCurrentSegmentEnd()
            
            // Loop within current segment
            if currentTime >= segmentEnd {
                player.seek(to: CMTime(seconds: segmentStart, preferredTimescale: 600))
            }
            
            if loopTimerActive && isPlaying {
                loopTimeRemaining -= 0.5 // Since timer fires every 0.5 seconds
                
                // When countdown reaches zero, pause and prepare for next segment
                if loopTimeRemaining <= 0 {
                    // Pause the video
                    if isPlaying {
                        player.pause()
                        isPlaying = false
                    }
                    
                    // Move to next segment but don't start playing
                    if currentSegmentIndex < loopMarks.count - 2 {
                        currentSegmentIndex += 1
                        moveToCurrentSegment()
                    } else {
                        // If we're at the last segment, just reset timer
                        loopTimerActive = false
                    }
                    
                    // Reset timer
                    loopTimerActive = true
                    loopTimeRemaining = 30.0
                }
            }
        }
    }
        
    // Format timer time as MM:SS
    func formatTime(_ seconds: Double) -> String {
        // Check for invalid values
        if seconds.isNaN || seconds.isInfinite || seconds < 0 {
            return "00:00"
        }
        
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    func formatLoopTimeRemaining() -> String {
        return "\(Int(loopTimeRemaining))s"
    }
    
    // Format current segment display for UI
    func formatCurrentSegment() -> String {
        return "[\(currentSegmentIndex + 1)/\(max(1, loopMarks.count - 1))]"
    }
    
    private func calculateProgressiveSeekAmount(clicks: Int) -> Double {
        switch clicks {
        case 0:  return 1.0  // First click: 1 second
        case 1:  return 5.0  // Second click: 5 seconds
        default:  return 10.0 // Third click: 10 seconds
        }
    }
}

// Focus state enum (important for tvOS navigation)
enum VideoControlFocus: Int {
    case seekBackward, seekForward
    case addMark, toggleLoop
    case startTimer, clearMarks
}
