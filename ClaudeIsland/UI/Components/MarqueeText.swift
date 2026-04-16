//
//  MarqueeText.swift
//  DynamicIsland
//
//  Scrolling text for long track names in the closed notch
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let speed: Double // points per second

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var needsScrolling: Bool {
        textWidth > containerWidth + 1
    }

    init(_ text: String, font: Font = .system(size: 11, weight: .medium), color: Color = .white, speed: Double = 30) {
        self.text = text
        self.font = font
        self.color = color
        self.speed = speed
    }

    var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width

            ZStack(alignment: .leading) {
                if needsScrolling {
                    // Two copies for seamless loop
                    HStack(spacing: 40) {
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize()
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize()
                    }
                    .offset(x: offset)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(1)
                }
            }
            .frame(width: containerW, alignment: .leading)
            .clipped()
            .onAppear {
                containerWidth = containerW
                startScrolling()
            }
            .onChange(of: text) { _, _ in
                offset = 0
                measureText()
                startScrolling()
            }
        }
        .background(
            Text(text)
                .font(font)
                .fixedSize()
                .hidden()
                .background(GeometryReader { textGeo in
                    Color.clear.onAppear {
                        textWidth = textGeo.size.width
                    }
                    .onChange(of: text) { _, _ in
                        textWidth = textGeo.size.width
                    }
                })
        )
    }

    private func measureText() {
        // Width is measured via hidden background text
    }

    private func startScrolling() {
        guard needsScrolling else {
            offset = 0
            return
        }

        let totalDistance = textWidth + 40 // text width + gap
        let duration = totalDistance / speed

        // Reset and start
        offset = 0
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -totalDistance
        }
    }
}
