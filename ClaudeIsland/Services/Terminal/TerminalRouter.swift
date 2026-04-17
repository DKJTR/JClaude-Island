//
//  TerminalRouter.swift
//  ClaudeIsland
//
//  Detects the host environment for a Claude session and routes "send text"
//  through the right strategy: tmux send-keys, AppleScript (Terminal/iTerm),
//  or CGEvent keystroke injection (Cursor, VS Code, Warp, etc.).
//

import AppKit
import Foundation
import os.log

actor TerminalRouter {
    static let shared = TerminalRouter()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "TerminalRouter")

    private init() {}

    // MARK: - Detection

    /// Walk up the process tree from a Claude pid; pick the first known host we hit.
    /// tmux wins over the GUI app (a Claude session inside tmux inside Terminal.app
    /// should still send via tmux for pane targeting).
    func detectHost(forSessionPid pid: Int?, isInTmux: Bool) async -> TerminalHost {
        guard let pid else { return .unknown }

        // 1. tmux first (works regardless of which GUI terminal hosts the tmux server)
        if isInTmux {
            if let target = await TmuxController.shared.findTmuxTarget(forClaudePid: pid) {
                return .tmux(target)
            }
        }

        // 2. Walk the ancestor process chain to find the GUI terminal app
        let tree = ProcessTreeBuilder.shared.buildTree()
        guard let hostPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: pid, tree: tree),
              let app = NSRunningApplication(processIdentifier: pid_t(hostPid))
        else {
            return .unknown
        }

        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? "App"

        switch bundleId {
        case "com.apple.Terminal":
            return .terminalApp(pid: hostPid)
        case "com.googlecode.iterm2":
            return .iTerm2(pid: hostPid)
        default:
            // Any registered terminal-like bundle, or fall back to generic
            if TerminalAppRegistry.isTerminalBundle(bundleId)
                || TerminalAppRegistry.isTerminal(appName) {
                return .bundleApp(bundleId: bundleId, name: appName, pid: hostPid)
            }
            return .unknown
        }
    }

    // MARK: - Sending

    /// Send `text` (followed by Return) into the host. Returns true on success.
    /// For CGEvent paths, requires Accessibility — caller should have prompted already.
    func sendMessage(_ text: String, to host: TerminalHost) async -> Bool {
        switch host {
        case .tmux(let target):
            return await TmuxController.shared.sendMessage(text, to: target)

        case .iTerm2:
            return await sendViaITerm2(text: text)

        case .terminalApp(let pid):
            return await sendViaTerminalAppKeystroke(text: text, pid: pid)

        case .bundleApp(_, _, let pid):
            return await sendViaCGEvent(text: text, pid: pid)

        case .unknown:
            return false
        }
    }

    // MARK: - Strategies

    /// iTerm2 has a native AppleScript API — write text directly into the focused session.
    /// Doesn't require focus; iTerm routes the text to the foreground session.
    private func sendViaITerm2(text: String) async -> Bool {
        // Escape backslashes and double quotes for AppleScript string literal
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "iTerm2"
          tell current session of current window
            write text "\(escaped)"
          end tell
        end tell
        """
        return await runAppleScript(script)
    }

    /// Terminal.app's `do script` opens a new shell, which is the wrong behavior here.
    /// Use System Events to deliver each character as a keystroke + Return.
    /// Activates the app first so keystrokes land in the right window.
    private func sendViaTerminalAppKeystroke(text: String, pid: Int) async -> Bool {
        await MainActor.run { KeystrokeInjector.activateApp(pid: pid) }
        try? await Task.sleep(for: .milliseconds(180))

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "System Events"
          tell process "Terminal"
            keystroke "\(escaped)"
            key code 36
          end tell
        end tell
        """
        return await runAppleScript(script)
    }

    /// Generic fallback: bring host to front, then post Unicode + Return via CGEvent.
    /// Requires Accessibility. Targets the focused window of `pid`.
    private func sendViaCGEvent(text: String, pid: Int) async -> Bool {
        await MainActor.run { KeystrokeInjector.activateApp(pid: pid) }
        // Give the system time to actually move focus
        try? await Task.sleep(for: .milliseconds(200))
        return await MainActor.run {
            KeystrokeInjector.typeText(text, pressReturn: true)
        }
    }

    /// Run an AppleScript and return success
    private func runAppleScript(_ source: String) async -> Bool {
        await Task.detached {
            var err: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return false }
            _ = script.executeAndReturnError(&err)
            if let err {
                Self.logger.error("AppleScript failed: \(String(describing: err), privacy: .public)")
                return false
            }
            return true
        }.value
    }
}
