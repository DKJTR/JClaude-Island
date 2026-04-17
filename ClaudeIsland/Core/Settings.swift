//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Foundation

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
