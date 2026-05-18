//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Where interactive prompts (AskUserQuestion + PermissionRequest) are answered.
/// `island`: questions appear in JClaude Island only; the terminal picker is intercepted.
/// `terminal`: questions stay in the terminal; Island is not involved.
/// `both`: question is mirrored to Island AND the terminal picker also renders.
/// In Both mode, answering in Island injects keystrokes into the terminal picker
/// (which is the canonical answer channel — the hook returns immediately so the
/// terminal picker drives the actual resolution).
enum QuestionRouting: String, CaseIterable, Sendable {
    case island
    case terminal
    case both

    var displayLabel: String {
        switch self {
        case .island:   return "Island"
        case .terminal: return "Terminal"
        case .both:     return "Both"
        }
    }
}

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    /// Posted whenever a visibility-affecting setting changes
    /// (showNowPlaying, showBluetooth). Subscribers re-render to honor it.
    static let didChangeNotification = Notification.Name("AppSettingsDidChange")

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let claudeDirectoryName = "claudeDirectoryName"
        static let showNowPlaying = "showNowPlaying"
        static let showBluetooth = "showBluetooth"
        static let useMediaRemoteBridge = "useMediaRemoteBridge"
        static let questionRouting = "questionRouting"
    }

    // MARK: - Question Routing

    /// File path the Python hook reads to learn the current routing mode. Kept
    /// out of `~/.claude` so it survives `claudeDirectoryName` changes and isn't
    /// confused with Claude config. Single-line file: "island" / "terminal" / "both".
    static let routingFilePath: String = {
        let support = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/ClaudeIsland")
        return (support as NSString).appendingPathComponent("routing.txt")
    }()

    /// Where interactive prompts are answered. See `QuestionRouting`.
    static var questionRouting: QuestionRouting {
        get {
            guard let raw = defaults.string(forKey: Keys.questionRouting),
                  let mode = QuestionRouting(rawValue: raw) else {
                return .island
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.questionRouting)
            writeRoutingFile(newValue)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Write the routing setting to a file the Python hook reads. Idempotent and
    /// safe to call from app launch so the file exists even before the user opens
    /// the menu.
    @discardableResult
    static func writeRoutingFile(_ mode: QuestionRouting) -> Bool {
        let url = URL(fileURLWithPath: routingFilePath)
        let dir = url.deletingLastPathComponent()
        // Diagnostic: trace every call so we can see if the menu toggle fires
        let trace = "[\(ISO8601DateFormatter().string(from: Date()))] writeRoutingFile(\(mode.rawValue))\n"
        if let data = trace.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/claude-island-routing-debug.log")) {
                h.seekToEndOfFile(); try? h.write(contentsOf: data); try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: "/tmp/claude-island-routing-debug.log"))
            }
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try mode.rawValue.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Media & Bluetooth

    /// Whether to show Now Playing info in the notch
    static var showNowPlaying: Bool {
        get { defaults.object(forKey: Keys.showNowPlaying) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Keys.showNowPlaying)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Whether to show Bluetooth devices in the notch
    static var showBluetooth: Bool {
        get { defaults.object(forKey: Keys.showBluetooth) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Keys.showBluetooth)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Whether to attempt the MediaRemote private-framework bridge before
    /// falling back to AppleScript. The bridge unlocks Chrome/YouTube, Brave,
    /// Arc, Edge, Safari, Podcasts, IINA, etc. — but on macOS 26 Tahoe the
    /// SPI returns "Operation not permitted" for ad-hoc-signed builds, so
    /// it's only useful once the app is Developer-ID-signed and notarized.
    /// Default off; flip on after notarization (or to test on older macOS).
    static var useMediaRemoteBridge: Bool {
        get { defaults.object(forKey: Keys.useMediaRemoteBridge) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.useMediaRemoteBridge) }
    }

    // MARK: - Claude Directory

    /// The name of the Claude config directory under the user's home folder.
    /// Defaults to ".claude" (standard Claude Code installation).
    /// Change to ".claude-internal" (or similar) for enterprise/custom distributions.
    static var claudeDirectoryName: String {
        get {
            let value = defaults.string(forKey: Keys.claudeDirectoryName) ?? ""
            return value.isEmpty ? ".claude" : value
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Keys.claudeDirectoryName)
        }
    }
}
