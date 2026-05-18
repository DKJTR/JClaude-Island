import AppKit
import IOKit
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?
    private var updateCheckTimer: Timer?
    /// Eager socket-server starter; kept alive so the hook socket is up
    /// regardless of whether the NotchView has appeared yet.
    private var eagerSessionMonitor: ClaudeSessionMonitor?

    static var shared: AppDelegate?
    let updater: SPUUpdater
    private let userDriver: NotchUserDriver

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        userDriver = NotchUserDriver()
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        super.init()
        AppDelegate.shared = self

        do {
            try updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        HookInstaller.installIfNeeded()
        // Seed routing.txt so the Python hook has a value to read even before
        // the user opens the menu / changes the setting.
        AppSettings.writeRoutingFile(AppSettings.questionRouting)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Start the hook socket server BEFORE Bluetooth/Media services.
        // BluetoothService.startMonitoring can synchronously trigger a TCC
        // prompt on ad-hoc-signed dev builds, which can block the main thread
        // until the user responds — leaving the socket unbound and every
        // Claude Code hook seeing "Connection refused." Eager-start the
        // monitor here so the socket is ready regardless. NotchView's onAppear
        // also calls startMonitoring (idempotent guard prevents double-bind).
        let monitor = ClaudeSessionMonitor()
        monitor.startMonitoring()
        eagerSessionMonitor = monitor

        // Start media and bluetooth monitoring after the socket is up
        MediaRemoteService.shared.startMonitoring()
        BluetoothService.shared.startMonitoring()

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        }

        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let updater = self?.updater, updater.canCheckForUpdates else { return }
            updater.checkForUpdates()
        }
    }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateCheckTimer?.invalidate()
        screenObserver = nil
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jclaude.island"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
