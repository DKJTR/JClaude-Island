//
//  CompactMediaRow.swift
//  DynamicIsland
//
//  Compact media player row for the expanded stacked layout
//

import AppKit
import SwiftUI

struct CompactMediaRow: View {
    @ObservedObject var mediaService: MediaRemoteService

    var body: some View {
        if let nowPlaying = mediaService.nowPlaying, nowPlaying.hasContent {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    // Album art
                    albumArt(nowPlaying)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Track info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(nowPlaying.artist)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 16) {
                        Button { mediaService.previousTrack() } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button { mediaService.togglePlayPause() } label: {
                            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button { mediaService.nextTrack() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Seekable progress bar with time labels
                if nowPlaying.duration > 0 {
                    SeekableProgressBar(
                        progress: nowPlaying.estimatedElapsed / nowPlaying.duration,
                        onSeek: { fraction in mediaService.seekTo(fraction: fraction) }
                    )

                    HStack {
                        Text(formatTime(nowPlaying.estimatedElapsed))
                            .font(.system(size: 9, weight: .regular).monospacedDigit())
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Text(formatTime(nowPlaying.duration))
                            .font(.system(size: 9, weight: .regular).monospacedDigit())
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.top, -2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    @ViewBuilder
    private func albumArt(_ nowPlaying: NowPlayingInfo) -> some View {
        Group {
            if let data = nowPlaying.artworkData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(0.3))
                    }
            }
        }
        .id(nowPlaying.title)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: nowPlaying.title)
    }
}
