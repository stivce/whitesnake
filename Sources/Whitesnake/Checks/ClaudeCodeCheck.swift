import Foundation

struct ClaudeCodeCheck: SystemCheck {
    let id = "claude-code"
    let title = "Claude Code"
    let requiresAdmin = false
    let fixAllPriority: Int? = 7

    private let commandRunner: any CommandRunning
    private let claudeURL: URL
    private let npmURL: URL

    init(
        commandRunner: any CommandRunning,
        claudeURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
        npmURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/npm")
    ) {
        self.commandRunner = commandRunner
        self.claudeURL = claudeURL
        self.npmURL = npmURL
    }

    func check() async -> CheckResult {
        do {
            let result = try await commandRunner.run(
                Command(executableURL: claudeURL, arguments: ["--version"], timeoutSeconds: 5)
            )

            if result.exitCode == 0 {
                return CheckResult(status: .ok, details: firstLine(of: result.stdout))
            }

            return CheckResult(status: .missing, details: "Claude Code is not installed")
        } catch let error as CommandRunnerError {
            if case .launchFailed = error {
                return CheckResult(status: .missing, details: "Claude Code is not installed")
            }

            return CheckResult(status: .failed(error.localizedDescription))
        } catch {
            return CheckResult(status: .failed(error.localizedDescription))
        }
    }

    func fix() async throws {
        try await fix(progressHandler: { _ in })
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        guard FileManager.default.isExecutableFile(atPath: npmURL.path) else {
            throw InstallCheckError.commandFailed("npm is required to install Claude Code. Install Node.js via Homebrew first.")
        }

        let parser = BrewInstallProgressParser(packageName: "Claude Code")
        progressHandler(parser.initialProgress)

        let result = try await commandRunner.runStreaming(
            Command(executableURL: npmURL, arguments: ["install", "-g", "@anthropic-ai/claude-code"], timeoutSeconds: 300)
        ) { line in
            if let progress = parser.process(line) {
                progressHandler(progress)
            }
        }

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Claude Code installation failed.")
            )
        }

        progressHandler(InstallProgress(stage: .verifying, fractionCompleted: 1, message: "Claude Code installation complete"))
    }

    private func firstLine(of output: String) -> String? {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }
}
