import SwiftUI
import AVKit

// Enum for focus control
enum VideoControlFocus {
    case seekBackward
    case seekForward
    case addMark
    case toggleLoop
    case startTimer
    case clearMarks
}

// View model for video control bar
class VideoControlBarViewModel: ObservableObject {
    // Player
    var player: AVPlayer
    
    // Video URL
    let videoURL: URL
    
    // MARK: - Published Properties
    
    // Playback state
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    // Loop state
    @Published var isLooping = false
    @Published var loopMarks: [Double] = []
    @Published var currentSegmentIndex = 0
    
    // Timer state
    @Published var isTimerRunning = false
    @Published var timerSeconds = 0
    @Published var loopTimerActive = false
    @Published var loopTimerSeconds = 0
    
    // MARK: - Non-Published Properties
    
    // Settings
    var seekStepSize: Double = 5.0
    var largeSeekMultiplier = 5.0
    
    // Timers
    private var timerUpdateTimer: Timer?
    private var loopTimer: Timer?
    
    // Observe player time
    private var timeObserver: Any?
    
    // MARK: - Initialization
    
    init(player: AVPlayer, videoURL: URL) {
        self.player = player
        self.videoURL = videoURL
        
        // Set up time observer
        setupTimeObserver()
        
        // Load any saved marks
        loadMarks()
    }
    
    deinit {
        // Remove time observer
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        
        // Invalidate timers
        timerUpdateTimer?.invalidate()
        loopTimer?.invalidate()
    }
    
    // MARK: - Time Observer
    
