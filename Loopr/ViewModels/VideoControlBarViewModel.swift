import SwiftUI
import AVKit

/// ViewModel for video control functionality
class VideoControlBarViewModel: ObservableObject {
    // MARK: - Step Size Configuration
    private struct SeekStepSizes {
        static let options: [Double] = [0.5, 5.0, 30.0]
        static let defaultIndex: Int = 1  // Index for 5.0
    }
    
    // MARK: - Published Properties
    @Published var isPlaying = true
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var seekStepSize: Double = SeekStepSizes.options[SeekStepSizes.defaultIndex]
    @Published var loopMarks: [Double] = []
    @Published var currentSegmentIndex: Int = 0
    @Published var isLooping = false
    @Published var timerSeconds: Int = 0
    @Published var isTimerRunning = false
    @Published var loopTimerActive: Bool = false
    @Published var loopTimeRemaining: Double = 30.0
    
    // Track the current index in the step size options
    private var currentStepSizeIndex: Int = SeekStepSizes.defaultIndex
    
    // MARK: - Properties
    var player: AVPlayer
    var videoURL: URL?
    
    // MARK: - Private Properties
    private var timerStartDate: Date? = nil
    private var isSeekInProgress = false  // Flag to prevent overlapping seeks
    private var markProximityThreshold = 0.5  // How close to consider a mark
    private var playbackMarkThreshold = 0.2  // How close to pause at mark during playback
    private var wasPlayingBeforeSeek = false  // Track playback state before seeking
    private var seekQueue = DispatchQueue(label: "com.loopr.seekQueue")
    
    // MARK: - Initialization
    init(player: AVPlayer, videoURL: URL? = nil) {
        self.player = player
        self.videoURL = videoURL
        
        if let url = videoURL {
            loopMarks = VideoMarksManager.shared.getMarks(for: url)
        }
        
        // New: Setup dynamic thresholds based on video properties
        setupDynamicThresholds()
    }
    
    // MARK: - Playback Controls
    
    /// Toggle between play and pause
    func togglePlayPause() {
        isPlaying.toggle()
        isPlaying ? player.play() : player.pause()
    }
    
