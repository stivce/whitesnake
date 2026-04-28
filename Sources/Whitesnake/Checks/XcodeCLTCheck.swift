import Foundation

struct XcodeCLTCheck: SystemCheck {
    let id = "xcode-clt"
    let title = "Xcode Command Line Tools"
    let requiresAdmin = false
    let fixAllPriority: Int? = 1

    private let commandRunner: any CommandRunning
    private let xcodeSelectURL: URL

    init(
        commandRunner: any CommandRunning,
        xcodeSelectURL: URL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    ) {
        self.commandRunner = commandRunner
        self.xcodeSelectURL = xcodeSelectURL
    }

    var fixConfirmationMessage: String {
        "Whitesnake will request the system Command Line Tools installer. macOS may show its own installation prompt."
    }

    func check() async -> CheckResult {
        do {
            let result = try await commandRunner.run(
                Command(executableURL: xcodeSelectURL, arguments: ["-p"], timeoutSeconds: 5)
            )

            guard result.exitCode == 0 else {
                return CheckResult(status: .missing, details: "Xcode Command Line Tools are not installed")
            }

            return CheckResult(status: .ok, details: CheckSupport.trimmedOutput(result))
        } catch let error as CommandRunnerError {
            if case .launchFailed = error {
                return CheckResult(status: .missing, details: "xcode-select is unavailable")
            }

            return CheckResult(status: .failed(error.localizedDescription))
        } catch {
            return CheckResult(status: .failed(error.localizedDescription))
        }
    }

    func fix() async throws {
        let result = try await commandRunner.run(
            Command(executableURL: xcodeSelectURL, arguments: ["--install"], timeoutSeconds: 10)
        )

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Failed to start Xcode Command Line Tools installation.")
            )
        }
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        let parser = XcodeCLTInstallProgressParser()
        progressHandler(parser.initialProgress)

        let result = try await commandRunner.runStreaming(
            Command(executableURL: xcodeSelectURL, arguments: ["--install"], timeoutSeconds: 10)
        ) { line in
            if let progress = parser.process(line) {
                progressHandler(progress)
            }
        }

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Failed to start Xcode Command Line Tools installation.")
            )
        }

        progressHandler(InstallProgress(stage: .waitingForUser, fractionCompleted: 0.28, message: "Waiting for the macOS installer dialog"))
    }
}
