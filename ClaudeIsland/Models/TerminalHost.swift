//
//  TerminalHost.swift
//  ClaudeIsland
//
//  Where a Claude session is running. Determines how to send text into it.
//

import Foundation

/// The host environment running a Claude session
enum TerminalHost: Sendable {
    /// Inside a tmux pane — use `tmux send-keys`
    case tmux(TmuxTarget)

    /// Apple Terminal.app — use System Events keystroke
    case terminalApp(pid: Int)

    /// iTerm2 — use AppleScript `write text`
    case iTerm2(pid: Int)

    /// Known terminal-like app (Cursor, VS Code, Warp, Ghostty, …) — CGEvent fallback
    case bundleApp(bundleId: String, name: String, pid: Int)

    /// Unknown / not running in any detectable terminal
    case unknown
}

extension TerminalHost {
    /// Human-readable label for the input bar placeholder
    var displayName: String {
        switch self {
        case .tmux: return "tmux"
        case .terminalApp: return "Terminal"
        case .iTerm2: return "iTerm2"
        case .bundleApp(_, let name, _): return name
        case .unknown: return "—"
        }
    }

    /// Whether this host supports sending text from the island
    var canSend: Bool {
        switch self {
        case .unknown: return false
        default: return true
        }
    }

    /// Whether sending to this host requires the host window to have focus
    /// (CGEvent fallback targets the frontmost window)
    var requiresFocus: Bool {
        switch self {
        case .tmux, .iTerm2: return false
        case .terminalApp, .bundleApp: return true
        case .unknown: return false
        }
    }
}
