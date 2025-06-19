import SwiftUI

struct TimerOverlayView: View {
    @ObservedObject var viewModel: VideoControlBarViewModel
    
    private enum UI {
        static let overlaySize: CGFloat = 120
        static let fontSize: CGFloat = 32
        static let shadowRadius: CGFloat = 8
        static let animationDuration: Double = 0.3
    }
    
    var body: some View {
        if viewModel.isTimerRunning {
            ZStack {
                // Semi-transparent background circle
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: UI.overlaySize, height: UI.overlaySize)
                    .shadow(radius: UI.shadowRadius)
                
                // Timer content
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                        .frame(width: UI.overlaySize - 16, height: UI.overlaySize - 16)
                    
                    // Timer display
                    Text(formatTimerTime(viewModel.timerSeconds))
                        .font(.system(size: UI.fontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .animation(.easeInOut(duration: UI.animationDuration), value: viewModel.timerSeconds)
                }
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    /// Format timer time as minutes:seconds (e.g. 1:10)
    private func formatTimerTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}