import Foundation

enum GitCheckError: Error, Equatable, LocalizedError {
    case homebrewMissing
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .homebrewMissing:
            return "Homebrew is required to install Git."
        case let .installFailed(message):
            return message
        }
    }
}

struct GitCheck: SystemCheck {
    let id = "git"
    let title = "Git"
    let requiresAdmin = false
    let fixAllPriority: Int? = 4

    private let commandRunner: any CommandRunning
    private let systemGitURL: URL
    private let homebrewGitURL: URL
    private let brewURL: URL

    init(
        commandRunner: any CommandRunning,
        systemGitURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        homebrewGitURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/git"),
        brewURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    ) {
        self.commandRunner = commandRunner
        self.systemGitURL = systemGitURL
        self.homebrewGitURL = homebrewGitURL
        self.brewURL = brewURL
    }

    var fixConfirmationMessage: String {
        "Whitesnake will install Git with Homebrew using a predefined absolute-path command."
    }

    func check() async -> CheckResult {
        let candidates = [systemGitURL, homebrewGitURL]

        for candidate in candidates {
            do {
                let result = try await commandRunner.run(
                    Command(
                        executableURL: candidate,
                        arguments: ["--version"],
                        timeoutSeconds: 5
                    )
                )

                if result.exitCode == 0 {
                    return CheckResult(status: .ok, details: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } catch let error as CommandRunnerError {
                if case .launchFailed = error {
                    continue
                }

                return CheckResult(status: .failed(error.localizedDescription), details: nil)
            } catch {
                return CheckResult(status: .failed(error.localizedDescription), details: nil)
            }
        }

        return CheckResult(status: .missing, details: "Git was not found in the default system locations.")
    }

    func fix() async throws {
        try await fix(progressHandler: { _ in })
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        guard FileManager.default.isExecutableFile(atPath: brewURL.path) else {
            throw GitCheckError.homebrewMissing
        }

        let parser = BrewInstallProgressParser(packageName: "Git")
        progressHandler(parser.initialProgress)

        let result = try await commandRunner.runStreaming(
            Command(executableURL: brewURL, arguments: ["install", "git"], timeoutSeconds: 300)
        ) { line in
            if let progress = parser.process(line) {
                progressHandler(progress)
            }
        }

        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitCheckError.installFailed(message.isEmpty ? "Git installation failed." : message)
        }

        progressHandler(InstallProgress(stage: .verifying, fractionCompleted: 1, message: "Git installation complete"))
    }
}
