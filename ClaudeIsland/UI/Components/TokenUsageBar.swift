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
        if fraction > 0.7 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
        return TerminalColors.cyan
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
                                colors: [barColor.opacity(0.6), barColor],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(0, geo.size.height * fraction))
                }
            }
            .frame(width: 4, height: 24)

            // Label
            Text(formattedTokens)
                .font(.system(size: 8, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var formattedTokens: String {
        if contextTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(contextTokens) / 1_000_000)
        } else if contextTokens >= 1_000 {
            return String(format: "%.0fK", Double(contextTokens) / 1_000)
        }
        return "\(contextTokens)"
    }
}
