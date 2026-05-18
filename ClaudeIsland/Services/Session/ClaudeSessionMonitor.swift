//
//  ClaudeSessionMonitor.swift
//  ClaudeIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        // Start periodic status rechecking
        Task {
            await SessionStore.shared.startPeriodicStatusCheck()
        }

        HookSocketServer.shared.start(
            onEvent: { event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
        Task {
            await SessionStore.shared.stopPeriodicStatusCheck()
        }
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            if permission.isMirrorMode {
                // Both mode: terminal picker is still on screen. Inject "1\n".
                await sendPermissionKeystroke(for: session, keys: "1")
            } else {
                HookSocketServer.shared.respondToPermission(
                    toolUseId: permission.toolUseId,
                    decision: "allow"
                )
            }

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            if permission.isMirrorMode {
                // Both mode: send "n" + Enter to the terminal picker. Reason
                // text isn't piped through — the user types follow-up
                // explanation in the terminal if they want.
                await sendPermissionKeystroke(for: session, keys: "n")
            } else {
                HookSocketServer.shared.respondToPermission(
                    toolUseId: permission.toolUseId,
                    decision: "deny",
                    reason: reason
                )
            }

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    /// Inject a permission-decision keystroke ("1", "2", or "n" + Enter) into
    /// the terminal showing Claude Code's picker. Used in `both` mode where
    /// the terminal picker is the canonical answer channel.
    private func sendPermissionKeystroke(for session: SessionState, keys: String) async {
        let host = await TerminalRouter.shared.detectHost(forSessionPid: session.pid, isInTmux: session.isInTmux)
        guard host.canSend else { return }
        _ = await TerminalRouter.shared.sendMessage(keys, to: host)
    }

    // MARK: - Question Handling (AskUserQuestion)

    /// Submit user-selected answers to a pending AskUserQuestion call
    /// `answers` is keyed by question header → selected option label
    func answerQuestion(sessionId: String, answers: [String: String]) {
        Self.flow("answerQuestion entry session=\(sessionId.prefix(8)) answers=\(answers)")
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                Self.flow("NO SESSION for \(sessionId.prefix(8))")
                return
            }
            guard let ctx = session.phase.questionContext else {
                Self.flow("phase not waitingForAnswer phase=\(session.phase)")
                return
            }
            Self.flow("ctx.routingMode=\(ctx.routingMode ?? "nil") isMirrorMode=\(ctx.isMirrorMode) toolUseId=\(ctx.toolUseId.prefix(12)) pid=\(session.pid.map(String.init) ?? "nil") isInTmux=\(session.isInTmux)")

            if ctx.isMirrorMode {
                // Both mode: send the picks as arrow-key navigation into the
                // terminal picker rather than replying on the (already-closed)
                // socket. SessionStore is told the question was answered so
                // the phase transitions out of waitingForAnswer.
                let host = await TerminalRouter.shared.detectHost(
                    forSessionPid: session.pid,
                    isInTmux: session.isInTmux
                )
                Self.flow("detected host=\(host) canSend=\(host.canSend)")
                if host.canSend {
                    // CGEvent-based keystroke injection needs Accessibility.
                    // Prompt lazily on the first attempt so macOS surfaces the
                    // grant dialog (silent failures are confusing).
                    if host.requiresFocus, !KeystrokeInjector.isAccessibilityTrusted() {
                        Self.flow("AX not granted — requesting prompt and bailing this round")
                        _ = await MainActor.run { KeystrokeInjector.requestAccessibility(prompt: true) }
                        // Don't dispatch .questionAnswered yet — the terminal
                        // picker is still waiting and the user will need to
                        // click again after granting.
                        return
                    }
                    Self.flow("AX trusted — about to sendQuestionAnswers")
                    let ok = await TerminalRouter.shared.sendQuestionAnswers(
                        answers,
                        context: ctx,
                        to: host
                    )
                    Self.flow("sendQuestionAnswers returned \(ok)")
                }
            }

            await SessionStore.shared.process(
                .questionAnswered(sessionId: sessionId, toolUseId: ctx.toolUseId, answers: answers)
            )
        }
    }

    /// File-based trace for the answer flow (NSLog content is redacted by macOS).
    private static func flow(_ s: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/claude-island-flow-debug.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); try? h.write(contentsOf: data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
