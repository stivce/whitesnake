import Foundation

struct MacOSUpdateCheck: SystemCheck {
    let id = "macos-update"
    let title = "macOS Update"
    let requiresAdmin = true
    let fixButtonTitle: String? = "Update"
    let fixAllPriority: Int? = 1

    private let commandRunner: any CommandRunning
    private let softwareUpdateURL: URL

    init(
        commandRunner: any CommandRunning,
        softwareUpdateURL: URL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
    ) {
        self.commandRunner = commandRunner
        self.softwareUpdateURL = softwareUpdateURL
    }

    var fixConfirmationTitle: String {
        "Install macOS updates?"
    }

    var fixConfirmationMessage: String {
        "Whitesnake will install all available macOS updates. Some may require a restart afterward."
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
        try await fix(progressHandler: { _ in })
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        progressHandler(InstallProgress(stage: .preparing, fractionCompleted: 0.1, message: "Requesting administrator approval"))

        let script = "/usr/sbin/softwareupdate -ia --agree-to-license"

        progressHandler(InstallProgress(stage: .installing, fractionCompleted: 0.4, message: "Installing macOS updates"))

        let result = try await commandRunner.runPrivileged(
            scriptBody: script,
            prompt: "Whitesnake needs to install macOS updates",
            timeoutSeconds: 3600
        )

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "macOS update installation failed.")
            )
        }

        progressHandler(InstallProgress(stage: .verifying, fractionCompleted: 1.0, message: "macOS updates installed"))
    }
}
