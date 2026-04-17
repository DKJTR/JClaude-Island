//
//  MediaClosedView.swift
//  DynamicIsland
//
//  Compact media indicators for the closed notch wings
//

import AppKit
import SwiftUI

// MARK: - Left Wing (album art + track info)

struct MediaClosedLeftWing: View {
    @ObservedObject var mediaService: MediaRemoteService

    var body: some View {
        if let np = mediaService.nowPlaying, np.hasContent {
            HStack(alignment: .center, spacing: 5) {
                // Album art thumbnail
                albumArt(np)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Scrolling track info
                MarqueeText(
                    np.displayText,
                    font: .system(size: 10, weight: .medium),
                    color: .white.opacity(0.85),
                    speed: 25
                )
                .frame(height: 20)
            }
            .padding(.leading, 6)
        }
    }

    @ViewBuilder
    private func albumArt(_ np: NowPlayingInfo) -> some View {
        Group {
            if let data = np.artworkData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.4))
                    }
            }
        }
        .id(np.title)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: np.title)
    }
}

// MARK: - Right Wing (sound animation)

struct MediaClosedRightWing: View {
    @ObservedObject var mediaService: MediaRemoteService

    var body: some View {
        if let np = mediaService.nowPlaying, np.hasContent {
            HStack(spacing: 0) {
                Spacer()
                if np.isPlaying {
                    MusicBarsIcon(size: 14)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.trailing, 6)
        }
    }
}

// MARK: - Music Bars Animation (5-bar organic waveform)

struct MusicBarsIcon: View {
    let size: CGFloat

    @State private var animating = false

    // Each bar: (delay, duration, baseHeight, peakHeight)
    // Staggered timing and varied ranges for organic feel
    private let barConfigs: [(delay: Double, duration: Double, base: CGFloat, peak: CGFloat)] = [
        (0.0,  0.52, 0.25, 0.65),
        (0.12, 0.44, 0.35, 0.85),
        (0.06, 0.48, 0.20, 0.95),
        (0.18, 0.40, 0.40, 0.70),
        (0.10, 0.55, 0.30, 0.60),
    ]

    var body: some View {
        HStack(spacing: 1.2) {
            ForEach(0..<5, id: \.self) { index in
                let config = barConfigs[index]
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(TerminalColors.green)
                    .frame(width: 1.8, height: size * (animating ? config.peak : config.base))
                    .animation(
                        .easeInOut(duration: config.duration)
                            .repeatForever(autoreverses: true)
                            .delay(config.delay),
                        value: animating
                    )
            }
        }
        .frame(width: size, height: size)
        .onAppear { animating = true }
    }
}
