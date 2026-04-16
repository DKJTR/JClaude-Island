//
//  MediaPlayerView.swift
//  DynamicIsland
//
//  Full media player view for the expanded notch
//

import AppKit
import SwiftUI

struct MediaPlayerView: View {
    @ObservedObject var mediaService: MediaRemoteService

    var body: some View {
        if let nowPlaying = mediaService.nowPlaying, nowPlaying.hasContent {
            VStack(spacing: 16) {
                // Album artwork + track info
                HStack(spacing: 14) {
                    // Artwork
                    artworkView(nowPlaying)
                        .frame(width: 72, height: 72)

                    // Track info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(nowPlaying.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Text(nowPlaying.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)

                        if !nowPlaying.album.isEmpty {
                            Text(nowPlaying.album)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 4)

                // Progress bar
                if nowPlaying.duration > 0 {
                    progressBar(nowPlaying)
                }

                // Controls
                controlsRow(nowPlaying)

                // Source app
                if !nowPlaying.appName.isEmpty {
                    HStack {
                        Spacer()
                        appIcon(nowPlaying)
                        Text(nowPlaying.appName)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 8)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white.opacity(0.2))
                Text("Nothing playing")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 40)
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(_ nowPlaying: NowPlayingInfo) -> some View {
        if let data = nowPlaying.artworkData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.white.opacity(0.2))
                }
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressBar(_ nowPlaying: NowPlayingInfo) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)

                    // Progress fill
                    Capsule()
                        .fill(TerminalColors.cyan)
                        .frame(
                            width: max(0, geo.size.width * progress(nowPlaying)),
                            height: 3
                        )
                }
            }
            .frame(height: 3)

            // Time labels
            HStack {
                Text(formatTime(nowPlaying.estimatedElapsed))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(formatTime(nowPlaying.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 4)
    }

    private func progress(_ nowPlaying: NowPlayingInfo) -> CGFloat {
        guard nowPlaying.duration > 0 else { return 0 }
        return CGFloat(nowPlaying.estimatedElapsed / nowPlaying.duration)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Controls

    @ViewBuilder
    private func controlsRow(_ nowPlaying: NowPlayingInfo) -> some View {
        HStack(spacing: 32) {
            Button { mediaService.previousTrack() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button { mediaService.togglePlayPause() } label: {
                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button { mediaService.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - App Icon

    @ViewBuilder
    private func appIcon(_ nowPlaying: NowPlayingInfo) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: nowPlaying.bundleIdentifier),
           let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}
