import SwiftUI
import AVKit

// The video control bar component
struct VideoControlBarView: View {
    // View model
    @ObservedObject var viewModel: VideoControlBarViewModel
    
    // Focus state
    @FocusState var focusedControl: VideoControlFocus?
    
    // State for confirmation dialog
    @State private var showClearMarksConfirmation = false
    
    // Track double tap timing
    @State private var lastBackwardTapTime: Date? = nil
    @State private var lastForwardTapTime: Date? = nil
    @State private var doubleTapThreshold: TimeInterval = 0.2
    
    // Mark adjustment mode
    @State private var isInMarkAdjustmentMode = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Transport controls (main row)
            HStack(spacing: 12) {
                // Rewind button
                Button {
                    if isInMarkAdjustmentMode {
                        // In mark adjustment mode, move current mark backward by 1 second
                        viewModel.adjustCurrentMarkBackward(by: 1.0)
                    } else {
                        // Check for double tap
                        if let lastTap = lastBackwardTapTime,
                           Date().timeIntervalSince(lastTap) < doubleTapThreshold {
                            // Double tap detected - jump to previous mark
                            viewModel.jumpToPreviousMark()
                            // Reset timing
                            lastBackwardTapTime = nil
                        } else {
                            // Normal seek
                            viewModel.seekBackward()
                            // Record tap time
                            lastBackwardTapTime = Date()
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                        if isInMarkAdjustmentMode {
                            Text("-1s")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                    }
                    .frame(width: 50, height: 40)
                    .background(focusedControl == .seekBackward ? Color.blue : Color.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .seekBackward)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if !isInMarkAdjustmentMode {
                                viewModel.seekLargeBackward()
                            }
                        }
                )
                                
                // Fast-forward button
                Button {
                    if isInMarkAdjustmentMode {
                        // In mark adjustment mode, move current mark forward by 1 second
                        viewModel.adjustCurrentMarkForward(by: 1.0)
                    } else {
                        // Check for double tap
                        if let lastTap = lastForwardTapTime,
                           Date().timeIntervalSince(lastTap) < doubleTapThreshold {
                            // Double tap detected - jump to next mark
                            viewModel.jumpToNextMark()
                            // Reset timing
                            lastForwardTapTime = nil
                        } else {
                            // Normal seek
                            viewModel.seekForward()
                            // Record tap time
                            lastForwardTapTime = Date()
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                        if isInMarkAdjustmentMode {
                            Text("+1s")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                    }
                    .frame(width: 50, height: 40)
                    .background(focusedControl == .seekForward ? Color.blue : Color.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .seekForward)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if !isInMarkAdjustmentMode {
                                viewModel.seekLargeForward()
                            }
                        }
                )
            }
                        
            // Separator
            Divider()
                .frame(height: 30)
            
            // Loop controls
            HStack(spacing: 8) {
                // Add Mark button
                Button {
                    if isInMarkAdjustmentMode {
                        // If already in adjustment mode, exit it
                        isInMarkAdjustmentMode = false
                    } else {
                        // Check if we're exactly on a mark
                        if viewModel.isOnExistingMark() {
                            // If we're on a mark, remove it
                            viewModel.removeMark()
                        } else {
                            // Add a mark and enter adjustment mode
                            viewModel.addMark()
                            isInMarkAdjustmentMode = true
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isInMarkAdjustmentMode ? "bookmark.circle.fill" : "bookmark.fill")
                            .font(.system(size: 20))
                        if isInMarkAdjustmentMode {
                            Text("Adjusting")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(
                        focusedControl == .addMark
                        ? Color.blue
                        : (isInMarkAdjustmentMode ? Color.orange.opacity(0.7) : Color.black.opacity(0.7))
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .addMark)
                
                // Toggle Loop button
                Button {
                    viewModel.toggleLoop()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 20))
                    }
                    .frame(width: 40, height: 40)
                    .background(
                        focusedControl == .toggleLoop
                        ? Color.blue
                        : (viewModel.isLooping ? Color.green.opacity(0.7) : Color.black.opacity(0.7))
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .toggleLoop)
                .disabled(viewModel.loopMarks.count < 2)
            }
            
            // Loop indicators (when active)
            if viewModel.isLooping {
                HStack(spacing: 4) {
                    Text(viewModel.formatCurrentSegment())
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    if viewModel.loopTimerActive {
                        Text("(\(viewModel.formatLoopTimeRemaining()))")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
            }
            
            // Mark adjustment mode indicator
            if isInMarkAdjustmentMode {
                Text("Mark Adjustment Mode")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
            }
            
            Spacer()
            
            // TIMER CONTROLS
            HStack(spacing: 10) {
                // Timer display
                // Fix: Direct access to timerSeconds and format it locally
                Text(formatTimerTime(viewModel.timerSeconds))
                    .font(.caption)
                    .foregroundColor(viewModel.isTimerRunning ? .yellow : .gray)
                    .frame(minWidth: 70)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                
                // Start Timer button
                Button {
                    viewModel.startTimer()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 20))
                    }
                    .frame(width: 50, height: 40)
                    .background(
                        focusedControl == .startTimer
                        ? Color.blue
                        : (viewModel.isTimerRunning ? Color.yellow.opacity(0.7) : Color.black.opacity(0.7))
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .startTimer)
                
                // Clear Marks button (moved to right side)
                Button {
                    // Show confirmation dialog instead of immediately clearing
                    showClearMarksConfirmation = true
                } label: {
                    Text("Clear All Marks")
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                        .background(focusedControl == .clearMarks ? Color.blue : Color.black.opacity(0.7))
                        .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .clearMarks)
                .disabled(viewModel.loopMarks.isEmpty)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
        .alert("Clear All Marks", isPresented: $showClearMarksConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                viewModel.clearMarks()
            }
        } message: {
            Text("Are you sure you want to clear all marks? This action cannot be undone.")
        }
        .onChange(of: isInMarkAdjustmentMode) { newValue in
            if newValue {
                // When entering mark adjustment mode, ensure we're on a mark
                viewModel.moveToNearestMark()
            }
        }
    }
    
    // Fix: Add the formatting function directly to the view
    private func formatTimerTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
