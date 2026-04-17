//
//  KeystrokeInjector.swift
//  ClaudeIsland
//
//  Injects Unicode text and Return into the focused window via CGEvent.
//  Used as the fallback for terminals/editors with no scripting API
//  (Cursor, VS Code, Warp, Ghostty, …).
//

import AppKit
import ApplicationServices
import Foundation
import os.log

enum KeystrokeInjector {
    private static let logger = Logger(subsystem: "com.claudeisland", category: "Keystrokes")
    private static let returnVirtualKey: CGKeyCode = 0x24

    /// Whether the app is currently trusted for Accessibility (required for CGEventPost into other apps)
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission via the system dialog.
    /// Returns the trust state at call time (may still be false until the user acts).
    @discardableResult
    static func requestAccessibility(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Activate the app owning `pid` and bring its frontmost window forward
    static func activateApp(pid: Int) {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return }
        app.activate(options: [.activateAllWindows])
    }

    /// Inject `text` followed by Return into the currently-focused window.
    /// Caller must ensure the right host is focused (use `activateApp` first).
    /// Returns false if Accessibility is not trusted.
    @discardableResult
    static func typeText(_ text: String, pressReturn: Bool = true) -> Bool {
        guard isAccessibilityTrusted() else {
            logger.warning("Cannot inject keystrokes — Accessibility not granted")
            return false
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create CGEventSource")
            return false
        }

        // Send the entire string in one keyDown event using Unicode strings.
        // Most apps treat this as a paste-equivalent.
        if !text.isEmpty {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                return false
            }
            let utf16 = Array(text.utf16)
            utf16.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        if pressReturn {
            guard let returnDown = CGEvent(keyboardEventSource: source, virtualKey: returnVirtualKey, keyDown: true),
                  let returnUp = CGEvent(keyboardEventSource: source, virtualKey: returnVirtualKey, keyDown: false)
            else {
                return false
            }
            // Tiny delay so the text lands before Return
            usleep(20_000)
            returnDown.post(tap: .cghidEventTap)
            returnUp.post(tap: .cghidEventTap)
        }

        return true
    }
}
