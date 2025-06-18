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
                // Add this line to restore focus after clearing marks
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.focusedControl = .seekForward
                }
            }
        } message: {
            Text("Are you sure?")
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
            
            // Seek step toggle button
            Button {
                viewModel.toggleSeekStepSize()
            } label: {
                Text(viewModel.formatSeekStepSize())
                    .font(.system(size: 14))
                    .frame(width: UI.seekButtonWidth, height: UI.buttonHeight)
                    .background(buttonBackgroundColor(for: .seekStepToggle))
                    .cornerRadius(UI.cornerRadius)
            }
            .buttonStyle(.card)
            .focused($focusedControl, equals: .seekStepToggle)
            
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
        
    /// Loop status indicators
    private var loopIndicators: some View {
        Group {
            if viewModel.isLooping {
                HStack(spacing: 4) {
                    Text(viewModel.formatCurrentSegment())
                        .font(.caption)
                        .foregroundColor(.white)
                    
                }
                .padding(UI.indicatorPadding)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
            }
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
            
            // Fine-tune left button
            controlButton(
                for: .fineTuneLeft,
                icon: "chevron.left",
                width: 60,
                height: 60,
                action: viewModel.finetuneMarkLeft
            )
            
            // Fine-tune right button
            controlButton(
                for: .fineTuneRight,
                icon: "chevron.right",
                width: 60,
                height: 60,
                action: viewModel.finetuneMarkRight
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
    
    /// Timer controls
    private var timerControls: some View {
        HStack(spacing: 10) {
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
    
    private var isOnMark: Bool {
        return viewModel.findMarkNearCurrentTime() != nil
    }
    
    /// Create a standard control button
    private func controlButton(
        for focus: VideoControlFocus,
        icon: String,
        width: CGFloat = UI.controlButtonWidth,
        height: CGFloat = UI.buttonHeight,
        action: @escaping () -> Void,
        activeColor: Color? = nil,
        isDisabled: Bool = false
    ) -> some View {
        let isFinetuneButton = focus == .fineTuneLeft || focus == .fineTuneRight
        
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isFinetuneButton ? 14 : 20))
                .frame(width: width, height: height)
                .background(
                    isFinetuneButton ?
                        (isOnMark ? Color.black.opacity(0.7) : Color.gray.opacity(0.3)) :
                        buttonBackgroundColor(for: focus, activeColor: activeColor)
                )
                .cornerRadius(UI.cornerRadius)
                .opacity(isFinetuneButton && !isOnMark ? 0.5 : 1.0)
        }
        .buttonStyle(.card)  // Important for tvOS
        .focused($focusedControl, equals: focus)
        .disabled(isFinetuneButton ? !isOnMark : isDisabled)
    }
    
    /// Get background color for a button based on focus state
    private func buttonBackgroundColor(for focus: VideoControlFocus, activeColor: Color? = nil) -> Color {
        focusedControl == focus
            ? Color.blue
            : (activeColor ?? Color.black.opacity(0.7))
    }
    
    /// Handle button click with simplified double-click detection for tvOS
    private func handleButtonClick(_ control: VideoControlFocus) {
        let now = Date()
        
        // Check if this is a double-click
        if let lastTime = lastClickTime[control],
           now.timeIntervalSince(lastTime) < UI.doubleClickThreshold {
            // Double-click detected - perform immediately
            print("Double-click detected for \(control)")
            lastClickTime[control] = nil // Reset
            
            // Execute double-click action
            switch control {
            case .seekBackward:
                viewModel.jumpToPreviousMark()
            case .seekForward:
                viewModel.jumpToNextMark()
            default:
                break
            }
        } else {
            // First click - store time
            lastClickTime[control] = now
            
            // Use a simple timer to differentiate single vs double clicks
            DispatchQueue.main.asyncAfter(deadline: .now() + UI.doubleClickThreshold) {
                // If the timestamp is still the same, no second click happened
                if self.lastClickTime[control] == now {
                    // Execute single-click action
                    print("Single-click action for \(control)")
                    switch control {
                    case .seekBackward:
                        self.viewModel.seekBackward()
                    case .seekForward:
                        self.viewModel.seekForward()
                    default:
                        break
                    }
                    self.lastClickTime[control] = nil // Reset
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
    case seekStepToggle
    case fineTuneLeft, fineTuneRight
}
