//
//  NotchHeaderView.swift
//  ClaudeIsland
//
//  Header bar for the dynamic island
//

import Combine
import SwiftUI

struct ClaudeCrabIcon: View {
    let size: CGFloat
    let color: Color
    var animateLegs: Bool = false

    @State private var legPhase: Int = 0

    // Timer for leg animation
    private let legTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    init(size: CGFloat = 16, color: Color = Color(red: 0.85, green: 0.47, blue: 0.34), animateLegs: Bool = false) {
        self.size = size
        self.color = color
        self.animateLegs = animateLegs
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 52.0  // Original viewBox height is 52
            let xOffset = (canvasSize.width - 66 * scale) / 2

            // Left antenna
            let leftAntenna = Path { p in
                p.addRect(CGRect(x: 0, y: 13, width: 6, height: 13))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(leftAntenna, with: .color(color))

            // Right antenna
            let rightAntenna = Path { p in
                p.addRect(CGRect(x: 60, y: 13, width: 6, height: 13))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(rightAntenna, with: .color(color))

            // Animated legs - alternating up/down pattern for walking effect
            // Legs stay attached to body (y=39), only height changes
            let baseLegPositions: [CGFloat] = [6, 18, 42, 54]
            let baseLegHeight: CGFloat = 13

            // Height offsets: positive = longer leg (down), negative = shorter leg (up)
            let legHeightOffsets: [[CGFloat]] = [
                [3, -3, 3, -3],   // Phase 0: alternating
                [0, 0, 0, 0],     // Phase 1: neutral
                [-3, 3, -3, 3],   // Phase 2: alternating (opposite)
                [0, 0, 0, 0],     // Phase 3: neutral
            ]

            let currentHeightOffsets = animateLegs ? legHeightOffsets[legPhase % 4] : [CGFloat](repeating: 0, count: 4)

            for (index, xPos) in baseLegPositions.enumerated() {
                let heightOffset = currentHeightOffsets[index]
                let legHeight = baseLegHeight + heightOffset
                let leg = Path { p in
                    p.addRect(CGRect(x: xPos, y: 39, width: 6, height: legHeight))
                }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
                context.fill(leg, with: .color(color))
            }

            // Main body
            let body = Path { p in
                p.addRect(CGRect(x: 6, y: 0, width: 54, height: 39))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(body, with: .color(color))

            // Left eye
            let leftEye = Path { p in
                p.addRect(CGRect(x: 12, y: 13, width: 6, height: 6.5))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(leftEye, with: .color(.black))

            // Right eye
            let rightEye = Path { p in
                p.addRect(CGRect(x: 48, y: 13, width: 6, height: 6.5))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(rightEye, with: .color(.black))
        }
        .frame(width: size * (66.0 / 52.0), height: size)
        .onReceive(legTimer) { _ in
            if animateLegs {
                legPhase = (legPhase + 1) % 4
            }
        }
    }
}

/// Brand colors for the two kinds of pending user action
enum IslandAttentionColor {
    /// Soft lavender — permission approvals
    static let permission = Color(red: 0.60, green: 0.47, blue: 0.92)
    /// Bright amber — AskUserQuestion answers. Distinct from the orange crab next to
    /// it so the indicator pops instead of blending into the body color.
    static let question = Color(red: 1.0, green: 0.78, blue: 0.30)
}

/// How a PermissionIndicatorIcon should behave
enum PermissionIndicatorStyle: Equatable {
    /// Permission request — purple, blinking
    case permission
    /// AskUserQuestion — orange, static
    case answer
    /// Both kinds pending at once — alternates purple ↔ orange
    case alternating
}

// Pixel art question-mark indicator icon
struct PermissionIndicatorIcon: View {
    let size: CGFloat
    let style: PermissionIndicatorStyle

    @State private var blinkOn = true
    @State private var useQuestionColor = false

    init(size: CGFloat = 14, style: PermissionIndicatorStyle = .permission) {
        self.size = size
        self.style = style
    }

    // Legacy constructor — still takes a raw color, used by the existing
    // call-sites during the transition
    init(size: CGFloat = 14, color: Color) {
        self.size = size
        self.style = .permission  // style is ignored; color overrides below
        self._blinkOn = State(initialValue: true)
        self._overrideColor = State(initialValue: color)
    }
    @State private var overrideColor: Color? = nil

    private var currentColor: Color {
        if let c = overrideColor { return c }
        switch style {
        case .permission:
            return IslandAttentionColor.permission
        case .answer:
            return IslandAttentionColor.question
        case .alternating:
            return useQuestionColor ? IslandAttentionColor.question : IslandAttentionColor.permission
        }
    }

    private var currentOpacity: Double {
        switch style {
        case .permission:
            return blinkOn ? 1.0 : 0.3
        case .answer, .alternating:
            return 1.0
        }
    }

    // Visible pixel positions (at 30x30 scale) — forms a "?"
    private let pixels: [(CGFloat, CGFloat)] = [
        (7, 7), (7, 11),
        (11, 3),
        (15, 3), (15, 19), (15, 27),
        (19, 3), (19, 15),
        (23, 7), (23, 11)
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale
            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(currentColor))
            }
        }
        .frame(width: size, height: size)
        .opacity(currentOpacity)
        .onAppear { startAnimationIfNeeded() }
        .onChange(of: style) { _, _ in startAnimationIfNeeded() }
    }

    private func startAnimationIfNeeded() {
        switch style {
        case .permission:
            // Opacity blink every 0.6s
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { t in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        blinkOn.toggle()
                    }
                }
                if self.style != .permission { t.invalidate() }
            }
        case .alternating:
            // Color swap every 0.7s
            Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { t in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        useQuestionColor.toggle()
                    }
                }
                if self.style != .alternating { t.invalidate() }
            }
        case .answer:
            break
        }
    }
}

// Pixel art "ready for input" indicator icon (checkmark/done shape)
struct ReadyForInputIndicatorIcon: View {
    let size: CGFloat
    let color: Color

    init(size: CGFloat = 14, color: Color = TerminalColors.green) {
        self.size = size
        self.color = color
    }

    // Checkmark shape pixel positions (at 30x30 scale)
    private let pixels: [(CGFloat, CGFloat)] = [
        (5, 15),                    // Start of checkmark
        (9, 19),                    // Down stroke
        (13, 23),                   // Bottom of checkmark
        (17, 19),                   // Up stroke begins
        (21, 15),                   // Up stroke
        (25, 11),                   // Up stroke
        (29, 7)                     // End of checkmark
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale

            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}

