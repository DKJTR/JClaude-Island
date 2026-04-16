//
//  BluetoothBridge.swift
//  DynamicIsland
//
//  IOBluetooth + IOKit bridge for device enumeration and battery levels
//

import Foundation
import IOBluetooth
import IOKit

/// Bluetooth device type classification
enum BTDeviceType: String, Sendable {
    case airpods = "AirPods"
    case airpodsPro = "AirPods Pro"
    case airpodsMax = "AirPods Max"
    case beats = "Beats"
    case keyboard = "Keyboard"
    case mouse = "Mouse"
    case trackpad = "Trackpad"
    case gamepad = "Gamepad"
    case other = "Other"

    var sfSymbol: String {
        switch self {
        case .airpods, .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "trackpad"
        case .gamepad: return "gamecontroller"
        case .other: return "wave.3.right"
        }
    }
}

/// Information about a connected Bluetooth device
struct BTDeviceInfo: Identifiable, Equatable {
    let id: String // hardware address
    let name: String
    let deviceType: BTDeviceType
    let isConnected: Bool
    var batteryLevel: Int? // 0-100 overall
    var batteryLevelLeft: Int? // AirPods left
    var batteryLevelRight: Int? // AirPods right
    var batteryLevelCase: Int? // AirPods case

    var hasBattery: Bool {
        batteryLevel != nil || batteryLevelLeft != nil
    }

    /// Primary display battery (single number)
    var displayBattery: Int? {
        if let overall = batteryLevel { return overall }
        if let l = batteryLevelLeft, let r = batteryLevelRight {
            return min(l, r)
        }
        return batteryLevelLeft ?? batteryLevelRight
    }
}

/// Bridge to IOBluetooth and IOKit for device enumeration
final class BluetoothBridge {
    static let shared = BluetoothBridge()

    private init() {}

    /// Get all connected Bluetooth devices with battery info
    func getConnectedDevices() -> [BTDeviceInfo] {
        var devices: [BTDeviceInfo] = []

        // Get battery info from IOKit (covers AirPods L/R/Case)
        let batteryMap = fetchIOKitBatteryInfo()

        // Enumerate paired devices via IOBluetooth
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return devices
        }

        for device in pairedDevices {
            guard device.isConnected() else { continue }

            let name = device.name ?? "Unknown"
            let address = device.addressString ?? UUID().uuidString
            let deviceType = classifyDevice(name: name, device: device)

            var info = BTDeviceInfo(
                id: address,
                name: name,
                deviceType: deviceType,
                isConnected: true
            )

            // Match with IOKit battery data by product name
            if let battery = batteryMap[name] {
                info.batteryLevel = battery.overall
                info.batteryLevelLeft = battery.left
                info.batteryLevelRight = battery.right
                info.batteryLevelCase = battery.caseLevel
            }

            devices.append(info)
        }

        return devices
    }

    // MARK: - IOKit Battery

    private struct BatteryInfo {
        var overall: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
    }

    private func fetchIOKitBatteryInfo() -> [String: BatteryInfo] {
        var result: [String: BatteryInfo] = [:]

        // Match HID services that report battery
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else {
            return result
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let productName = getStringProperty(service, key: "Product") else { continue }

            var info = result[productName] ?? BatteryInfo()

            if let percent = getIntProperty(service, key: "BatteryPercent") {
                info.overall = percent
            }
            if let left = getIntProperty(service, key: "BatteryPercentLeft") {
                info.left = left
            }
            if let right = getIntProperty(service, key: "BatteryPercentRight") {
                info.right = right
            }
            if let caseVal = getIntProperty(service, key: "BatteryPercentCase") {
                info.caseLevel = caseVal
            }

            result[productName] = info
        }

        return result
    }

    private func getStringProperty(_ service: io_object_t, key: String) -> String? {
        guard let cfValue = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return cfValue as? String
    }

    private func getIntProperty(_ service: io_object_t, key: String) -> Int? {
        guard let cfValue = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return cfValue as? Int
    }

    // MARK: - Device Classification

    private func classifyDevice(name: String, device: IOBluetoothDevice) -> BTDeviceType {
        let lower = name.lowercased()

        if lower.contains("airpods pro") { return .airpodsPro }
        if lower.contains("airpods max") { return .airpodsMax }
        if lower.contains("airpods") { return .airpods }
        if lower.contains("beats") { return .beats }
        if lower.contains("keyboard") || lower.contains("magic keyboard") { return .keyboard }
        if lower.contains("mouse") || lower.contains("magic mouse") { return .mouse }
        if lower.contains("trackpad") || lower.contains("magic trackpad") { return .trackpad }
        if lower.contains("controller") || lower.contains("dualsense") || lower.contains("xbox") { return .gamepad }

        // Fallback: check device class
        let majorClass = device.deviceClassMajor
        if majorClass == kBluetoothDeviceClassMajorPeripheral {
            let minorClass = device.deviceClassMinor
            if minorClass == kBluetoothDeviceClassMinorPeripheral1Keyboard { return .keyboard }
            if minorClass == kBluetoothDeviceClassMinorPeripheral1Pointing { return .mouse }
        }
        if majorClass == kBluetoothDeviceClassMajorAudio { return .other }

        return .other
    }
}
