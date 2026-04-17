//
//  NotchView.swift
//  ClaudeIsland
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
import CoreGraphics
import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var sessionMonitor = ClaudeSessionMonitor()
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared
    @ObservedObject private var mediaService = MediaRemoteService.shared
    @ObservedObject private var bluetoothService = BluetoothService.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var previousPendingIds: Set<String> = []
    @State private var previousWaitingForInputIds: Set<String> = []
    @State private var waitingForInputTimestamps: [String: Date] = [:]  // sessionId -> when it entered waitingForInput
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false
    @State private var isBouncing: Bool = false
    @State private var modeScale: CGFloat = 1.0

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    private var isAnyProcessing: Bool {
        sessionMonitor.instances.contains { $0.phase == .processing || $0.phase == .compacting }
    }

    /// Whether any Claude session has a pending permission request
    private var hasPendingPermission: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
    }

    /// Whether any Claude session is waiting for user input (done/ready state) within the display window
    private var hasWaitingForInput: Bool {
        let now = Date()
        let displayDuration: TimeInterval = 30  // Show checkmark for 30 seconds

        return sessionMonitor.instances.contains { session in
            guard session.phase == .waitingForInput else { return false }
            // Only show if within the 30-second display window
            if let enteredAt = waitingForInputTimestamps[session.stableId] {
                return now.timeIntervalSince(enteredAt) < displayDuration
            }
            return false
        }
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        CGSize(
            width: viewModel.deviceNotchRect.width,
            height: viewModel.deviceNotchRect.height
        )
    }

    /// Whether Claude is actively working (not just the 30s cooldown)
    private var hasClaudeActivity: Bool {
        isAnyProcessing || hasPendingPermission
    }

    /// Whether Claude has any visible state (including 30s "done" checkmark)
    private var hasClaudeVisibleState: Bool {
        isAnyProcessing || hasPendingPermission || hasWaitingForInput
    }

    /// Whether media is playing
    private var hasMediaActivity: Bool {
        mediaService.isActive && (mediaService.nowPlaying?.hasContent ?? false)
    }

    /// Whether a Bluetooth device just connected (brief animation)
    private var hasBluetoothConnection: Bool {
        bluetoothService.recentlyConnected != nil
    }

    /// Closed notch expansion: show Claude if actively working, else show media
    private var expansionWidth: CGFloat {
        let permissionIndicatorWidth: CGFloat = hasPendingPermission ? 18 : 0
        let baseWidth = 2 * max(0, closedNotchSize.height - 12) + 20

        // Claude takes priority only when actively working
        if closedShowsClaude {
            return baseWidth + permissionIndicatorWidth
        }
        // Bluetooth connection animation (overrides media briefly)
        if hasBluetoothConnection {
            let leftWing = max(0, closedNotchSize.height - 12) + 10 + 80
            let rightWing = max(0, closedNotchSize.height - 12) + 10
            return leftWing + rightWing
        }
        // Music-only: left wing (album+song) + right wing (sound bars)
        if hasMediaActivity {
            let leftWing = max(0, closedNotchSize.height - 12) + 10 + 80
            let rightWing = max(0, closedNotchSize.height - 12) + 10
            return leftWing + rightWing
        }
        return 0
    }

    /// Whether closed state shows Claude (true) or media (false)
    /// Claude takes over only when actively processing/approval, not during the done-checkmark cooldown
    private var closedShowsClaude: Bool {
        isAnyProcessing || hasPendingPermission
    }

    /// Glow color for hover: green when media is active, orange/prompt when Claude is active, dim white otherwise
    private var hoverGlowColor: Color {
        if hasMediaActivity { return TerminalColors.green }
        if closedShowsClaude { return TerminalColors.prompt }
        return Color.white
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    /// Width of the closed content (notch + any expansion)
    private var closedContentWidth: CGFloat {
        closedNotchSize.width + expansionWidth
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background {
                        if viewModel.status == .opened {
                            ZStack {
                                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                                Color.black.opacity(0.82)
                            }
                        } else {
                            Color.black
                        }
                    }
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .shadow(
                        color: isHovering && viewModel.status != .opened
                            ? hoverGlowColor.opacity(0.35)
                            : .clear,
                        radius: 12
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize) // Animate container size changes between content types
                    .animation(.smooth, value: expansionWidth)
                    .animation(.smooth, value: hasPendingPermission)
                    .animation(.smooth, value: hasWaitingForInput)
                    .animation(.smooth, value: hasMediaActivity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isBouncing)
                    .scaleEffect(modeScale, anchor: .top)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            sessionMonitor.startMonitoring()
            // On non-notched devices, keep visible so users have a target to interact with
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: sessionMonitor.pendingInstances) { _, sessions in
            handlePendingSessionsChange(sessions)
        }
        .onChange(of: sessionMonitor.instances) { _, instances in
            handleProcessingChange()
            handleWaitingForInputChange(instances)
        }
        .onChange(of: mediaService.isActive) { _, _ in
            handleProcessingChange()
        }
        .onChange(of: closedShowsClaude) { _, _ in
            guard viewModel.status == .closed else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                modeScale = 1.03
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                    modeScale = 1.0
                }
            }
        }
        .animation(.smooth, value: mediaService.isActive)
        .animation(.smooth, value: hasBluetoothConnection)
        .onChange(of: bluetoothService.recentlyConnected?.id) { _, _ in
            handleProcessingChange()
        }
    }

    // MARK: - Notch Layout

    private var isProcessing: Bool {
        isAnyProcessing || hasPendingPermission
    }

    /// Whether to show the expanded closed state
    private var showClosedActivity: Bool {
        closedShowsClaude || hasBluetoothConnection || hasMediaActivity
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always present, contains crab and spinner that persist across states
            headerRow
                .frame(height: max(24, closedNotchSize.height))

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24) // Fixed width to prevent reflow
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header Row (persists across states)

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            if viewModel.status == .opened {
                // OPENED: crab + header content + spinner
                if hasClaudeVisibleState {
                    HStack(spacing: 4) {
                        ClaudeCrabIcon(size: 14, animateLegs: isProcessing)
                        if hasPendingPermission {
                            PermissionIndicatorIcon(size: 14, color: Color(red: 0.85, green: 0.47, blue: 0.34))
                        }
                    }
                    .padding(.leading, 8)
                }

                openedHeaderContent

                if hasClaudeVisibleState {
                    if isProcessing || hasPendingPermission {
                        ProcessingSpinner()
                            .frame(width: 20)
                    } else if hasWaitingForInput {
                        ReadyForInputIndicatorIcon(size: 14, color: TerminalColors.green)
                            .frame(width: 20)
                    }
                }
            } else if closedShowsClaude {
                // CLOSED — Claude mode: crab left, spinner right
                HStack(spacing: 4) {
                    ClaudeCrabIcon(size: 14, animateLegs: isProcessing)
                    if hasPendingPermission {
                        PermissionIndicatorIcon(size: 14, color: Color(red: 0.85, green: 0.47, blue: 0.34))
                    }
                }
                .frame(width: sideWidth + (hasPendingPermission ? 18 : 0))

                Rectangle()
                    .fill(.black)
                    .frame(width: closedNotchSize.width - cornerRadiusInsets.closed.top + (isBouncing ? 16 : 0))

                if isProcessing || hasPendingPermission {
                    ProcessingSpinner()
                        .frame(width: sideWidth)
                        .padding(.trailing, 4)
                } else if hasWaitingForInput {
                    ReadyForInputIndicatorIcon(size: 14, color: TerminalColors.green)
                        .frame(width: sideWidth)
                        .padding(.trailing, 4)
                }
            } else if bluetoothService.recentlyConnected != nil {
                // CLOSED — Bluetooth just connected: brief animation
                HStack(spacing: 6) {
                    Image(systemName: bluetoothService.recentlyConnected!.deviceType.sfSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.cyan)

                    Text(bluetoothService.recentlyConnected!.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.green)
                }
                .frame(width: sideWidth * 2 + closedNotchSize.width - cornerRadiusInsets.closed.top + 80)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if hasMediaActivity {
                // CLOSED — Media-only: wings only (progress bar is in expanded view)
                HStack(spacing: 0) {
                    MediaClosedLeftWing(mediaService: mediaService)
                        .frame(width: sideWidth + 80)

                    Rectangle()
                        .fill(.black)
                        .frame(width: closedNotchSize.width - cornerRadiusInsets.closed.top)

                    MediaClosedRightWing(mediaService: mediaService)
                        .frame(width: sideWidth)
                }
            } else {
                // CLOSED — nothing active
                Rectangle()
                    .fill(.clear)
                    .frame(width: closedNotchSize.width - 20)
            }
        }
        .frame(height: closedNotchSize.height)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchSize.height - 12) + 10
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 8) {
            if !hasClaudeVisibleState {
                ClaudeCrabIcon(size: 14)
                    .padding(.leading, 8)
            }

            Spacer()

            // Menu toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.toggleMenu()
                    if viewModel.contentType == .menu {
                        updateManager.markUpdateSeen()
                    }
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: viewModel.contentType == .menu ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())

                    if updateManager.hasUnseenUpdate && viewModel.contentType != .menu {
                        Circle()
                            .fill(TerminalColors.green)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View (Opened State)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .menu:
                NotchMenuView(viewModel: viewModel)
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
                .id(session.sessionId)
            default:
                // Stacked layout: Claude on top (if sessions), Media below (if playing)
                VStack(spacing: 0) {
                    // Claude section (only if sessions exist)
                    if !sessionMonitor.instances.isEmpty {
                        ClaudeInstancesView(
                            sessionMonitor: sessionMonitor,
                            viewModel: viewModel
                        )
                    }

                    // Media section (if music is playing)
                    if hasMediaActivity {
                        if !sessionMonitor.instances.isEmpty {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.vertical, 4)
                        }

                        CompactMediaRow(mediaService: mediaService)
                    }

                    // Bluetooth section (if devices connected)
                    if !bluetoothService.connectedDevices.isEmpty {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.vertical, 4)

                        BluetoothView(bluetoothService: bluetoothService)
                    }

                    // Nothing active
                    if sessionMonitor.instances.isEmpty && !hasMediaActivity && bluetoothService.connectedDevices.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(.white.opacity(0.2))
                            Text("No active sessions")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
        }
        .frame(width: notchSize.width - 24)
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        if closedShowsClaude || hasBluetoothConnection || hasMediaActivity {
            isVisible = true
        } else {
            if viewModel.status == .closed && viewModel.hasPhysicalNotch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !self.closedShowsClaude && !self.hasBluetoothConnection && !self.hasMediaActivity && self.viewModel.status == .closed {
                        self.isVisible = false
                    }
                }
            }
        }
    }

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
            // Clear waiting-for-input timestamps only when manually opened (user acknowledged)
            if viewModel.openReason == .click || viewModel.openReason == .hover {
                waitingForInputTimestamps.removeAll()
            }
        case .closed:
            guard viewModel.hasPhysicalNotch else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.status == .closed && !closedShowsClaude && !hasBluetoothConnection && !hasMediaActivity {
                    isVisible = false
                }
            }
        }
    }

    private func handlePendingSessionsChange(_ sessions: [SessionState]) {
        let currentIds = Set(sessions.map { $0.stableId })
        let newPendingIds = currentIds.subtracting(previousPendingIds)

        if !newPendingIds.isEmpty &&
           viewModel.status == .closed &&
           !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace() {
            viewModel.notchOpen(reason: .notification)
        }

        previousPendingIds = currentIds
    }

    private func handleWaitingForInputChange(_ instances: [SessionState]) {
        // Get sessions that are now waiting for input
        let waitingForInputSessions = instances.filter { $0.phase == .waitingForInput }
        let currentIds = Set(waitingForInputSessions.map { $0.stableId })
        let newWaitingIds = currentIds.subtracting(previousWaitingForInputIds)

        // Track timestamps for newly waiting sessions
        let now = Date()
        for session in waitingForInputSessions where newWaitingIds.contains(session.stableId) {
            waitingForInputTimestamps[session.stableId] = now
        }

        // Clean up timestamps for sessions no longer waiting
        let staleIds = Set(waitingForInputTimestamps.keys).subtracting(currentIds)
        for staleId in staleIds {
            waitingForInputTimestamps.removeValue(forKey: staleId)
        }

        // Bounce the notch when a session newly enters waitingForInput state
        if !newWaitingIds.isEmpty {
            // Get the sessions that just entered waitingForInput
            let newlyWaitingSessions = waitingForInputSessions.filter { newWaitingIds.contains($0.stableId) }

            // Play notification sound if the session is not actively focused
            if let soundName = AppSettings.notificationSound.soundName {
                // Check if we should play sound (async check for tmux pane focus)
                Task {
                    let shouldPlaySound = await shouldPlayNotificationSound(for: newlyWaitingSessions)
                    if shouldPlaySound {
                        await MainActor.run {
                            NSSound(named: soundName)?.play()
                        }
                    }
                }
            }

            // Trigger bounce animation to get user's attention
            DispatchQueue.main.async {
                isBouncing = true
                // Bounce back after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isBouncing = false
                }
            }

            // Schedule hiding the checkmark after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                // Trigger a UI update to re-evaluate hasWaitingForInput
                handleProcessingChange()
            }
        }

        previousWaitingForInputIds = currentIds
    }

    /// Determine if notification sound should play for the given sessions
    /// Returns true if ANY session is not actively focused
    private func shouldPlayNotificationSound(for sessions: [SessionState]) async -> Bool {
        for session in sessions {
            guard let pid = session.pid else {
                // No PID means we can't check focus, assume not focused
                return true
            }

            let isFocused = await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid)
            if !isFocused {
                return true
            }
        }

        return false
    }
}

// MARK: - NSVisualEffectView wrapper for blur behind the notch

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
