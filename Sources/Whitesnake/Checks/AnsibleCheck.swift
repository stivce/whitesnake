import Foundation

struct AnsibleCheck: SystemCheck {
    let id = "ansible"
    let title = "Ansible"
    let requiresAdmin = false
    let fixAllPriority: Int? = 5

    private let commandRunner: any CommandRunning
    private let ansibleURL: URL
    private let brewURL: URL

    init(
        commandRunner: any CommandRunning,
        ansibleURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/ansible"),
        brewURL: URL = CheckSupport.brewURL
    ) {
        self.commandRunner = commandRunner
        self.ansibleURL = ansibleURL
        self.brewURL = brewURL
    }

    func check() async -> CheckResult {
        do {
            let result = try await commandRunner.run(
                Command(executableURL: ansibleURL, arguments: ["--version"], timeoutSeconds: 5)
            )

            if result.exitCode == 0 {
                return CheckResult(status: .ok, details: firstLine(of: result.stdout))
            }

            return CheckResult(status: .missing, details: "Ansible is not installed")
        } catch let error as CommandRunnerError {
            if case .launchFailed = error {
                return CheckResult(status: .missing, details: "Ansible is not installed")
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
        guard FileManager.default.isExecutableFile(atPath: brewURL.path) else {
            throw InstallCheckError.homebrewMissing("Homebrew is required to install Ansible.")
        }

        let parser = BrewInstallProgressParser(packageName: "Ansible")
        progressHandler(parser.initialProgress)

        let result = try await commandRunner.runStreaming(
            Command(executableURL: brewURL, arguments: ["install", "ansible"], timeoutSeconds: 300)
        ) { line in
            if let progress = parser.process(line) {
                progressHandler(progress)
            }
        }

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Ansible installation failed.")
            )
        }

        progressHandler(InstallProgress(stage: .verifying, fractionCompleted: 1, message: "Ansible installation complete"))
    }

    private func firstLine(of output: String) -> String? {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }
}
