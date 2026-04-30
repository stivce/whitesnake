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
    let title = "Git & GitHub CLI"
    let requiresAdmin = false
    let fixAllPriority: Int? = 5

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
        "Whitesnake will install Git and the GitHub CLI with Homebrew using predefined absolute-path commands."
    }

    func check() async -> CheckResult {
        let gitCandidates = [systemGitURL, homebrewGitURL]

        for candidate in gitCandidates {
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

        return CheckResult(
            status: .missing,
            details: "Git or GitHub CLI was not found in the default locations."
        )
    }

    func fix() async throws {
        try await fix(progressHandler: { _ in })
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        guard FileManager.default.isExecutableFile(atPath: brewURL.path) else {
            throw GitCheckError.homebrewMissing
        }

        let gitParser = BrewInstallProgressParser(packageName: "Git")
        progressHandler(gitParser.initialProgress)

        let gitResult = try await commandRunner.runStreaming(
            Command(executableURL: brewURL, arguments: ["install", "git"], timeoutSeconds: 300)
        ) { line in
            if let progress = gitParser.process(line) {
                progressHandler(progress)
            }
        }

        guard gitResult.exitCode == 0 else {
            let message = gitResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitCheckError.installFailed(message.isEmpty ? "Git installation failed." : message)
        }

        let ghParser = BrewInstallProgressParser(packageName: "GitHub CLI")
        progressHandler(ghParser.initialProgress)

        let ghResult = try await commandRunner.runStreaming(
            Command(executableURL: brewURL, arguments: ["install", "gh"], timeoutSeconds: 300)
        ) { line in
            if let progress = ghParser.process(line) {
                progressHandler(progress)
            }
        }

        guard ghResult.exitCode == 0 else {
            let message = ghResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitCheckError.installFailed(message.isEmpty ? "GitHub CLI installation failed." : message)
        }

        progressHandler(
            InstallProgress(
                stage: .verifying,
                fractionCompleted: 1,
                message: "Git & GitHub CLI installation complete"
            )
        )
    }
}
