import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    @Published private(set) var availableVersion: String?

    private var updaterController: SPUStandardUpdaterController!
    private var hasChecked = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // Silent background check on launch
        Task {
            try? await Task.sleep(for: .seconds(2))
            await checkForUpdatesSilently()
        }
    }

    private func checkForUpdatesSilently() async {
        guard let updater = updaterController.updater else { return }
        await updater.checkForUpdatesInBackground()
    }

    func installUpdate() {
        updaterController.checkForUpdates(nil)
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.availableVersion = version
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.availableVersion = nil
        }
    }
}
