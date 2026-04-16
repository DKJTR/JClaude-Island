//
//  SeekableProgressBar.swift
//  DynamicIsland
//
//  Draggable progress bar for seeking through tracks
//

import SwiftUI

struct SeekableProgressBar: View {
    let progress: Double
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    private var displayProgress: Double {
        isDragging ? dragFraction : max(0, min(1, progress))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: isDragging ? 6 : 3)

                // Fill
                Capsule()
                    .fill(TerminalColors.green.opacity(isDragging ? 0.9 : 0.7))
                    .frame(
                        width: max(0, geo.size.width * CGFloat(displayProgress)),
                        height: isDragging ? 6 : 3
                    )

                // Thumb (only when dragging)
                if isDragging {
                    Circle()
                        .fill(TerminalColors.green)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, min(geo.size.width - 10, geo.size.width * CGFloat(dragFraction) - 5)))
                }
            }
            .frame(height: isDragging ? 10 : 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragFraction = max(0, min(1, Double(value.location.x / geo.size.width)))
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, Double(value.location.x / geo.size.width)))
                        onSeek(fraction)
                        isDragging = false
                    }
            )
        }
        .frame(height: isDragging ? 10 : 6)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }
}