    private func setupTimeObserver() {
        // Create a time observer that fires every half second
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // Get the current time
            let seconds = time.seconds
            if seconds.isFinite {
                self.currentTime = seconds
                
                // Check if we're looping and need to jump back
                if self.isLooping {
                    self.checkLoopBounds()
                }
            }
        }
    }
    
    // MARK: - Playback Controls
    
    func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }
    
    func seekBackward() {
        let newTime = max(0, currentTime - seekStepSize)
        seek(to: newTime)
    }
    
    func seekForward() {
        let newTime = min(duration, currentTime + seekStepSize)
        seek(to: newTime)
    }
    
    func seekLargeBackward() {
        let newTime = max(0, currentTime - (seekStepSize * largeSeekMultiplier))
        seek(to: newTime)
    }
    
    func seekLargeForward() {
        let newTime = min(duration, currentTime + (seekStepSize * largeSeekMultiplier))
        seek(to: newTime)
    }
    
    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }
    
    // MARK: - Loop Controls
    
    // Add a mark at the current position
    func addMark() {
        // Round to 2 decimal places for precision
        let roundedTime = (currentTime * 100).rounded() / 100
        
        // Check if a mark already exists at this time
        if !loopMarks.contains(where: { abs($0 - roundedTime) < 0.1 }) {
            // Add the mark and sort
            loopMarks.append(roundedTime)
            loopMarks.sort()
            
            // Save marks
            saveMarks()
        }
    }
    
    func removeMark() {
        guard !loopMarks.isEmpty else { return }
        
        // Find the closest mark
        if let (index, distance) = findClosestMark(), distance < 1.0 {
            // Remove the mark
            loopMarks.remove(at: index)
            
            // If we were looping, we might need to adjust
            if isLooping && loopMarks.count < 2 {
                isLooping = false
            }
            
            // Save marks
            saveMarks()
        }
    }
    
    func clearMarks() {
        // Stop looping if active
        isLooping = false
        
        // Clear all marks
        loopMarks.removeAll()
        
        // Save (empty) marks
        saveMarks()
    }
    
    func toggleLoop() {
        // Need at least 2 marks to loop
        guard loopMarks.count >= 2 else { return }
        
        isLooping.toggle()
        
        if isLooping {
            // Find the current segment
            currentSegmentIndex = findCurrentSegment()
            
            // Ensure we're within the segment
            let segmentStart = getCurrentSegmentStart()
            let segmentEnd = getCurrentSegmentEnd()
            
            if currentTime < segmentStart || currentTime >= segmentEnd {
                // Seek to the start of the segment
                seek(to: segmentStart)
            }
        }
    }
    
    // MARK: - Jump Between Marks
    
    func jumpToPreviousMark() {
        guard !loopMarks.isEmpty else { return }
        
        // Find the first mark that is before the current time
        for i in (0..<loopMarks.count).reversed() {
            if loopMarks[i] < currentTime - 0.1 {
                // Found a previous mark
                seek(to: loopMarks[i])
                return
            }
        }
        
        // If no previous mark found, loop to the last mark
        seek(to: loopMarks.last!)
    }
    
    func jumpToNextMark() {
        guard !loopMarks.isEmpty else { return }
        
        // Find the first mark that is after the current time
        for mark in loopMarks {
            if mark > currentTime + 0.1 {
                // Found a next mark
                seek(to: mark)
                return
            }
        }
        
        // If no next mark found, loop to the first mark
        seek(to: loopMarks.first!)
    }
    
    // MARK: - Segment Navigation
    
    func findCurrentSegment() -> Int {
        guard loopMarks.count >= 2 else { return 0 }
        
        // Find which segment we're in
        for i in 0..<(loopMarks.count - 1) {
            if currentTime >= loopMarks[i] && currentTime < loopMarks[i + 1] {
                return i
            }
        }
        
        // Default to the first segment
        return 0
    }
    
    func previousSegment() {
        guard isLooping && loopMarks.count >= 2 else { return }
        
        // Move to previous segment
        currentSegmentIndex = (currentSegmentIndex - 1 + (loopMarks.count - 1)) % (loopMarks.count - 1)
        
        // Seek to the start of the segment
        seek(to: getCurrentSegmentStart())
    }
    
    func nextSegment() {
        guard isLooping && loopMarks.count >= 2 else { return }
        
        // Move to next segment
        currentSegmentIndex = (currentSegmentIndex + 1) % (loopMarks.count - 1)
        
        // Seek to the start of the segment
        seek(to: getCurrentSegmentStart())
    }
    
    func getCurrentSegmentStart() -> Double {
        guard loopMarks.count >= 2 && currentSegmentIndex < loopMarks.count - 1 else { return 0 }
        return loopMarks[currentSegmentIndex]
    }
    
    func getCurrentSegmentEnd() -> Double {
        guard loopMarks.count >= 2 && currentSegmentIndex < loopMarks.count - 1 else { return duration }
        return loopMarks[currentSegmentIndex + 1]
    }
    
    func formatCurrentSegment() -> String {
        if loopMarks.count < 2 {
            return "No Loop"
        }
        
        let total = loopMarks.count - 1
        return "Segment \(currentSegmentIndex + 1)/\(total)"
    }
    
    // MARK: - Loop Logic
    
    private func checkLoopBounds() {
        guard isLooping && loopMarks.count >= 2 else { return }
        
        let segmentStart = getCurrentSegmentStart()
        let segmentEnd = getCurrentSegmentEnd()
        
        // If we've reached the end of the segment, loop back to the start
        if currentTime >= segmentEnd || currentTime < segmentStart {
            seek(to: segmentStart)
            
            // If there's a timer running, increment the loop count
            if loopTimerActive {
                loopTimerSeconds += 1
            }
        }
    }
    
    // MARK: - Timer Controls
    
    func startTimer() {
        // Toggle timer on/off
        isTimerRunning.toggle()
        
        if isTimerRunning {
            // Start countdown from 5 minutes
            timerSeconds = 5 * 60
            
            // Create timer to update every second
            timerUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // Decrement timer
                self.timerSeconds -= 1
                
                // Check if timer expired
                if self.timerSeconds <= 0 {
                    // Stop timer
                    self.isTimerRunning = false
                    self.timerUpdateTimer?.invalidate()
                    
                    // Stop playback
                    self.player.pause()
                    self.isPlaying = false
                    
                    // Stop looping
                    self.isLooping = false
                }
            }
        } else {
            // Stop timer
            timerUpdateTimer?.invalidate()
        }
    }
    
    func startLoopTimer(seconds: Int = 5) {
        loopTimerActive = true
        loopTimerSeconds = 0
        
        // Create timer to check loop count
        loopTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Check if the specified number of loops has occurred
            if self.loopTimerSeconds >= seconds {
                // Stop the loop timer
                self.loopTimerActive = false
                self.loopTimer?.invalidate()
                
                // Continue playback but don't loop anymore
                self.isLooping = false
            }
        }
    }
    
    func formatLoopTimeRemaining() -> String {
        let remaining = max(0, 5 - loopTimerSeconds)
        return "\(remaining) loops"
    }
    
    // MARK: - Update State
    
    func updatePlayerState() {
        // Update playing state
        isPlaying = (player.rate != 0)
        
        // Update current time
        if let currentItem = player.currentItem {
            let seconds = CMTimeGetSeconds(currentItem.currentTime())
            if seconds.isFinite {
                currentTime = seconds
            }
        }
    }
    
    func updateTimerState() {
        // Nothing to do here, the timer updates itself
    }
    
    // MARK: - Formatting
    
    func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    // MARK: - Save/Load Marks
    
    private func saveMarks() {
        // Create a key using the video URL
        let key = "marks_" + videoURL.absoluteString.hash.description
        
        // Save the loop marks
        UserDefaults.standard.set(loopMarks, forKey: key)
    }
    
    private func loadMarks() {
        // Create a key using the video URL
        let key = "marks_" + videoURL.absoluteString.hash.description
        
        // Load the loop marks
        if let marks = UserDefaults.standard.array(forKey: key) as? [Double] {
            loopMarks = marks
        }
    }
    
    // MARK: - Mark Adjustment Features
    
    // Check if the current position is exactly on an existing mark
    func isOnExistingMark() -> Bool {
        // Round to 2 decimal places for precision
        let roundedTime = (currentTime * 100).rounded() / 100
        
        // Check if a mark exists at this time
        return loopMarks.contains(where: { abs($0 - roundedTime) < 0.1 })
    }
    
    // Adjust the current mark backward by specified seconds
    func adjustCurrentMarkBackward(by seconds: Double) {
        // Find the closest mark to current time
        guard !loopMarks.isEmpty else { return }
        
        if let (index, _) = findClosestMark() {
            // Ensure we don't go below 0
            let newTime = max(0, loopMarks[index] - seconds)
            loopMarks[index] = newTime
            
            // If we're looping, we need to update the player position
            if isLooping && (index == currentSegmentIndex || index == currentSegmentIndex + 1) {
                // Seek to the new mark position if it's a segment boundary
                player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                currentTime = newTime
            } else {
                // Just update the playhead position
                player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                currentTime = newTime
            }
            
            // Save the updated marks
            saveMarks()
        }
    }
    
    // Adjust the current mark forward by specified seconds
    func adjustCurrentMarkForward(by seconds: Double) {
        // Find the closest mark to current time
        guard !loopMarks.isEmpty else { return }
        
        if let (index, _) = findClosestMark() {
            // Ensure we don't go beyond video duration
            let newTime = min(duration, loopMarks[index] + seconds)
            loopMarks[index] = newTime
            
            // If we're looping, we need to update the player position
            if isLooping && (index == currentSegmentIndex || index == currentSegmentIndex + 1) {
                // Seek to the new mark position if it's a segment boundary
                player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                currentTime = newTime
            } else {
                // Just update the playhead position
                player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                currentTime = newTime
            }
            
            // Save the updated marks
            saveMarks()
        }
    }
    
    // Find the mark closest to the current time
    func findClosestMark() -> (Int, Double)? {
        guard !loopMarks.isEmpty else { return nil }
        
        var closestIndex = 0
        var closestDistance = Double.infinity
        
        for (index, markTime) in loopMarks.enumerated() {
            let distance = abs(markTime - currentTime)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        
        return (closestIndex, closestDistance)
    }
    
    // Move to the nearest mark (used when entering mark adjustment mode)
    // We'll use this after adding a mark too, so it should find the exact match first
    func moveToNearestMark() {
        // First check if we're exactly on a mark already (which happens when we just added one)
        let roundedTime = (currentTime * 100).rounded() / 100
        
        // Try to find an exact match first (for newly added marks)
        if let exactIndex = loopMarks.firstIndex(where: { abs($0 - roundedTime) < 0.01 }) {
            // We're already on a mark, just ensure the player is exactly at that position
            let markTime = loopMarks[exactIndex]
            player.seek(to: CMTime(seconds: markTime, preferredTimescale: 600))
            currentTime = markTime
            return
        }
        
        // Otherwise, find the closest mark
        if let (index, _) = findClosestMark() {
            let markTime = loopMarks[index]
            player.seek(to: CMTime(seconds: markTime, preferredTimescale: 600))
            currentTime = markTime
        }
    }
}
