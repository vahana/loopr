import SwiftUI
import AVKit

// The video control bar component
struct VideoControlBarView: View {
    // View model
    @ObservedObject var viewModel: VideoControlBarViewModel
    
    // Focus state
    @FocusState var focusedControl: VideoControlFocus?
    
    var body: some View {
        HStack(spacing: 12) {
            // Transport controls (main row)
            HStack(spacing: 12) {
                // Play/Pause button
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                    }
                    .frame(width: 50, height: 40)
                    .background(focusedControl == .play ? Color.blue : Color.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .play)

                // Rewind button
                Button {
                    viewModel.seekBackward()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                    }
                    .frame(width: 50, height: 40)
                    .background(focusedControl == .seekBackward ? Color.blue : Color.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .seekBackward)
                                
                // Fast-forward button
                Button {
                    viewModel.seekForward()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                    }
                    .frame(width: 50, height: 40)
                    .background(focusedControl == .seekForward ? Color.blue : Color.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .seekForward)
            }
                        
            // Separator
            Divider()
                .frame(height: 30)
            
            // Loop controls
            HStack(spacing: 8) {
                // Set Start button
                Button {
                    viewModel.setLoopStart()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 20))
                    }
                    .frame(width: 40, height: 40)
                    .background(focusedControl == .loopStart ? Color.blue : Color.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .loopStart)
                
                // Set End button
                Button {
                    viewModel.setLoopEnd()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 20))
                    }
                    .frame(width: 40, height: 40)
                    .background(focusedControl == .loopEnd ? Color.blue : Color.black.opacity(0.7))
                    .cornerRadius(6)
                }
                .buttonStyle(.card)
                .focused($focusedControl, equals: .loopEnd)
                
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
            }
            
            // Loop indicators (when active)
            if viewModel.isLooping {
                HStack(spacing: 4) {
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
            
            Spacer()
            
            // TIMER CONTROLS
            HStack(spacing: 10) {
                // Timer display
                Text(viewModel.formatTimerTime(viewModel.timerSeconds))
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
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
}
