//
//  TokenUsageBar.swift
//  DynamicIsland
//
//  Stacked gradient bar showing token usage relative to context limit
//

import SwiftUI

struct TokenUsageBar: View {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    var contextLimit: Int = 200_000

    /// Infer context limit from model ID
    /// Opus 4.6 / Sonnet 4.6 default to 200K, [1m] variant = 1M
    /// Since JSONL doesn't expose the [1m] suffix, use a heuristic:
    /// If total tokens > 180K, the session must be on 1M context
    static func inferLimit(totalTokens: Int) -> Int {
        if totalTokens > 180_000 { return 1_000_000 }
        return 200_000
    }

    private var totalTokens: Int {
        inputTokens + outputTokens
    }

    private var fraction: CGFloat {
        guard contextLimit > 0 else { return 0 }
        return min(1.0, CGFloat(totalTokens) / CGFloat(contextLimit))
    }

    private var inputFraction: CGFloat {
        guard contextLimit > 0 else { return 0 }
        return min(1.0, CGFloat(inputTokens) / CGFloat(contextLimit))
    }

    private var outputFraction: CGFloat {
        guard contextLimit > 0 else { return 0 }
        return min(1.0, CGFloat(outputTokens) / CGFloat(contextLimit))
    }

    private var barColor: Color {
        if fraction > 0.9 { return Color(red: 1.0, green: 0.3, blue: 0.3) }
        if fraction > 0.7 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
        return TerminalColors.cyan
    }

    var body: some View {
        VStack(spacing: 2) {
            // Stacked gradient bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))

                    // Input tokens (lighter)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.5), barColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * (inputFraction + outputFraction)))

                    // Output tokens (brighter, stacked on top)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * outputFraction))
                        .offset(x: geo.size.width * inputFraction)
                }
            }
            .frame(width: 32, height: 4)

            // Label
            Text(formattedTokens)
                .font(.system(size: 7, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var formattedTokens: String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        } else if totalTokens >= 1_000 {
            return String(format: "%.0fK", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens)"
    }
}
