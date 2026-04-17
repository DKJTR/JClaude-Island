//
//  QuestionPickerView.swift
//  ClaudeIsland
//
//  Renders Claude's AskUserQuestion in the notch and lets the user pick answers
//  without leaving the island.
//

import SwiftUI

/// Picker bar shown in ChatView when phase = .waitingForAnswer
struct ChatQuestionBar: View {
    let context: QuestionContext
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void

    /// Single-select: header → label
    /// Multi-select: header → set of labels (joined by ", " on submit)
    @State private var selections: [String: Set<String>] = [:]
    @State private var showContent = false
    @State private var showSubmit = false

    private var allAnswered: Bool {
        context.questions.allSatisfy { q in
            !(selections[q.header]?.isEmpty ?? true)
        }
    }

    private func encodedAnswers() -> [String: String] {
        var out: [String: String] = [:]
        for q in context.questions {
            let picked = selections[q.header] ?? []
            // Preserve option order for stable output
            let ordered = q.options.map { $0.label }.filter { picked.contains($0) }
            out[q.header] = ordered.joined(separator: ", ")
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<context.questions.count, id: \.self) { idx in
                let question = context.questions[idx]
                QuestionBlock(
                    question: question,
                    selected: selections[question.header] ?? [],
                    onTap: { label in
                        toggle(header: question.header, label: label, multi: question.multiSelect)
                    }
                )
            }

            HStack(spacing: 10) {
                Button { onCancel() } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button { onSubmit(encodedAnswers()) } label: {
                    HStack(spacing: 5) {
                        Text("Submit")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(allAnswered ? .black : .white.opacity(0.35))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(allAnswered ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!allAnswered)
                .opacity(showSubmit ? 1 : 0)
                .scaleEffect(showSubmit ? 1 : 0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.25))
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 6)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78).delay(0.04)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78).delay(0.12)) {
                showSubmit = true
            }
        }
    }

    private func toggle(header: String, label: String, multi: Bool) {
        var current = selections[header] ?? []
        if multi {
            if current.contains(label) {
                current.remove(label)
            } else {
                current.insert(label)
            }
        } else {
            current = current.contains(label) ? [] : [label]
        }
        selections[header] = current
    }
}

/// One question + its option chips
private struct QuestionBlock: View {
    let question: PendingQuestion
    let selected: Set<String>
    let onTap: (String) -> Void

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(question.header.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(claudeOrange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(claudeOrange.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if question.multiSelect {
                    Text("multi-select")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
            }

            Text(question.question)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 6) {
                ForEach(0..<question.options.count, id: \.self) { idx in
                    let opt = question.options[idx]
                    OptionChip(
                        label: opt.label,
                        description: opt.description,
                        isSelected: selected.contains(opt.label),
                        onTap: { onTap(opt.label) }
                    )
                }
            }
            .padding(.top, 2)
        }
    }
}

/// Single option chip with hover + selected states
private struct OptionChip: View {
    let label: String
    let description: String?
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHover = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(
                isSelected
                ? claudeOrange
                : .white.opacity(isHover ? 1.0 : 0.82)
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .background(
                isSelected
                ? claudeOrange.opacity(0.13)
                : Color.white.opacity(isHover ? 0.16 : 0.08)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected
                        ? claudeOrange.opacity(0.55)
                        : Color.white.opacity(isHover ? 0.10 : 0),
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(description ?? label)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHover = hovering }
        }
    }
}

/// Minimal flow layout — wraps option chips onto multiple rows (SwiftUI Layout protocol)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if lineWidth + size.width + (lineWidth == 0 ? 0 : spacing) > maxWidth {
                totalHeight += lineHeight + spacing
                widestLine = max(widestLine, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += size.width + (lineWidth == 0 ? 0 : spacing)
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        widestLine = max(widestLine, lineWidth)
        return CGSize(width: min(widestLine, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
