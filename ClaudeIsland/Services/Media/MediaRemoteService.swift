//
//  MediaRemoteService.swift
//  DynamicIsland
//
//  Now Playing state management via AppleScript (reliable on macOS 26+)
//

import AppKit
import Combine
import Foundation

/// Run an AppleScript via /usr/bin/osascript subprocess. Each call gets a
/// fresh Apple Event connection — bypasses macOS error -609
/// ("Connection is invalid") that bites in-process NSAppleScript when the
/// target app (Spotify, Music) restarts. Returns trimmed stdout, or nil on
/// non-zero exit. Synchronous; call off the main thread.
fileprivate func runViaOSAScript(_ src: String) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", src]
    let outPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

struct NowPlayingInfo: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkData: Data?
    var duration: TimeInterval = 0
    var elapsedTime: TimeInterval = 0
    var playbackRate: Double = 0
    var bundleIdentifier: String = ""
    var timestamp: Date = Date()

    var isPlaying: Bool { playbackRate > 0 }
    var hasContent: Bool { !title.isEmpty }

    var estimatedElapsed: TimeInterval {
        guard isPlaying else { return elapsedTime }
        return min(elapsedTime + Date().timeIntervalSince(timestamp) * playbackRate, duration)
    }

    var displayText: String {
        if artist.isEmpty { return title }
        return "\(artist) — \(title)"
    }

    var appName: String {
        if bundleIdentifier.contains("spotify") { return "Spotify" }
        if bundleIdentifier.contains("Music") { return "Music" }
        return ""
    }
}

@MainActor
class MediaRemoteService: ObservableObject {
    static let shared = MediaRemoteService()

    @Published var nowPlaying: NowPlayingInfo?
    @Published var isActive: Bool = false

    private var pollTimer: Timer?
    private var elapsedTimer: Timer?
    private var lastArtworkUrl: String?
    private var cachedArtwork: Data?

    private init() {}

    // MARK: - Lifecycle

    func startMonitoring() {
        NSLog("[DI-Media] startMonitoring called")
        // Poll every 2 seconds via AppleScript
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetchNowPlaying() }
        }
        // Tick elapsed time display every second
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        fetchNowPlaying()
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Controls

    func togglePlayPause() {
        sendCommand("playpause")
        if var info = nowPlaying {
            info.playbackRate = info.isPlaying ? 0 : 1
            info.timestamp = Date()
            nowPlaying = info
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.fetchNowPlaying() }
    }

    func nextTrack() {
        sendCommand("next track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.fetchNowPlaying() }
    }

    func previousTrack() {
        sendCommand("previous track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.fetchNowPlaying() }
    }

    func seekTo(fraction: Double) {
        guard let np = nowPlaying, np.duration > 0 else { return }
        let position = np.duration * max(0, min(1, fraction))
        guard let app = runningMusicApp() else { return }
        let src = "tell application \"\(app.name)\" to set player position to \(position)"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runViaOSAScript(src)
        }
        // Optimistic UI update
        if var info = nowPlaying {
            info.elapsedTime = position
            info.timestamp = Date()
            nowPlaying = info
        }
    }

    // MARK: - Private

    private func runningMusicApp() -> (name: String, bundleId: String)? {
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == "com.spotify.client" {
                return ("Spotify", "com.spotify.client")
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == "com.apple.Music" {
                return ("Music", "com.apple.Music")
            }
        }
        return nil
    }

    private func sendCommand(_ command: String) {
        guard let app = runningMusicApp() else { return }
        let src = "tell application \"\(app.name)\" to \(command)"
        DispatchQueue.global(qos: .userInitiated).async {
            // Use /usr/bin/osascript subprocess so each call gets a fresh
            // Apple Event connection. Avoids macOS error -609 ("Connection is
            // invalid") when Spotify/Music has restarted under us.
            _ = runViaOSAScript(src)
        }
    }

    private var fetchCount = 0
    private func fetchNowPlaying() {
        fetchCount += 1
        guard let app = runningMusicApp() else {
            if fetchCount <= 3 { NSLog("[DI-Media] fetch #\(fetchCount): no music app running") }
            nowPlaying = nil
            isActive = false
            return
        }
        if fetchCount <= 5 { NSLog("[DI-Media] fetch #\(fetchCount): found \(app.name)") }

        let artLine = app.name == "Spotify"
            ? "set artUrl to artwork url of current track"
            : "set artUrl to \"\""
        let durExpr = app.name == "Spotify"
            ? "(duration of current track) / 1000"
            : "duration of current track"

        let src = """
        tell application "\(app.name)"
            if player state is playing or player state is paused then
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to \(durExpr)
                set p to player position
                set pl to (player state is playing)
                \(artLine)
                return t & "|||" & a & "|||" & al & "|||" & (d as string) & "|||" & (p as string) & "|||" & (pl as string) & "|||" & artUrl
            end if
        end tell
        return ""
        """

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // osascript subprocess avoids macOS error -609 caused by stale
            // in-process Apple Event connections after Spotify/Music restart.
            let output = runViaOSAScript(src) ?? ""

            Task { @MainActor in
                guard let self else { return }
                guard !output.isEmpty else {
                    if self.fetchCount <= 5 { NSLog("[DI-Media] osascript returned empty") }
                    self.nowPlaying = nil
                    self.isActive = false
                    return
                }
                if self.fetchCount <= 5 { NSLog("[DI-Media] osascript result: \(output.prefix(80))") }

                let p = output.components(separatedBy: "|||")
                guard p.count >= 6 else {
                    self.nowPlaying = nil
                    self.isActive = false
                    return
                }

                var info = NowPlayingInfo(
                    title: p[0],
                    artist: p[1],
                    album: p[2],
                    duration: Double(p[3]) ?? 0,
                    elapsedTime: Double(p[4]) ?? 0,
                    playbackRate: p[5] == "true" ? 1.0 : 0.0,
                    bundleIdentifier: app.bundleId,
                    timestamp: Date()
                )

                // Artwork (Spotify only)
                if p.count >= 7, !p[6].isEmpty, let url = URL(string: p[6]) {
                    if self.lastArtworkUrl == p[6], let cached = self.cachedArtwork {
                        info.artworkData = cached
                    } else {
                        self.lastArtworkUrl = p[6]
                        // Fetch async, don't block state update
                        self.nowPlaying = info
                        self.isActive = true
                        Task.detached {
                            if let data = try? Data(contentsOf: url) {
                                await MainActor.run {
                                    self.cachedArtwork = data
                                    if var current = self.nowPlaying {
                                        current.artworkData = data
                                        self.nowPlaying = current
                                    }
                                }
                            }
                        }
                        return
                    }
                }

                self.nowPlaying = info
                self.isActive = true
            }
        }
    }
}
