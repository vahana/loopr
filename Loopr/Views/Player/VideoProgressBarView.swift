// File: Loopr/VideoProgressBarView.swift
import SwiftUI
import AVKit

// Progress bar component for video player
struct VideoProgressBarView: View {
    // View model
    @ObservedObject var viewModel: VideoControlBarViewModel
    
    var body: some View {
        VStack(spacing: 2) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    // Progress fill
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: CGFloat(viewModel.currentTime / max(viewModel.duration, 1)) * geometry.size.width, height: 8)
                        .cornerRadius(4)
                    
                    // Loop start marker (green)
                    if viewModel.duration > 0 {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 3, height: 16)
                            .position(x: CGFloat(viewModel.loopStartTime / viewModel.duration) * geometry.size.width, y: 4)
                    }
                    
                    // Loop end marker (red)
                    if viewModel.duration > 0 {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 3, height: 16)
                            .position(x: CGFloat(viewModel.loopEndTime / viewModel.duration) * geometry.size.width, y: 4)
                    }
                    
                    // Current position marker
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .position(x: CGFloat(viewModel.currentTime / max(viewModel.duration, 1)) * geometry.size.width, y: 4)
                }
            }
            .frame(height: 16)
            
            // Time indicators
            HStack {
                // Current time
                Text(viewModel.formatTime(viewModel.currentTime))
                    .font(.caption)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Total duration
                Text(viewModel.formatTime(viewModel.duration))
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.8))
    }
}
