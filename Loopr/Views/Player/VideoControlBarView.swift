import SwiftUI
import AVKit

struct VideoControlBarView: View {
    // MARK: - Properties
    @ObservedObject var viewModel: VideoControlBarViewModel
    @FocusState var focusedControl: VideoControlFocus?
    
    // MARK: - State
    @State private var showClearMarksConfirmation = false
    @State private var lastClickTime: [VideoControlFocus: Date] = [:]
    
    // MARK: - UI Constants
    private enum UI {
        static let buttonHeight: CGFloat = 40
        static let seekButtonWidth: CGFloat = 50
        static let controlButtonWidth: CGFloat = 40
        static let cornerRadius: CGFloat = 6
        static let spacing: CGFloat = 12
        static let controlSpacing: CGFloat = 8
        static let doubleClickThreshold: TimeInterval = 0.5  // Slightly longer for tvOS
        static let barPadding: EdgeInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        static let indicatorPadding: EdgeInsets = EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
    }
    
    // MARK: - Body
    var body: some View {
        HStack(spacing: UI.spacing) {
            transportControls
            Divider().frame(height: 30)
            loopControls
            loopIndicators
            Spacer()
            timerControls
        }
        .padding(UI.barPadding)
        .background(Color.black.opacity(0.8))
        .alert("Clear All Marks", isPresented: $showClearMarksConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                viewModel.clearMarks()
            }
        } message: {
            Text("Are you sure you want to clear all marks? This action cannot be undone.")
        }
    }
    
    // MARK: - UI Components
    
    /// Transport controls (rewind/forward)
    private var transportControls: some View {
        HStack(spacing: UI.spacing) {
            // Backward button - tvOS compatible
            Button {
                handleButtonClick(.seekBackward)
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20))
                    .frame(width: UI.seekButtonWidth, height: UI.buttonHeight)
                    .background(buttonBackgroundColor(for: .seekBackward))
                    .cornerRadius(UI.cornerRadius)
            }
            .buttonStyle(.card) // Important for tvOS
            .focused($focusedControl, equals: .seekBackward)
            
            // Forward button - tvOS compatible
            Button {
                handleButtonClick(.seekForward)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .frame(width: UI.seekButtonWidth, height: UI.buttonHeight)
                    .background(buttonBackgroundColor(for: .seekForward))
                    .cornerRadius(UI.cornerRadius)
            }
            .buttonStyle(.card) // Important for tvOS
            .focused($focusedControl, equals: .seekForward)
        }
    }
    
    /// Loop controls (mark/loop toggle)
    private var loopControls: some View {
        HStack(spacing: UI.controlSpacing) {
            controlButton(
                for: .addMark,
                icon: "bookmark.fill",
                action: viewModel.toggleMark
            )
            
            controlButton(
                for: .toggleLoop,
                icon: "repeat",
                action: viewModel.toggleLoop,
                activeColor: viewModel.isLooping ? .green.opacity(0.7) : nil,
                isDisabled: viewModel.loopMarks.count < 2
            )
        }
    }
    
    /// Loop status indicators
    private var loopIndicators: some View {
        Group {
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
                .padding(UI.indicatorPadding)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
            }
        }
    }
    
    /// Timer controls
    private var timerControls: some View {
        HStack(spacing: 10) {
            timerDisplay
            
            controlButton(
                for: .startTimer,
                icon: "timer",
                width: UI.seekButtonWidth,
                action: viewModel.startTimer,
                activeColor: viewModel.isTimerRunning ? .yellow.opacity(0.7) : nil
            )
            
            clearMarksButton
        }
        .padding(.horizontal, 6)
    }
    
    /// Timer display
    private var timerDisplay: some View {
        Text(formatTimerTime(viewModel.timerSeconds))
            .font(.caption)
            .foregroundColor(viewModel.isTimerRunning ? .yellow : .gray)
            .frame(minWidth: 70)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5))
            .cornerRadius(4)
    }
    
    /// Clear marks button
    private var clearMarksButton: some View {
        Button {
            showClearMarksConfirmation = true
        } label: {
            Text("Clear All Marks")
                .font(.system(size: 16))
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .frame(height: UI.buttonHeight)
                .background(buttonBackgroundColor(for: .clearMarks))
                .cornerRadius(UI.cornerRadius)
        }
        .buttonStyle(.card)
        .focused($focusedControl, equals: .clearMarks)
        .disabled(viewModel.loopMarks.isEmpty)
    }
    
    // MARK: - Helper Methods
    
    /// Create a standard control button
    private func controlButton(
        for focus: VideoControlFocus,
        icon: String,
        width: CGFloat = UI.controlButtonWidth,
        action: @escaping () -> Void,
        activeColor: Color? = nil,
        isDisabled: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: width, height: UI.buttonHeight)
                .background(buttonBackgroundColor(for: focus, activeColor: activeColor))
                .cornerRadius(UI.cornerRadius)
        }
        .buttonStyle(.card)  // Important for tvOS
        .focused($focusedControl, equals: focus)
        .disabled(isDisabled)
    }
    
    /// Get background color for a button based on focus state
    private func buttonBackgroundColor(for focus: VideoControlFocus, activeColor: Color? = nil) -> Color {
        focusedControl == focus
            ? Color.blue
            : (activeColor ?? Color.black.opacity(0.7))
    }
    
    /// Format timer time as MM:SS
    private func formatTimerTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    /// Handle button click with double-click detection for tvOS
    private func handleButtonClick(_ control: VideoControlFocus) {
        let now = Date()
        
        // Check if this is a double-click
        if let lastTime = lastClickTime[control],
           now.timeIntervalSince(lastTime) < UI.doubleClickThreshold {
            // Double-click detected
            print("Double-click detected for \(control)")
            lastClickTime[control] = nil // Reset
            
            // Execute double-click action
            if control == .seekBackward {
                viewModel.jumpToPreviousMark()
            } else if control == .seekForward {
                viewModel.jumpToNextMark()
            }
        } else {
            // First click - store time
            lastClickTime[control] = now
            
            // Execute single-click action after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                // Only execute if not a double-click
                if let clickTime = self.lastClickTime[control],
                   clickTime == now { // Same timestamp means no second click has happened
                    DispatchQueue.main.asyncAfter(deadline: .now() + UI.doubleClickThreshold) {
                        // Check again if the timestamp is still the same
                        if self.lastClickTime[control] == now {
                            print("Single-click action for \(control)")
                            // Execute single-click action
                            if control == .seekBackward {
                                self.viewModel.seekBackward()
                            } else if control == .seekForward {
                                self.viewModel.seekForward()
                            }
                            self.lastClickTime[control] = nil // Reset
                        }
                    }
                }
            }
        }
    }
}

/// Focus state for controls
enum VideoControlFocus: Int {
    case seekBackward, seekForward
    case addMark, toggleLoop
    case startTimer, clearMarks
}
