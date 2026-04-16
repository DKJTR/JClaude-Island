//
//  BluetoothView.swift
//  DynamicIsland
//
//  Expanded Bluetooth device list with battery information
//

import SwiftUI

struct BluetoothView: View {
    @ObservedObject var bluetoothService: BluetoothService

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Connected Devices")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Button {
                    bluetoothService.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)

            if bluetoothService.connectedDevices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No devices connected")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(bluetoothService.connectedDevices) { device in
                            DeviceRow(device: device)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: BTDeviceInfo

    var body: some View {
        HStack(spacing: 12) {
            // Device icon
            Image(systemName: device.deviceType.sfSymbol)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 28, height: 28)

            // Name + type
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if device.batteryLevelLeft != nil || device.batteryLevelRight != nil {
                    // AirPods L/R/Case breakdown
                    airPodsBatteryRow
                }
            }

            Spacer()

            // Battery indicator
            if let battery = device.displayBattery {
                BatteryIndicator(level: battery)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var airPodsBatteryRow: some View {
        HStack(spacing: 8) {
            if let left = device.batteryLevelLeft {
                HStack(spacing: 3) {
                    Text("L")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(left)%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(batteryColor(left))
                }
            }
            if let right = device.batteryLevelRight {
                HStack(spacing: 3) {
                    Text("R")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(right)%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(batteryColor(right))
                }
            }
            if let caseLevel = device.batteryLevelCase {
                HStack(spacing: 3) {
                    Image(systemName: "case")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(caseLevel)%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(batteryColor(caseLevel))
                }
            }
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        if level <= 15 { return Color(red: 1.0, green: 0.3, blue: 0.3) }
        if level <= 30 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
        return TerminalColors.green
    }
}

// MARK: - Battery Indicator

private struct BatteryIndicator: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            // Battery bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 24, height: 10)

                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(width: max(2, 24 * CGFloat(level) / 100), height: 10)
            }

            Text("\(level)%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var fillColor: Color {
        if level <= 15 { return Color(red: 1.0, green: 0.3, blue: 0.3) }
        if level <= 30 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
        return TerminalColors.green
    }
}
