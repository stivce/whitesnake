import Foundation

struct MacOSUpdateCheck: SystemCheck {
    let id = "macos-update"
    let title = "macOS Update"
    let requiresAdmin = true
    let fixButtonTitle: String? = "Open"

    private let commandRunner: any CommandRunning
    private let softwareUpdateURL: URL
    private let openURL: URL
    private let settingsURL: String

    init(
        commandRunner: any CommandRunning,
        softwareUpdateURL: URL = URL(fileURLWithPath: "/usr/sbin/softwareupdate"),
        openURL: URL = CheckSupport.openURL,
        settingsURL: String = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    ) {
        self.commandRunner = commandRunner
        self.softwareUpdateURL = softwareUpdateURL
        self.openURL = openURL
        self.settingsURL = settingsURL
    }

    var fixConfirmationTitle: String {
        "Open System Settings?"
    }

    var fixConfirmationMessage: String {
        "macOS updates are handled manually because they may require a reboot. Whitesnake will open Software Update settings for you."
    }

    func check() async -> CheckResult {
        do {
            let result = try await commandRunner.run(
                Command(executableURL: softwareUpdateURL, arguments: ["-l"], timeoutSeconds: 30)
            )

            let output = [result.stdout, result.stderr].joined(separator: "\n")
            let normalizedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedOutput.localizedCaseInsensitiveContains("No new software available") {
                return CheckResult(status: .ok, details: "No macOS updates available")
            }

            if normalizedOutput.localizedCaseInsensitiveContains("Label:") || normalizedOutput.localizedCaseInsensitiveContains("Software Update found") {
                return CheckResult(status: .updateAvailable, details: "macOS update available")
            }

            return CheckResult(status: .ok, details: normalizedOutput.isEmpty ? "No macOS updates available" : normalizedOutput)
        } catch {
            return CheckResult(status: .failed(error.localizedDescription))
        }
    }

    func fix() async throws {
        let result = try await commandRunner.run(
            Command(executableURL: openURL, arguments: [settingsURL], timeoutSeconds: 10)
        )

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Failed to open Software Update settings.")
            )
        }
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        progressHandler(InstallProgress(stage: .preparing, fractionCompleted: 0.1, message: "Opening Software Update settings"))
        try await fix()
        progressHandler(InstallProgress(stage: .waitingForUser, fractionCompleted: 0.25, message: "Software Update settings opened"))
    }
}