    /// Seek to a specific time
    func seekToTime(_ time: Double) {
        // Use a dispatch queue to serialize seek operations
        seekQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Set the flag to prevent overlapping seeks
            self.isSeekInProgress = true
            
            // Remember playback state
            self.wasPlayingBeforeSeek = self.isPlaying
            
            // Pause temporarily for better seeking accuracy
            DispatchQueue.main.async {
                if self.isPlaying {
                    self.player.pause()
                }
                
                // Calculate bounded time
                let boundedTime = max(0, min(self.duration, time))
                
                // Get frame rate for better tolerance setting
                let frameRate = self.player.currentItem?.asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30
                let frameDuration = 1.0 / Double(frameRate)
                
                // Round to nearest frame boundary
                let frameAlignedTime = round(boundedTime / frameDuration) * frameDuration
                
                print("Seeking to time: \(frameAlignedTime)")
                
                // Set tolerances based on frame duration
                let tolerance = CMTime(seconds: frameDuration/2, preferredTimescale: 600)
                
                // Execute seek with proper tolerances
                let seekTime = CMTime(seconds: frameAlignedTime, preferredTimescale: 600)
                self.player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        // Only update the time if seek completed successfully
                        if finished {
                            self.currentTime = frameAlignedTime
                            
                            // Resume playback if it was playing before
                            if self.wasPlayingBeforeSeek && self.isLooping {
                                self.player.play()
                                self.isPlaying = true
                            }
                        }
                        
                        // Clear flag when seek is complete
                        self.isSeekInProgress = false
                    }
                }
            }
        }
    }

    func toggleSeekStepSize() {
        // Cycle to the next step size in the options array
        currentStepSizeIndex = (currentStepSizeIndex + 1) % SeekStepSizes.options.count
        seekStepSize = SeekStepSizes.options[currentStepSizeIndex]
    }
    
    /// Format the seek step size for display
    func formatSeekStepSize() -> String {
        // If the value is a whole number, display as integer
        if seekStepSize.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(seekStepSize))s"
        } else {
            // For decimal values, show one decimal place
            return String(format: "%.1fs", seekStepSize)
        }
    }
    
    /// Seek backward by current step size
    func seekBackward() {
        print("Seek backward called")
        if isSeekInProgress { return }
        
        // Simple fixed seek - no mark detection
        let newTime = max(0, currentTime - seekStepSize)
        seekToTime(newTime)
    }

    /// Seek forward by current step size
    func seekForward() {
        print("Seek forward called")
        if isSeekInProgress { return }
        
        // Simple fixed seek - no mark detection
        let newTime = min(duration, currentTime + seekStepSize)
        seekToTime(newTime)
    }

    /// Jump to next mark if available
    func jumpToNextMark() {
        print("Jump to next mark called")
        if isSeekInProgress { return }
        
        // Always pause when seeking for better control
        let wasPlaying = isPlaying
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
            
            // Restore playback state if we were playing and in loop mode
            if wasPlaying && isLooping {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.player.play()
                    self.isPlaying = true
                }
            }
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
        if isSeekInProgress { return }
        
        // Always pause when seeking for better control
        let wasPlaying = isPlaying
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
            
            // Restore playback state if we were playing and in loop mode
            if wasPlaying && isLooping {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.player.play()
                    self.isPlaying = true
                }
            }
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
        if isSeekInProgress { return }
        
        // Save playback state
        let wasPlaying = isPlaying
        
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
        
        // Restore playback if it was playing
        if wasPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.player.play()
                self.isPlaying = true
            }
        }
    }
    
    /// Remove all marks
    func clearMarks() {
        if isSeekInProgress { return }
        
        // Save playback state
        let wasPlaying = isPlaying
        
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
        
        // Restore playback if it was playing
        if wasPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.player.play()
                self.isPlaying = true
            }
        }
    }
        
    // MARK: - Loop Controls
    
    /// Toggle looping mode
    func toggleLoop() {
        if isSeekInProgress { return }
        
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
        if isSeekInProgress { return }
        
        guard loopMarks.count >= 2 else { return }
        
        // Save playback state
        let wasPlaying = isPlaying
        
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
        
        // Restore playback if it was playing and we're in loop mode
        if wasPlaying && isLooping {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.player.play()
                self.isPlaying = true
            }
        }
    }
    
    /// Move to previous segment
    func previousSegment() {
        if isSeekInProgress { return }
        
        guard loopMarks.count >= 2 else { return }
        
        // Save playback state
        let wasPlaying = isPlaying
        
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
        
        // Restore playback if it was playing and we're in loop mode
        if wasPlaying && isLooping {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.player.play()
                self.isPlaying = true
            }
        }
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
        if isSeekInProgress { return }
        
        // Update current time from player
        let playerTime = CMTimeGetSeconds(player.currentTime())
        if !playerTime.isNaN && playerTime.isFinite {
            // Round to a reasonable precision to avoid floating point errors
            let roundedTime = round(playerTime * 1000) / 1000  // Round to milliseconds
            
            // Only update if not currently seeking
            if !isSeekInProgress {
                currentTime = roundedTime
            }
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
        // Round to nearest frame boundary based on video frame rate
        let frameRate = player.currentItem?.asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30
        let frameDuration = 1.0 / Double(frameRate)
        
        // Round to nearest frame
        let frameAlignedTime = round(currentTime / frameDuration) * frameDuration
        
        loopMarks.append(frameAlignedTime)
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
        
        // Use frame duration as minimum threshold
        let frameRate = player.currentItem?.asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30
        let frameDuration = 1.0 / Double(frameRate)
        
        // Only seek if we're at least one frame away
        if abs(currentTime - segmentStart) >= frameDuration {
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
        // Skip if already seeking
        if isSeekInProgress { return }
        
        for mark in loopMarks {
            if abs(currentTime - mark) < playbackMarkThreshold && currentTime > mark {
                let wasPlaying = isPlaying
                
                if isPlaying {
                    player.pause()
                    isPlaying = false
                }
                
                // Use seekToTime to ensure proper state management
                seekToTime(mark)
                
                // Don't automatically resume - let the user decide
                break
            }
        }
    }
    
    private func handleLoopBoundaries() {
        // Skip if already seeking
        if isSeekInProgress { return }
        
        let segmentStart = getCurrentSegmentStart()
        let segmentEnd = getCurrentSegmentEnd()
        
        // Add small epsilon to avoid boundary edge cases
        let epsilon = 0.03  // ~1 frame at 30fps
        
        // Check for out-of-bounds in both directions with margin
        if currentTime >= (segmentEnd - epsilon) || currentTime < (segmentStart + epsilon) {
            // Use our seekToTime method which handles state properly
            seekToTime(segmentStart)
            
            // We'll resume playing in the seekToTime completion handler
        }
    }
    
    private func updateLoopTimer() {
        if loopTimerActive && isPlaying {
            loopTimeRemaining -= 0.5
            
            if loopTimeRemaining <= 0 {
                let wasPlaying = isPlaying
                
                if isPlaying {
                    player.pause()
                    isPlaying = false
                }
                
                if currentSegmentIndex < loopMarks.count - 2 {
                    currentSegmentIndex += 1
                    moveToCurrentSegment()
                    
                    // Resume playback after moving to new segment
                    if wasPlaying {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.player.play()
                            self.isPlaying = true
                        }
                    }
                } else {
                    loopTimerActive = false
                }
                
                resetLoopTimer()
            }
        }
    }
    
    // New method to setup dynamic thresholds based on video
    private func setupDynamicThresholds() {
        // Wait for player item to be ready before getting frame rate
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: player.currentItem,
            queue: nil
        ) { [weak self] _ in
            self?.updateThresholdsFromVideo()
        }
        
        // Set initial thresholds based on default values
        updateThresholdsFromVideo()
    }
    
    private func updateThresholdsFromVideo() {
        if let frameRate = player.currentItem?.asset.tracks(withMediaType: .video).first?.nominalFrameRate {
            let frameDuration = 1.0 / Double(frameRate)
            
            // Set thresholds relative to frame duration
            markProximityThreshold = max(0.25, frameDuration * 2)  // At least 2 frames
            playbackMarkThreshold = max(0.1, frameDuration)        // At least 1 frame
            
            print("Video frame rate: \(frameRate)fps, thresholds updated")
        }
    }
}
