//
//  ContentTabButton.swift
//  DynamicIsland
//
//  Minimal pill-shaped tab button for content switching in expanded header
//

import SwiftUI

struct ContentTabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.35))
                .frame(width: 28, height: 20)
                .background(
                    isSelected
                        ? Color.white.opacity(0.12)
                        : Color.clear
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
