import SwiftUI
import AVKit

struct VideoProgressBarView: View {
    // MARK: - Properties
    @ObservedObject var viewModel: VideoControlBarViewModel
    
    // MARK: - UI Constants
    private enum UI {
        static let trackHeight: CGFloat = 8
        static let trackCornerRadius: CGFloat = 4
        static let containerHeight: CGFloat = 16
        static let markIndicatorWidth: CGFloat = 2
        static let markIndicatorHeight: CGFloat = 16
        static let positionMarkerSize: CGFloat = 12
        static let segmentNumberOffset: CGFloat = 8
        static let segmentHighlightHeight: CGFloat = 14
        static let verticalPadding: CGFloat = 2
        static let horizontalPadding: CGFloat = 16
        static let spacing: CGFloat = 2
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: UI.spacing) {
            progressBar
            timeIndicators
        }
        .padding(.vertical, UI.verticalPadding)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - UI Components
    
    /// Progress bar with marks and position indicator
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                backgroundTrack
                
                // Highlight current segment if looping
                if viewModel.isLooping && viewModel.loopMarks.count >= 2 {
                    segmentHighlight(in: geometry)
                }
                
                // Progress fill
                progressFill(in: geometry)
                
                // Mark indicators
                ForEach(viewModel.loopMarks.indices, id: \.self) { index in
                    markIndicator(for: index, in: geometry)
                }
                
                // Current position marker
                positionMarker(in: geometry)
            }
        }
        .frame(height: UI.containerHeight)
    }
    
    /// Background track of the progress bar
    private var backgroundTrack: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.5))
            .frame(height: UI.trackHeight)
            .cornerRadius(UI.trackCornerRadius)
    }
    
    /// Filled portion of the progress bar
    private func progressFill(in geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(Color.blue)
            .frame(
                width: calculateWidth(progress: viewModel.currentTime / max(viewModel.duration, 1), in: geometry),
                height: UI.trackHeight
            )
            .cornerRadius(UI.trackCornerRadius)
    }
    
    /// Highlight for the current segment in loop mode
    private func segmentHighlight(in geometry: GeometryProxy) -> some View {
        let segmentStart = viewModel.getCurrentSegmentStart()
        let segmentEnd = viewModel.getCurrentSegmentEnd()
        let startPosition = calculatePosition(time: segmentStart, in: geometry)
        let width = calculateWidth(
            progress: (segmentEnd - segmentStart) / max(viewModel.duration, 1),
            in: geometry
        )
        
        return Rectangle()
            .fill(Color.green.opacity(0.3))
            .frame(width: max(0, width), height: UI.segmentHighlightHeight)
            .position(x: startPosition + width/2, y: UI.containerHeight/2)
    }
    
    /// Mark indicator for a specific mark
    private func markIndicator(for index: Int, in geometry: GeometryProxy) -> some View {
        let mark = viewModel.loopMarks[index]
        let isActiveSegmentBoundary = viewModel.isLooping &&
                                     (index == viewModel.currentSegmentIndex ||
                                      index == viewModel.currentSegmentIndex + 1)
        
        return VStack(spacing: 0) {
            // Segment number above mark
            if index < viewModel.loopMarks.count - 1 {
                Text("\(index + 1)")
                    .font(.system(size: 10))
                    .foregroundColor(
                        viewModel.isLooping && index == viewModel.currentSegmentIndex
                            ? Color.yellow
                            : Color.white
                    )
                    .padding(.bottom, 2)
                    .offset(x: UI.segmentNumberOffset)
            }
            
            // Mark indicator line
            Rectangle()
                .fill(isActiveSegmentBoundary ? Color.yellow : Color.white)
                .frame(width: UI.markIndicatorWidth, height: UI.markIndicatorHeight)
        }
        .position(
            x: calculatePosition(time: mark, in: geometry),
            y: UI.containerHeight/2
        )
    }
    
    /// Current position marker
    private func positionMarker(in geometry: GeometryProxy) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: UI.positionMarkerSize, height: UI.positionMarkerSize)
            .position(
                x: calculatePosition(time: viewModel.currentTime, in: geometry),
                y: UI.containerHeight/2
            )
    }
    
    /// Time indicators showing current time and duration
    private var timeIndicators: some View {
        HStack {
            Text(viewModel.formatTime(viewModel.currentTime))
                .font(.caption)
                .foregroundColor(.white)
            
            Spacer()
            
            if !viewModel.loopMarks.isEmpty {
                Text("\(viewModel.loopMarks.count) marks")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            
            Spacer()
            
            Text(viewModel.formatTime(viewModel.duration))
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, UI.horizontalPadding)
    }
    
    // MARK: - Helper Methods
    
    /// Calculate horizontal position for a time value
    private func calculatePosition(time: Double, in geometry: GeometryProxy) -> CGFloat {
        return CGFloat(time / max(viewModel.duration, 1)) * geometry.size.width
    }
    
    /// Calculate width for a progress value
    private func calculateWidth(progress: Double, in geometry: GeometryProxy) -> CGFloat {
        return CGFloat(progress) * geometry.size.width
    }
}
