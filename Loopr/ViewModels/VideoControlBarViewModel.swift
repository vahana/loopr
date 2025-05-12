import SwiftUI
import AVKit

/// ViewModel for video control functionality
class VideoControlBarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying = true
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var seekStepSize: Double = 5.0  // Fixed 5-second seek increment
    @Published var loopMarks: [Double] = []
    @Published var currentSegmentIndex: Int = 0
    @Published var isLooping = false
    @Published var timerSeconds: Int = 0
    @Published var isTimerRunning = false
    @Published var loopTimerActive: Bool = false
    @Published var loopTimeRemaining: Double = 30.0
    
    // MARK: - Properties
    var player: AVPlayer
    var videoURL: URL?
    
    // MARK: - Private Properties
    private var timerStartDate: Date? = nil
    private var isSeekInProgress = false  // Flag to prevent overlapping seeks
    private var markProximityThreshold = 0.5  // How close to consider a mark
    private var playbackMarkThreshold = 0.2  // How close to pause at mark during playback
    
    // MARK: - Initialization
    init(player: AVPlayer, videoURL: URL? = nil) {
        self.player = player
        self.videoURL = videoURL
        
        if let url = videoURL {
            loopMarks = VideoMarksManager.shared.getMarks(for: url)
        }
    }
    
    // MARK: - Playback Controls
    
    /// Toggle between play and pause
    func togglePlayPause() {
        isPlaying.toggle()
        isPlaying ? player.play() : player.pause()
    }
    
    /// Seek to a specific time
    func seekToTime(_ time: Double) {
        // Always pause when seeking
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        // Calculate bounded time
        let boundedTime = max(0, min(duration, time))
        print("Seeking to time: \(boundedTime)")
        
        // Execute seek
        let seekTime = CMTime(seconds: boundedTime, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            
            // Only update the time if seek completed successfully
            if finished {
                self.currentTime = boundedTime
            }
        }
    }

    func toggleSeekStepSize() {
        // Toggle between 1.0 and 5.0 seconds
        seekStepSize = seekStepSize == 5.0 ? 1.0 : 5.0
    }
    
    /// Seek backward by fixed step size
    func seekBackward() {
        print("Seek backward called")
        // Simple fixed seek - no mark detection
        let newTime = max(0, currentTime - seekStepSize)
        seekToTime(newTime)
    }

    /// Seek forward by fixed step size
    func seekForward() {
        print("Seek forward called")
        // Simple fixed seek - no mark detection
        let newTime = min(duration, currentTime + seekStepSize)
        seekToTime(newTime)
    }

    /// Jump to next mark if availablea
    ///
    func jumpToNextMark() {
        print("Jump to next mark called")
        
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        if isLooping {
            // In loop mode, jumping forward should go to the start of the next segment
            if currentSegmentIndex < loopMarks.count - 2 {
                currentSegmentIndex += 1
                let segmentStart = getCurrentSegmentStart()
                seekToTime(segmentStart)
            } else {
                // If at the last segment, loop back to the first segment
                currentSegmentIndex = 0
                let segmentStart = getCurrentSegmentStart()
                seekToTime(segmentStart)
            }
            
            // Reset the loop timer
            resetLoopTimer()
            
            // Start playback again if we were playing
            isPlaying = true
            player.play()
        } else {
            // Normal mark navigation when not in loop mode
            if let nextMark = loopMarks.first(where: { $0 > currentTime + 0.1 }) {
                print("Found next mark at: \(nextMark)")
                seekToTime(nextMark)
            } else {
                // If no next mark, jump to the first mark (loop around)
                if let firstMark = loopMarks.min() {
                    print("Looping to first mark at: \(firstMark)")
                    seekToTime(firstMark)
                }
            }
        }
    }

    /// Jump to previous mark if available
    func jumpToPreviousMark() {
        print("Jump to previous mark called")
        
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        if isLooping {
            // In loop mode, jumping backward should go to the start of the current segment first
            // If already at the start, then go to previous segment
            let currentStart = getCurrentSegmentStart()
            
            if abs(currentTime - currentStart) > 0.5 {
                // If not at segment start, go to segment start
                seekToTime(currentStart)
            } else {
                // If already at segment start, go to previous segment
                if currentSegmentIndex > 0 {
                    currentSegmentIndex -= 1
                } else {
                    // If at first segment, loop to last segment
                    currentSegmentIndex = loopMarks.count - 2
                }
                seekToTime(getCurrentSegmentStart())
            }
            
            // Reset the loop timer
            resetLoopTimer()
            
            // Start playback again if we were playing
            isPlaying = true
            player.play()
        } else {
            // Normal mark navigation when not in loop mode
            if let prevMark = loopMarks.filter({ $0 < currentTime - 0.1 }).max() {
                print("Found previous mark at: \(prevMark)")
                seekToTime(prevMark)
            } else {
                // If no previous mark, jump to the last mark (loop around)
                if let lastMark = loopMarks.max() {
                    print("Looping to last mark at: \(lastMark)")
                    seekToTime(lastMark)
                }
            }
        }
    }
    
    /// Find the nearest mark between two time points
    ///
    private func findNearestMarkBetween(start: Double, end: Double) -> Double? {
        // Ensure start is less than end
        let (lower, upper) = start < end ? (start, end) : (end, start)
        
        // Get all marks between these points
        let marksBetween = loopMarks.filter { mark in
            mark >= lower && mark <= upper
        }
        
        // If there are marks, return the closest one to the current position
        if !marksBetween.isEmpty {
            return marksBetween.min(by: { abs($0 - currentTime) < abs($1 - currentTime) })
        }
        
        return nil
    }
        
    // MARK: - Mark Management
    
    /// Add a mark at current time or remove if already present
    func toggleMark() {
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        if let index = findMarkNearCurrentTime() {
            loopMarks.remove(at: index)
        } else {
            addMarkAtCurrentTime()
        }
        
        updateCurrentSegmentIndex()
        saveMarks()
    }
    
    /// Remove all marks
    func clearMarks() {
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        loopMarks = []
        isLooping = false
        loopTimerActive = false
        currentSegmentIndex = 0
        
        if let url = videoURL {
            VideoMarksManager.shared.clearMarks(for: url)
        }
    }
        
    // MARK: - Loop Controls
    
    /// Toggle looping mode
    func toggleLoop() {
        guard loopMarks.count >= 2 else {
            isLooping = false
            return
        }
        
        isLooping.toggle()
        
        if isLooping {
            loopTimerActive = true
            loopTimeRemaining = 30.0
            
            updateCurrentSegmentIndex()
            moveToCurrentSegment()
        } else {
            loopTimerActive = false
        }
    }
    
    /// Move to next segment
    func nextSegment() {
        guard loopMarks.count >= 2 && !isSeekInProgress else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        if currentSegmentIndex < loopMarks.count - 2 {
            currentSegmentIndex += 1
        } else {
            currentSegmentIndex = 0
        }
        
        resetLoopTimer()
        moveToCurrentSegment()
    }
    
    /// Move to previous segment
    func previousSegment() {
        guard loopMarks.count >= 2 && !isSeekInProgress else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        
        if currentSegmentIndex > 0 {
            currentSegmentIndex -= 1
        } else {
            currentSegmentIndex = loopMarks.count - 2
        }
        
        resetLoopTimer()
        moveToCurrentSegment()
    }
    
    // MARK: - Timer Controls
    
    /// Start or reset the timer
    func startTimer() {
        timerSeconds = 0
        isTimerRunning = true
        timerStartDate = Date()
    }
    
    /// Update timer when called by timer
    func updateTimerState() {
        if isTimerRunning, let startDate = timerStartDate {
            timerSeconds = Int(Date().timeIntervalSince(startDate))
        }
    }
    
    /// Update player state when called by timer
    func updatePlayerState() {
        // Skip updates during seeking
        guard !isSeekInProgress else { return }
        
        // Update current time from player
        let playerTime = CMTimeGetSeconds(player.currentTime())
        if !playerTime.isNaN && playerTime.isFinite {
            currentTime = playerTime
        }
        
        if isPlaying {
            if !isLooping {
                checkForMarksInPlayback()
            } else {
                handleLoopBoundaries()
                updateLoopTimer()
            }
        }
    }
    
    // MARK: - Segment Information
    
    /// Get the start time of current segment
    func getCurrentSegmentStart() -> Double {
        guard hasValidSegments else { return 0 }
        return loopMarks[currentSegmentIndex]
    }
    
    /// Get the end time of current segment
    func getCurrentSegmentEnd() -> Double {
        guard hasValidSegments else { return duration }
        return loopMarks[currentSegmentIndex + 1]
    }
    
    // MARK: - Formatters
    
    /// Format time as MM:SS or HH:MM:SS
    func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds < 0 {
            return "00:00"
        }
        
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }
    
    /// Format loop timer as "30s"
    func formatLoopTimeRemaining() -> String {
        return "\(Int(loopTimeRemaining))s"
    }
    
    /// Format current segment as "[1/3]"
    func formatCurrentSegment() -> String {
        return "[\(currentSegmentIndex + 1)/\(max(1, loopMarks.count - 1))]"
    }
    
    // MARK: - Private Methods
    
    private var hasValidSegments: Bool {
        return loopMarks.count >= 2 && currentSegmentIndex < loopMarks.count - 1
    }
    
    private func findMarkNearCurrentTime() -> Int? {
        return loopMarks.firstIndex(where: { abs($0 - currentTime) < markProximityThreshold })
    }
        
    private func addMarkAtCurrentTime() {
        loopMarks.append(currentTime)
        loopMarks.sort()
    }
    
    private func saveMarks() {
        if let videoURL = videoURL {
            VideoMarksManager.shared.saveMarks(loopMarks, for: videoURL)
        }
    }
    
    private func resetLoopTimer() {
        loopTimerActive = true
        loopTimeRemaining = 30.0
    }
    
    private func moveToCurrentSegment() {
        guard hasValidSegments && !isSeekInProgress else { return }
        
        let segmentStart = getCurrentSegmentStart()
        
        if abs(currentTime - segmentStart) >= 0.1 {
            seekToTime(segmentStart)
        }
    }
    
    private func updateCurrentSegmentIndex() {
        guard loopMarks.count >= 2 else {
            currentSegmentIndex = 0
            return
        }
        
        for i in 0..<(loopMarks.count - 1) {
            if currentTime >= loopMarks[i] && currentTime < loopMarks[i + 1] {
                currentSegmentIndex = i
                return
            }
        }
        
        // If past the last mark, use the last segment
        if currentTime >= loopMarks.last! {
            currentSegmentIndex = loopMarks.count - 2
        } else {
            currentSegmentIndex = 0
        }
    }
    
    private func checkForMarksInPlayback() {
        for mark in loopMarks {
            if abs(currentTime - mark) < playbackMarkThreshold && currentTime > mark {
                if isPlaying {
                    player.pause()
                    isPlaying = false
                }
                player.seek(to: CMTime(seconds: mark, preferredTimescale: 600))
                currentTime = mark
                break
            }
        }
    }
    
    private func handleLoopBoundaries() {
        let segmentStart = getCurrentSegmentStart()
        let segmentEnd = getCurrentSegmentEnd()
        
        if currentTime >= segmentEnd {
            player.seek(to: CMTime(seconds: segmentStart, preferredTimescale: 600))
        }
    }
    
    private func updateLoopTimer() {
        if loopTimerActive && isPlaying {
            loopTimeRemaining -= 0.5
            
            if loopTimeRemaining <= 0 {
                if isPlaying {
                    player.pause()
                    isPlaying = false
                }
                
                if currentSegmentIndex < loopMarks.count - 2 {
                    currentSegmentIndex += 1
                    moveToCurrentSegment()
                } else {
                    loopTimerActive = false
                }
                
                resetLoopTimer()
            }
        }
    }
}
