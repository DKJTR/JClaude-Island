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

    /// Submit AskUserQuestion answers into the terminal picker. For each question
    /// in `context.questions`, we send Down×N then Enter so inquirer-style
    /// pickers (what Claude Code uses) navigate to the right option and submit.
    /// Returns true if every question's keystrokes went out without error.
    func sendQuestionAnswers(
        _ answers: [String: String],
        context: QuestionContext,
        to host: TerminalHost
    ) async -> Bool {
        guard host.canSend else { return false }

        if host.requiresFocus {
            await activateHostFocus(host)
            try? await Task.sleep(for: .milliseconds(220))
        }

        var allOk = true
        for (idx, q) in context.questions.enumerated() {
            guard let picked = answers[q.header], !picked.isEmpty else {
                allOk = false
                continue
            }
            // Multi-select fallback: only the first picked label is honored at the
            // terminal-picker level (it requires Space-toggle navigation we don't
            // emulate yet). User can finish complex multi-select in the terminal.
            let firstLabel = picked.components(separatedBy: ", ").first ?? picked
            guard let optionIndex = q.options.firstIndex(where: { $0.label == firstLabel }) else {
                allOk = false
                continue
            }
            let ok = await sendArrowSelection(optionIndex: optionIndex, to: host)
            if !ok { allOk = false }

            if idx < context.questions.count - 1 {
                try? await Task.sleep(for: .milliseconds(280))
            }
        }
        return allOk
    }

    /// Send a single option pick — Down × optionIndex, then Enter. Used by the
    /// inline row picker when the user wants to answer without opening the chat view.
    func sendOptionPick(optionIndex: Int, for session: SessionState) async -> Bool {
        let host = await detectHost(forSessionPid: session.pid, isInTmux: session.isInTmux)
        guard host.canSend else { return false }
        if host.requiresFocus {
            await activateHostFocus(host)
            try? await Task.sleep(for: .milliseconds(180))
        }
        return await sendArrowSelection(optionIndex: optionIndex, to: host)
    }

    /// Press Down `optionIndex` times then Enter, routed by host.
    private func sendArrowSelection(optionIndex: Int, to host: TerminalHost) async -> Bool {
        switch host {
        case .tmux(let target):
            return await sendArrowsViaTmux(target: target, downCount: optionIndex)
        case .iTerm2:
            return await sendArrowsViaAppleScript(processName: "iTerm2", downCount: optionIndex)
        case .terminalApp:
            return await sendArrowsViaAppleScript(processName: "Terminal", downCount: optionIndex)
        case .bundleApp:
            return await MainActor.run {
                if optionIndex > 0 {
                    _ = KeystrokeInjector.pressKey(0x7D, repeats: optionIndex, gapMs: 30_000) // Down arrow
                }
                return KeystrokeInjector.pressKey(0x24) // Return
            }
        case .unknown:
            return false
        }
    }

    private func sendArrowsViaTmux(target: TmuxTarget, downCount: Int) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else { return false }
        do {
            for _ in 0..<downCount {
                _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                    "send-keys", "-t", target.targetString, "Down"
                ])
                try? await Task.sleep(for: .milliseconds(20))
            }
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "send-keys", "-t", target.targetString, "Enter"
            ])
            return true
        } catch {
            return false
        }
    }

    private func sendArrowsViaAppleScript(processName: String, downCount: Int) async -> Bool {
        var lines: [String] = []
        for _ in 0..<downCount {
            lines.append("key code 125")  // Down arrow
        }
        lines.append("key code 36")  // Return
        let body = lines.joined(separator: "\n        ")
        let script = """
        tell application "System Events"
          tell process "\(processName)"
            \(body)
          end tell
        end tell
        """
        return await runAppleScript(script)
    }

    private func activateHostFocus(_ host: TerminalHost) async {
        if case .terminalApp(let pid) = host {
            await MainActor.run { KeystrokeInjector.activateApp(pid: pid) }
        } else if case .bundleApp(_, _, let pid) = host {
            await MainActor.run { KeystrokeInjector.activateApp(pid: pid) }
        }
    }

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

    /// Escape arbitrary user text for an AppleScript double-quoted string literal.
    /// Handles backslash, quote, CR, LF — the four chars that can break out of the
    /// `keystroke "..."` / `write text "..."` literal.
    private func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// iTerm2 has a native AppleScript API — write text directly into the focused session.
    /// Doesn't require focus; iTerm routes the text to the foreground session.
    private func sendViaITerm2(text: String) async -> Bool {
        let escaped = appleScriptEscape(text)
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

        let escaped = appleScriptEscape(text)
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
