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
    let speed: Double

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animating = false

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
        // Use overlay + hidden text to measure, avoid GeometryReader
        Text(text)
            .font(font)
            .foregroundColor(.clear)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack(alignment: .leading) {
                        if needsScrolling {
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
                            .offset(x: offset, y: 0)
                        } else {
                            Text(text)
                                .font(font)
                                .foregroundColor(color)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: w, height: h)
                    .clipped()
                    .onAppear {
                        containerWidth = w
                    }
                    .onChange(of: text) { _, _ in
                        offset = 0
                        animating = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            startScrolling()
                        }
                    }
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
                            startScrolling()
                        }
                        .onChange(of: text) { _, _ in
                            textWidth = textGeo.size.width
                        }
                    })
            )
    }

    private func startScrolling() {
        guard needsScrolling, !animating else {
            if !needsScrolling { offset = 0 }
            return
        }
        animating = true

        let totalDistance = textWidth + 40
        let duration = totalDistance / speed

        offset = 0
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -totalDistance
        }
    }
}
