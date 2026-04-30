import AppKit
import Sparkle
import SwiftUI

private enum WindowLayout {
    static let preferredWidth: CGFloat = 720
    static let preferredHeight: CGFloat = 880
    static let minWidth: CGFloat = 640
    static let minHeight: CGFloat = 860
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
                let targetHeight = maxHeight

                window.minSize = NSSize(width: WindowLayout.minWidth, height: WindowLayout.minHeight)
                let x = (screenFrame.width - targetWidth) / 2 + screenFrame.origin.x
                let y = (screenFrame.height - targetHeight) / 2 + screenFrame.origin.y
                window.setFrame(NSRect(x: x, y: y, width: targetWidth, height: targetHeight), display: true)
            }
        }
    }
}

enum AppPage: Hashable {
    case dashboard
    case generateKey
    case cloneRepo
}

@main
struct WhitesnakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var updateManager = UpdateManager()
    @State private var currentPage: AppPage = .dashboard

    private static let sharedRunner = CommandRunner()
    private var commandRunner: any CommandRunning { Self.sharedRunner }

    init() {
        let runner = Self.sharedRunner
        _viewModel = StateObject(
            wrappedValue: DashboardViewModel(
                checks: [
                    MacOSUpdateCheck(commandRunner: runner),
                    XcodeCLTCheck(commandRunner: runner),
                    HomebrewCheck(commandRunner: runner),
                    RosettaCheck(commandRunner: runner),
                    GitCheck(commandRunner: runner),
                    AnsibleCheck(commandRunner: runner)
                ]
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if currentPage == .dashboard {
                    DashboardView(
                        viewModel: viewModel,
                        updateManager: updateManager,
                        onNext: { currentPage = .generateKey }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                }

                if currentPage == .generateKey {
                    GenerateKeyView(
                        commandRunner: commandRunner,
                        onBack: { currentPage = .dashboard },
                        onNext: { currentPage = .cloneRepo }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        )
                    )
                }

                if currentPage == .cloneRepo {
                    CloneRepoView(
                        commandRunner: commandRunner,
                        onBack: { currentPage = .generateKey }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.2), value: currentPage)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
