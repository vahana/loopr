import SwiftUI
import AVKit

/// ViewModel for video control functionality
class VideoControlBarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying = true
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var seekStepSize: Double = 5.0
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
    private var lastSeekDirection = SeekDirection.none
    private var lastSeekTime = Date.distantPast
    private var consecutiveSeekCount = 0
    private var timerStartDate: Date? = nil
    
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
        pauseIfPlaying()
        
        currentTime = max(0, min(duration, time))
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
        
        if isLooping {
            updateCurrentSegmentIndex()
        }
    }
    
    /// Seek backward with dynamic step size
    func seekBackward() {
        let amount = calculateSeekAmount(direction: .backward)
        let newTime = max(0, currentTime - amount)
        
        if shouldStopAtMark(currentTime: currentTime, targetTime: newTime) {
            seekToPreviousMark()
        } else {
            seekToTime(newTime)
        }
    }
    
    /// Seek forward with dynamic step size
    func seekForward() {
        let amount = calculateSeekAmount(direction: .forward)
        let newTime = min(duration, currentTime + amount)
        
        if shouldStopAtMark(currentTime: currentTime, targetTime: newTime) {
            seekToNextMark()
        } else {
            seekToTime(newTime)
        }
    }
    
    // MARK: - Mark Management
    
    /// Add a mark at current time or remove if already present
    func toggleMark() {
        pauseIfPlaying()
        
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
        pauseIfPlaying()
        
        loopMarks = []
        isLooping = false
        loopTimerActive = false
        currentSegmentIndex = 0
        
        if let url = videoURL {
            VideoMarksManager.shared.clearMarks(for: url)
        }
    }
    
    /// Jump to next mark if available
    func jumpToNextMark() {
        seekToNextMark()
    }
    
    /// Jump to previous mark if available
    func jumpToPreviousMark() {
        seekToPreviousMark()
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
        guard loopMarks.count >= 2 else { return }
        
        pauseIfPlaying()
        
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
        guard loopMarks.count >= 2 else { return }
        
        pauseIfPlaying()
        
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
        currentTime = CMTimeGetSeconds(player.currentTime())
        
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
    
    private func pauseIfPlaying() {
        if isPlaying {
            player.pause()
            isPlaying = false
        }
    }
    
    private func findMarkNearCurrentTime() -> Int? {
        return loopMarks.firstIndex(where: { abs($0 - currentTime) < 0.5 })
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
        guard hasValidSegments else { return }
        
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
    
    private func calculateSeekAmount(direction: SeekDirection) -> Double {
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastSeekTime)
        
        // Check if this is a consecutive seek in the same direction
        if timeInterval < 0.4 && lastSeekDirection == direction {
            consecutiveSeekCount += 1
        } else {
            consecutiveSeekCount = 0
        }
        
        lastSeekDirection = direction
        lastSeekTime = now
        
        // Dynamic seek amount based on consecutive seeks
        switch consecutiveSeekCount {
        case 0:  return 1.0
        case 1:  return 5.0
        default: return 10.0
        }
    }
    
    private func seekToNextMark() {
        if let nextMark = loopMarks.first(where: { $0 > currentTime }) {
            seekToTime(nextMark)
        }
    }
    
    private func seekToPreviousMark() {
        if let prevMark = loopMarks.filter({ $0 < currentTime }).max() {
            seekToTime(prevMark)
        }
    }
    
    private func shouldStopAtMark(currentTime: Double, targetTime: Double) -> Bool {
        guard !loopMarks.isEmpty else { return false }
        
        if targetTime < currentTime {  // seeking backward
            return loopMarks.contains(where: {
                $0 < currentTime && $0 >= targetTime
            })
        } else {  // seeking forward
            return loopMarks.contains(where: {
                $0 > currentTime && $0 <= targetTime
            })
        }
    }
    
    private func checkForMarksInPlayback() {
        for mark in loopMarks {
            if abs(currentTime - mark) < 0.2 && currentTime > mark {
                pauseIfPlaying()
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
                pauseIfPlaying()
                
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

enum SeekDirection {
    case forward, backward, none
}
