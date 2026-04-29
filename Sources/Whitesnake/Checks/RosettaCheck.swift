import Foundation

struct RosettaCheck: SystemCheck {
    let id = "rosetta"
    let title = "Rosetta 2"
    let requiresAdmin = true
    let fixAllPriority: Int? = 2

    private let commandRunner: any CommandRunning
    private let pgrepURL: URL
    private let softwareUpdateURL: URL

    init(
        commandRunner: any CommandRunning,
        pgrepURL: URL = URL(fileURLWithPath: "/usr/bin/pgrep"),
        softwareUpdateURL: URL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
    ) {
        self.commandRunner = commandRunner
        self.pgrepURL = pgrepURL
        self.softwareUpdateURL = softwareUpdateURL
    }

    var fixConfirmationMessage: String {
        "Whitesnake will request Rosetta 2 installation with Apple's softwareupdate tool. macOS may ask for administrator approval."
    }

    func check() async -> CheckResult {
        do {
            let result = try await commandRunner.run(
                Command(executableURL: pgrepURL, arguments: ["oahd"], timeoutSeconds: 5)
            )

            if result.exitCode == 0 {
                return CheckResult(status: .ok, details: "Rosetta 2 is installed")
            }

            return CheckResult(status: .missing, details: "Rosetta 2 is not installed")
        } catch let error as CommandRunnerError {
            if case .launchFailed = error {
                return CheckResult(status: .missing, details: "Rosetta 2 process could not be checked")
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
        let parser = SoftwareUpdateProgressParser(subject: "Rosetta 2")
        progressHandler(parser.initialProgress)

        let result = try await commandRunner.runStreaming(
            Command(executableURL: softwareUpdateURL, arguments: ["--install-rosetta", "--agree-to-license"], timeoutSeconds: 300)
        ) { line in
            if let progress = parser.process(line) {
                progressHandler(progress)
            }
        }

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Rosetta 2 installation failed.")
            )
        }

        progressHandler(InstallProgress(stage: .verifying, fractionCompleted: 1, message: "Rosetta 2 installation complete"))
    }
}
