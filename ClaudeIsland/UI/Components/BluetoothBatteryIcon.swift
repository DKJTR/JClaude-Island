//
//  BluetoothBatteryIcon.swift
//  DynamicIsland
//
//  Tiny battery icon for closed notch right wing
//

import SwiftUI

struct BluetoothBatteryIcon: View {
    let level: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: batterySymbol)
                .font(.system(size: 10))
                .foregroundColor(batteryColor)
        }
    }

    private var batterySymbol: String {
        if level <= 10 { return "battery.0percent" }
        if level <= 25 { return "battery.25percent" }
        if level <= 50 { return "battery.50percent" }
        if level <= 75 { return "battery.75percent" }
        return "battery.100percent"
    }

    private var batteryColor: Color {
        if level <= 15 { return Color(red: 1.0, green: 0.3, blue: 0.3) }
        if level <= 30 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
        return TerminalColors.green
    }
}
