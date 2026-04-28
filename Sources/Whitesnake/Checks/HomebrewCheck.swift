import Foundation

struct HomebrewCheck: SystemCheck {
    let id = "homebrew"
    let title = "Homebrew"
    let requiresAdmin = false
    let fixButtonTitle: String? = "Open"

    private let commandRunner: any CommandRunning
    private let brewURL: URL
    private let openURL: URL
    private let installerURL: String

    init(
        commandRunner: any CommandRunning,
        brewURL: URL = CheckSupport.brewURL,
        openURL: URL = CheckSupport.openURL,
        installerURL: String = "https://brew.sh"
    ) {
        self.commandRunner = commandRunner
        self.brewURL = brewURL
        self.openURL = openURL
        self.installerURL = installerURL
    }

    var fixConfirmationTitle: String {
        "Open Homebrew installer?"
    }

    var fixConfirmationMessage: String {
        "Homebrew installation is handled manually in this MVP. Whitesnake will open the official Homebrew installer page."
    }

    func check() async -> CheckResult {
        do {
            let versionResult = try await commandRunner.run(
                Command(executableURL: brewURL, arguments: ["--version"], timeoutSeconds: 5)
            )

            guard versionResult.exitCode == 0 else {
                return CheckResult(status: .missing, details: "Homebrew is not installed")
            }

            let version = CheckSupport.trimmedOutput(versionResult)

            let outdatedResult = try await commandRunner.run(
                Command(executableURL: brewURL, arguments: ["outdated", "--formula", "brew"], timeoutSeconds: 30)
            )

            if outdatedResult.exitCode == 0,
               !outdatedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CheckResult(status: .updateAvailable, details: version)
            }

            return CheckResult(status: .ok, details: version)
        } catch let error as CommandRunnerError {
            if case .launchFailed = error {
                return CheckResult(status: .missing, details: "Homebrew is not installed")
            }

            return CheckResult(status: .failed(error.localizedDescription))
        } catch {
            return CheckResult(status: .failed(error.localizedDescription))
        }
    }

    func fix() async throws {
        let result = try await commandRunner.run(
            Command(executableURL: openURL, arguments: [installerURL], timeoutSeconds: 10)
        )

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Failed to open the Homebrew installer page.")
            )
        }
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        progressHandler(InstallProgress(stage: .preparing, fractionCompleted: 0.1, message: "Opening Homebrew installer"))
        try await fix()
        progressHandler(InstallProgress(stage: .waitingForUser, fractionCompleted: 0.25, message: "Homebrew installer page opened"))
    }
}
