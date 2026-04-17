//
//  TokenUsageBar.swift
//  DynamicIsland
//
//  Vertical gradient bar showing token context usage
//

import SwiftUI

struct TokenUsageBar: View {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    var contextLimit: Int = 200_000

    static func inferLimit(totalTokens: Int) -> Int {
        if totalTokens > 180_000 { return 1_000_000 }
        return 200_000
    }

    /// Context usage: input tokens include cache reads (what fills the context window)
    private var contextTokens: Int {
        inputTokens + outputTokens
    }

    private var fraction: CGFloat {
        guard contextLimit > 0 else { return 0 }
        return min(1.0, CGFloat(contextTokens) / CGFloat(contextLimit))
    }

    private var barColor: Color {
        if fraction > 0.9 { return Color(red: 1.0, green: 0.3, blue: 0.3) }
        if fraction > 0.7 { return Color(red: 1.0, green: 0.6, blue: 0.0) }
        if fraction > 0.5 { return Color(red: 1.0, green: 0.8, blue: 0.0) }
        return TerminalColors.green
    }

    private var barColorLight: Color {
        if fraction > 0.9 { return Color(red: 1.0, green: 0.5, blue: 0.5) }
        if fraction > 0.7 { return Color(red: 1.0, green: 0.75, blue: 0.3) }
        if fraction > 0.5 { return Color(red: 1.0, green: 0.9, blue: 0.4) }
        return Color(red: 0.5, green: 0.85, blue: 0.55)
    }

    var body: some View {
        HStack(spacing: 3) {
            // Vertical bar (fills bottom-to-top)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [barColor, barColorLight],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(0, geo.size.height * fraction))
                }
            }
            .frame(width: 4, height: 24)

            // Label: percentage + context size e.g. "50%(1M)"
            Text(formattedLabel)
                .font(.system(size: 7, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.35))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var percentInt: Int {
        Int(fraction * 100)
    }

    private var formattedLabel: String {
        let pct = "\(percentInt)%"
        let ctx: String
        if contextLimit >= 1_000_000 {
            ctx = "\(contextLimit / 1_000_000)M"
        } else {
            ctx = "\(contextLimit / 1_000)K"
        }
        return "\(pct)(\(ctx))"
    }
}
