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
                // Background track (always tall enough to tap)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: isDragging ? 8 : 4)

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(TerminalColors.green.opacity(isDragging ? 0.9 : 0.7))
                    .frame(
                        width: max(0, geo.size.width * CGFloat(displayProgress)),
                        height: isDragging ? 8 : 4
                    )

                // Thumb (always visible, larger when dragging)
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: isDragging ? 14 : 8, height: isDragging ? 14 : 8)
                    .shadow(color: TerminalColors.green.opacity(0.3), radius: isDragging ? 4 : 0)
                    .offset(x: max(0, min(
                        geo.size.width - (isDragging ? 14 : 8),
                        geo.size.width * CGFloat(displayProgress) - (isDragging ? 7 : 4)
                    )))
            }
            .frame(maxHeight: .infinity)
            // Large invisible tap area (24pt tall)
            .contentShape(Rectangle())
            .simultaneousGesture(
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
            // Also handle taps (single click to jump)
            .onTapGesture { location in
                let fraction = max(0, min(1, Double(location.x / geo.size.width)))
                onSeek(fraction)
            }
        }
        .frame(height: 24) // 24pt hit area
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }
}
