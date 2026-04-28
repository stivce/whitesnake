import AppKit
import Sparkle
import SwiftUI

private enum WindowLayout {
    static let preferredWidth: CGFloat = 720
    static let preferredHeight: CGFloat = 900
    static let minWidth: CGFloat = 640
    static let minHeight: CGFloat = 880
    static let maxScreenFraction: CGFloat = 0.95
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.forEach { window in
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.isMovableByWindowBackground = true
                window.styleMask.insert(.fullSizeContentView)
                window.toolbarStyle = .unifiedCompact

                guard let screen = window.screen ?? NSScreen.main else {
                    return
                }
                let screenFrame = screen.visibleFrame
                let maxWidth = screenFrame.width * WindowLayout.maxScreenFraction
                let maxHeight = screenFrame.height * WindowLayout.maxScreenFraction
                let targetWidth = min(WindowLayout.preferredWidth, maxWidth)
                let targetHeight = min(WindowLayout.preferredHeight, maxHeight)

                window.minSize = NSSize(width: WindowLayout.minWidth, height: WindowLayout.minHeight)
                let x = (screenFrame.width - targetWidth) / 2 + screenFrame.origin.x
                let y = (screenFrame.height - targetHeight) / 2 + screenFrame.origin.y
                window.setFrame(NSRect(x: x, y: y, width: targetWidth, height: targetHeight), display: true)
            }
        }
    }

}

@main
struct WhitesnakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: DashboardViewModel
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        let commandRunner = CommandRunner()
        _viewModel = StateObject(
            wrappedValue: DashboardViewModel(
                checks: [
                    MacOSUpdateCheck(commandRunner: commandRunner),
                    XcodeCLTCheck(commandRunner: commandRunner),
                    HomebrewCheck(commandRunner: commandRunner),
                    RosettaCheck(commandRunner: commandRunner),
                    GitCheck(commandRunner: commandRunner),
                    AnsibleCheck(commandRunner: commandRunner)
                ]
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
