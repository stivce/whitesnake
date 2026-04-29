import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    @Published private(set) var availableVersion: String?

    private var updater: SPUUpdater!

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    override init() {
        super.init()
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
            delegate: self
        )

        try? updater.start()

        // Silent background check on launch
        Task {
            try? await Task.sleep(for: .seconds(2))
            self.updater.checkForUpdatesInBackground()
        }
    }

    func installUpdate() {
        updater.checkForUpdates()
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.availableVersion = item.displayVersionString
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.availableVersion = nil
        }
    }
}
