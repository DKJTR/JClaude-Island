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
    @Published var recentlyConnected: BTDeviceInfo?

    /// Whether any devices with battery info are connected
    var hasDevicesWithBattery: Bool {
        connectedDevices.contains { $0.hasBattery }
    }

    /// Primary audio device (AirPods/Beats/headphones) if connected
    var primaryAudioDevice: BTDeviceInfo? {
        connectedDevices.first { device in
            switch device.deviceType {
            case .airpods, .airpodsPro, .airpodsMax, .beats, .headphones: return true
            default: return false
            }
        }
    }

    private let bridge = BluetoothBridge.shared
    private var pollTimer: Timer?
    private var fastPollTimer: Timer?
    private var previousDeviceIds: Set<String> = []
    private var recentlyConnectedTimer: Timer?

    private init() {}

    func startMonitoring() {
        // Fast poll every 5 seconds for connection detection
        fastPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        // Slow poll every 30 seconds for battery updates (less aggressive)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        // Initial fetch
        refresh()
        // Seed previous IDs so initial devices don't trigger the animation
        previousDeviceIds = Set(connectedDevices.map { $0.id })
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        fastPollTimer?.invalidate()
        fastPollTimer = nil
        recentlyConnectedTimer?.invalidate()
        recentlyConnectedTimer = nil
    }

    func refresh() {
        let newDevices = bridge.getConnectedDevices()
        let newIds = Set(newDevices.map { $0.id })

        // Detect newly connected devices (present now but not before)
        let addedIds = newIds.subtracting(previousDeviceIds)
        if let firstNew = newDevices.first(where: { addedIds.contains($0.id) }) {
            recentlyConnected = firstNew
            // Auto-clear after 4 seconds
            recentlyConnectedTimer?.invalidate()
            recentlyConnectedTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.recentlyConnected = nil
                }
            }
        }

        previousDeviceIds = newIds
        connectedDevices = newDevices
    }
}
