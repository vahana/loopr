import SwiftUI

struct LoopCountdownOverlayView: View {
    @ObservedObject var viewModel: VideoControlBarViewModel
    
    private enum UI {
        static let overlaySize: CGFloat = 120
        static let fontSize: CGFloat = 48
        static let cornerRadius: CGFloat = 16
        static let shadowRadius: CGFloat = 8
        static let animationDuration: Double = 0.3
    }
    
    // Pulsate during the last 5 seconds of loop countdown
    private var shouldPulsate: Bool {
        viewModel.loopTimerActive && viewModel.loopTimeRemaining <= 5.0
    }
    
    var body: some View {
        if viewModel.isLooping && (viewModel.loopTimerActive || viewModel.isTransitionCounterActive) {
            ZStack {
                // Semi-transparent background circle
                Circle()
                    .fill(shouldPulsate ? Color.yellow.opacity(0.8) : Color.black.opacity(0.7))
                    .frame(width: UI.overlaySize, height: UI.overlaySize)
                    .shadow(radius: UI.shadowRadius)
                    .animation(.easeInOut(duration: UI.animationDuration), value: shouldPulsate)
                
                // Countdown ring and content
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                        .frame(width: UI.overlaySize - 16, height: UI.overlaySize - 16)
                    
                    if viewModel.loopTimerActive {
                        // Loop countdown ring
                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.loopTimeRemaining / 30.0))
                            .stroke(
                                Color.yellow,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: UI.overlaySize - 16, height: UI.overlaySize - 16)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: viewModel.loopTimeRemaining)
                        
                        // Loop countdown number
                        Text("\(Int(viewModel.loopTimeRemaining))")
                            .font(.system(size: UI.fontSize, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .animation(.easeInOut(duration: UI.animationDuration), value: viewModel.loopTimeRemaining)
                    } else if viewModel.isTransitionCounterActive {
                        // Transition counter ring
                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.transitionTimeRemaining / viewModel.transitionDuration))
                            .stroke(
                                Color.blue.opacity(0.8),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: UI.overlaySize - 16, height: UI.overlaySize - 16)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: viewModel.transitionTimeRemaining)
                        
                        // Transition counter number
                        Text("\(Int(viewModel.transitionTimeRemaining))")
                            .font(.system(size: UI.fontSize, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .animation(.easeInOut(duration: UI.animationDuration), value: viewModel.transitionTimeRemaining)
                    }
                }
            }
            .scaleEffect(shouldPulsate ? 1.1 : 1.0)
            .opacity(shouldPulsate ? 0.8 : 1.0)
            .animation(
                shouldPulsate ? 
                    .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : 
                    .easeInOut(duration: UI.animationDuration), 
                value: shouldPulsate
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}