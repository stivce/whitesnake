import AppKit
import Sparkle
import SwiftUI

private enum WindowLayout {
    static let aspectRatio: CGFloat = 580.0 / 855.0
    static let maxWidthFraction: CGFloat = 0.8
    static let maxHeightFraction: CGFloat = 0.85
    static let snapGrid: CGFloat = 5.0
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
                let maxUsableWidth = screenFrame.width * WindowLayout.maxWidthFraction
                var targetWidth = round(maxUsableWidth / WindowLayout.snapGrid) * WindowLayout.snapGrid
                var targetHeight = round(targetWidth / WindowLayout.aspectRatio / WindowLayout.snapGrid) * WindowLayout.snapGrid

                let maxHeight = screenFrame.height * WindowLayout.maxHeightFraction
                if targetHeight > maxHeight {
                    targetHeight = round(maxHeight / WindowLayout.snapGrid) * WindowLayout.snapGrid
                    targetWidth = round(targetHeight * WindowLayout.aspectRatio / WindowLayout.snapGrid) * WindowLayout.snapGrid
                }

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
