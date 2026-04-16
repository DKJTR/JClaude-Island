//
//  BluetoothService.swift
//  DynamicIsland
//
//  ObservableObject for connected Bluetooth devices
//

import Combine
import Foundation

@MainActor
class BluetoothService: ObservableObject {
    static let shared = BluetoothService()

    @Published var connectedDevices: [BTDeviceInfo] = []

    /// Whether any devices with battery info are connected
    var hasDevicesWithBattery: Bool {
        connectedDevices.contains { $0.hasBattery }
    }

    /// Primary audio device (AirPods/Beats/headphones) if connected
    var primaryAudioDevice: BTDeviceInfo? {
        connectedDevices.first { device in
            switch device.deviceType {
            case .airpods, .airpodsPro, .airpodsMax, .beats: return true
            default: return false
            }
        }
    }

    private let bridge = BluetoothBridge.shared
    private var pollTimer: Timer?

    private init() {}

    func startMonitoring() {
        // Poll every 30 seconds (battery changes slowly)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        // Initial fetch
        refresh()
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        connectedDevices = bridge.getConnectedDevices()
    }
}
