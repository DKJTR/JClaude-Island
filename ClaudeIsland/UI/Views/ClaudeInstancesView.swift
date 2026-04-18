//
//  ClaudeInstancesView.swift
//  ClaudeIsland
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    var visibleSessionIds: Set<String>? = nil // nil = show all
    var maxVisible: Int = 5

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Run claude in terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .waitingForAnswer, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    private var filteredInstances: [SessionState] {
        if let ids = visibleSessionIds {
            return sortedInstances.filter { ids.contains($0.stableId) }
        }
        return Array(sortedInstances.prefix(maxVisible))
    }

    private var instancesList: some View {
        LazyVStack(spacing: 2) {
            ForEach(filteredInstances) { session in
                    InstanceRow(
                        session: session,
                        onFocus: { focusSession(session) },
                        onChat: { openChat(session) },
                        onArchive: { archiveSession(session) },
                        onApprove: { approveSession(session) },
                        onReject: { rejectSession(session) },
                        onSendInput: { text in sendInputToSession(session, text: text) },
                        onAnswerQuestion: { answers in
                            sessionMonitor.answerQuestion(
                                sessionId: session.sessionId,
                                answers: answers
                            )
                        }
                    )
                    .id(session.stableId)
                }
            }
            .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        guard session.isInTmux else { return }

        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }

    private func sendInputToSession(_ session: SessionState, text: String) {
        Task {
            // Route through TerminalRouter so this works in tmux, Terminal.app,
            // iTerm2, Cursor, VS Code, Warp — anywhere we can detect.
            let host = await TerminalRouter.shared.detectHost(
                forSessionPid: session.pid,
                isInTmux: session.isInTmux
            )
            if host.canSend {
                if host.requiresFocus, !KeystrokeInjector.isAccessibilityTrusted() {
                    _ = await MainActor.run { KeystrokeInjector.requestAccessibility(prompt: true) }
                    return
                }
                _ = await TerminalRouter.shared.sendMessage(text, to: host)
            }
        }
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void
    var onSendInput: (String) -> Void = { _ in }
    var onAnswerQuestion: (_ answers: [String: String]) -> Void = { _ in }

    @State private var isHovered = false
    @State private var spinnerPhase = 0
    @State private var isYabaiAvailable = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether we're showing the AskUserQuestion inline picker
    private var isWaitingForAnswer: Bool {
        session.phase.isWaitingForAnswer
    }

    /// The pending QuestionContext, if any
    private var inlineQuestionContext: QuestionContext? {
        session.phase.questionContext
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    /// Extract the question text from AskUserQuestion toolInput
    private var questionText: String? {
        guard isInteractiveTool,
              let input = session.activePermission?.toolInput,
              let question = input["question"]?.value as? String else { return nil }
        return question
    }

    /// Extract options from AskUserQuestion toolInput
    private var questionOptions: [String] {
        guard isInteractiveTool,
              let input = session.activePermission?.toolInput else { return [] }

        // Check for "options" array
        if let options = input["options"]?.value as? [Any] {
            return options.compactMap { item -> String? in
                if let str = item as? String { return str }
                if let dict = item as? [String: Any], let label = dict["label"] as? String { return label }
                return nil
            }
        }
        return []
    }

    /// Status text based on session phase (fallback when no other content)
    private var phaseStatusText: String {
        switch session.phase {
        case .processing:
            return "Processing..."
        case .compacting:
            return "Compacting..."
        case .waitingForInput:
            return "Ready"
        case .waitingForApproval:
            return "Waiting for approval"
        case .waitingForAnswer(let ctx):
            return ctx.questions.count > 1 ? "Question (\(ctx.questions.count))" : "Question"
        case .idle:
            return "Idle"
        case .ended:
            return "Ended"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // State indicator on left
            stateIndicator
                .frame(width: 14)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Show tool call when waiting for approval, otherwise last activity
                if isWaitingForApproval, let toolName = session.pendingToolName {
                    // Show tool name in amber + input on same line
                    HStack(spacing: 4) {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(TerminalColors.amber.opacity(0.9))
                        if isInteractiveTool {
                            // Show the actual question text from toolInput
                            if let question = questionText {
                                Text(question)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(2)
                            } else {
                                Text("Needs your input")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        } else if let input = session.pendingToolInput {
                            Text(input)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }

                    // Show pickable options for AskUserQuestion
                    if isInteractiveTool && !questionOptions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(questionOptions.enumerated()), id: \.offset) { idx, option in
                                    Button {
                                        // Send the option number (1-indexed) to the terminal via tmux
                                        onSendInput("\(idx + 1)")
                                    } label: {
                                        Text(option)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white.opacity(0.85))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(TerminalColors.cyan.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                } else if isWaitingForAnswer, let ctx = inlineQuestionContext {
                    // AskUserQuestion intercept mode — picker is the only UI; pick
                    // here and the answer is returned to Claude via the socket
                    // (python hook outputs deny-with-answer-in-reason).
                    InlineQuestionPicker(
                        context: ctx,
                        onPick: { qIdx, optionIdx in
                            let q = ctx.questions[qIdx]
                            let pickedLabel = q.options[optionIdx].label
                            onAnswerQuestion([q.header: pickedLabel])
                        }
                    )
                } else if let role = session.lastMessageRole {
                    switch role {
                    case "tool":
                        // Tool call - show tool name + input
                        HStack(spacing: 4) {
                            if let toolName = session.lastToolName {
                                Text(MCPToolFormatter.formatToolName(toolName))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            if let input = session.lastMessage {
                                Text(input)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    case "user":
                        // User message - prefix with "You:"
                        HStack(spacing: 4) {
                            Text("You:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    default:
                        // Assistant message - just show text
                        if let msg = session.lastMessage {
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                } else if let lastMsg = session.lastMessage {
                    Text(lastMsg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                } else {
                    // Fallback: show phase-based status when no other content
                    Text(phaseStatusText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Action icons or approval buttons
            if isWaitingForApproval && isInteractiveTool {
                // AskUserQuestion — show "answer in terminal" + chat
                HStack(spacing: 8) {
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }
                    if isYabaiAvailable {
                        TerminalButton(
                            isEnabled: session.isInTmux,
                            onTap: { onFocus() }
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isWaitingForApproval {
                InlineApprovalButtons(
                    onChat: onChat,
                    onApprove: onApprove,
                    onReject: onReject
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                HStack(spacing: 8) {
                    // Token usage bar — prefer the per-session token cache
                    // (authoritative; written by the user's statusline if
                    // they opted in) and fall back to the JSONL-derived
                    // approximation otherwise.
                    if let snap = TokenCacheReader.snapshot(for: session.sessionId),
                       snap.isFresh() {
                        TokenUsageBar(
                            inputTokens: snap.tokensUsed,
                            outputTokens: 0,
                            cacheReadTokens: 0,
                            cacheCreationTokens: 0,
                            contextLimit: snap.contextSize
                        )
                    } else if session.usage.totalTokens > 0 {
                        TokenUsageBar(
                            inputTokens: session.usage.inputTokens,
                            outputTokens: session.usage.outputTokens,
                            cacheReadTokens: session.usage.cacheReadTokens,
                            cacheCreationTokens: session.usage.cacheCreationTokens,
                            contextLimit: TokenUsageBar.inferLimit(totalTokens: session.usage.totalTokens)
                        )
                    }

                    // Chat icon
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }

                    // Focus icon (only for tmux instances with yabai)
                    if session.isInTmux && isYabaiAvailable {
                        IconButton(icon: "eye") {
                            onFocus()
                        }
                    }

                    // Archive button - only for idle or completed sessions
                    if session.phase == .idle || session.phase == .waitingForInput {
                        IconButton(icon: "archivebox") {
                            onArchive()
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onChat()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(claudeOrange)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForApproval:
            // Pixel "?" — purple, blinking
            PermissionIndicatorIcon(size: 12, style: .permission)
        case .waitingForAnswer:
            // Pixel "?" — orange, static
            PermissionIndicatorIcon(size: 12, style: .answer)
        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text("Deny")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text("Allow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .medium))
                Text("Go to Terminal")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Question Picker (AskUserQuestion mirror in row)

/// Compact picker rendered inline in a Claude row when the session is in
/// .waitingForAnswer. Shows the first un-picked question's options as chips.
/// Tapping a chip routes the keystroke into the terminal picker so the
/// terminal session submits without the user leaving the island.
struct InlineQuestionPicker: View {
    let context: QuestionContext
    let onPick: (_ questionIdx: Int, _ optionIdx: Int) -> Void

    /// Track which question we're currently on (advances after each pick).
    @State private var currentQuestion: Int = 0
    @State private var pickedIdx: Int? = nil

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    private var question: PendingQuestion? {
        guard currentQuestion < context.questions.count else { return nil }
        return context.questions[currentQuestion]
    }

    var body: some View {
        if let q = question {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(q.header.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundColor(claudeOrange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(claudeOrange.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if context.questions.count > 1 {
                        Text("\(currentQuestion + 1)/\(context.questions.count)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Text(q.question)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(0..<q.options.count, id: \.self) { idx in
                            let opt = q.options[idx]
                            Button {
                                pickedIdx = idx
                                onPick(currentQuestion, idx)
                                // Advance to the next question after a beat so the user
                                // sees their pick before the chip set swaps.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    pickedIdx = nil
                                    if currentQuestion + 1 < context.questions.count {
                                        currentQuestion += 1
                                    }
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    if pickedIdx == idx {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    Text(opt.label)
                                        .font(.system(size: 10, weight: pickedIdx == idx ? .semibold : .medium))
                                        .lineLimit(1)
                                }
                                .foregroundColor(pickedIdx == idx ? claudeOrange : .white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    pickedIdx == idx
                                    ? claudeOrange.opacity(0.16)
                                    : Color.white.opacity(0.10)
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        pickedIdx == idx ? claudeOrange.opacity(0.55) : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(opt.description ?? opt.label)
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }
}
