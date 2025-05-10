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
                    
                    // Highlight current segment
                    if viewModel.isLooping && viewModel.loopMarks.count >= 2 {
                        let segmentStart = viewModel.getCurrentSegmentStart()
                        let segmentEnd = viewModel.getCurrentSegmentEnd()
                        let segmentStartPos = CGFloat(segmentStart / max(viewModel.duration, 1)) * geometry.size.width
                        let segmentWidth = CGFloat((segmentEnd - segmentStart) / max(viewModel.duration, 1)) * geometry.size.width
                        
                        Rectangle()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: max(0, segmentWidth), height: 14)
                            .position(x: segmentStartPos + segmentWidth/2, y: 4)
                    }
                    
                    // All mark indicators
                    ForEach(viewModel.loopMarks.indices, id: \.self) { index in
                        let mark = viewModel.loopMarks[index]
                        let isActiveSegmentBoundary = viewModel.isLooping &&
                                                     (index == viewModel.currentSegmentIndex ||
                                                      index == viewModel.currentSegmentIndex + 1)
                        
                        VStack(spacing: 0) {
                            // Segment number (shown above mark between segments)
                            if index < viewModel.loopMarks.count - 1 {
                                Text("\(index + 1)")
                                    .font(.system(size: 10))
                                    .foregroundColor(
                                        viewModel.isLooping && index == viewModel.currentSegmentIndex
                                            ? Color.yellow
                                            : Color.white
                                    )
                                    .padding(.bottom, 2)
                                    .offset(x: 8) // Offset to center between marks
                            }
                            
                            // Mark indicator
                            Rectangle()
                                .fill(isActiveSegmentBoundary ? Color.yellow : Color.white)
                                .frame(width: 2, height: 16)
                        }
                        .position(x: CGFloat(mark / max(viewModel.duration, 1)) * geometry.size.width, y: 4)
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
                
                // Number of marks indicator
                if !viewModel.loopMarks.isEmpty {
                    Text("\(viewModel.loopMarks.count) marks")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
                
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
