//
//  ClaudeDirPickerRow.swift
//  ClaudeIsland
//
//  Settings row that lets users pick a custom Claude config directory via
//  the native macOS folder picker. Defaults to auto-detection (CLAUDE_CONFIG_DIR,
//  ~/.config/claude/, or ~/.claude/).
//

import AppKit
import SwiftUI

struct ClaudeDirPickerRow: View {
    @State private var currentValue: String = AppSettings.claudeDirectoryName
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: openFolderPicker) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text("Claude Directory")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                Text(displayValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isCustom {
                    // Reset button — clears the override and returns to auto-detect
                    Button(action: resetToAutoDetect) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Reset to auto-detect")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear { currentValue = AppSettings.claudeDirectoryName }
    }

    // MARK: - Presentation

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    /// Whether the user has set a custom override (vs. falling back to auto-detect).
    private var isCustom: Bool {
        !currentValue.isEmpty && currentValue != ".claude"
    }

    /// Human-readable representation of the active directory. Shortens paths
    /// under the user's home to `~/...` and shows `Auto-detect` when no
    /// override is set.
    private var displayValue: String {
        guard isCustom else { return "Auto-detect" }

        let path = currentValue.hasPrefix("/")
            ? currentValue
            : NSHomeDirectory() + "/" + currentValue

        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Actions

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Claude Config Directory"
        panel.message = "Select the folder Claude Code uses (typically ~/.claude or ~/.config/claude)."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = false
        panel.directoryURL = ClaudePaths.claudeDir

        // Lift the picker above the notch's window level (mainMenu + 3)
        panel.level = .popUpMenu

        // The notch window catches clicks over its whole frame when open, which
        // blocks interaction with anything below (even a higher-level window,
        // because hit-testing on the notch consumes the event). Let clicks pass
        // through the notch while the picker is modal, then restore.
        let notchWindow = NSApp.windows.first { $0 is NotchPanel }
        let wasIgnoring = notchWindow?.ignoresMouseEvents ?? true
        notchWindow?.ignoresMouseEvents = true

        let response = panel.runModal()

        notchWindow?.ignoresMouseEvents = wasIgnoring

        if response == .OK, let url = panel.url {
            applyChoice(path: url.path)
        }
    }

    private func resetToAutoDetect() {
        applyChoice(path: "")
    }

    private func applyChoice(path: String) {
        currentValue = path
        AppSettings.claudeDirectoryName = path
        ClaudePaths.invalidateCache()
        HookInstaller.installIfNeeded()
    }
}
