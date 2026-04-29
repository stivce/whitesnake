import Foundation

struct XcodeCLTCheck: SystemCheck {
    let id = "xcode-clt"
    let title = "Xcode Command Line Tools"
    let requiresAdmin = true
    let fixButtonTitle: String? = "Install"
    let fixAllPriority: Int? = 3

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
        try await fix(progressHandler: { _ in })
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        progressHandler(InstallProgress(stage: .preparing, fractionCompleted: 0.1, message: "Requesting administrator approval"))

        let script = """
        set -e
        PLACEHOLDER=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        /usr/bin/touch "$PLACEHOLDER"
        PROD=$(/usr/sbin/softwareupdate -l 2>&1 | /usr/bin/grep -E "\\\\*.*Command Line Tools" | /usr/bin/tail -n 1 | /usr/bin/sed -E 's/^ *\\* *Label: //' | /usr/bin/sed -E 's/^ *//')
        if [ -z "$PROD" ]; then
            /bin/rm -f "$PLACEHOLDER"
            echo "No Command Line Tools package available from softwareupdate"
            exit 1
        fi
        /usr/sbin/softwareupdate -i "$PROD" --verbose
        STATUS=$?
        /bin/rm -f "$PLACEHOLDER"
        exit $STATUS
        """

        progressHandler(InstallProgress(stage: .installing, fractionCompleted: 0.4, message: "Installing Command Line Tools"))

        let result = try await commandRunner.runPrivileged(
            scriptBody: script,
            prompt: "Whitesnake needs to install Xcode Command Line Tools",
            timeoutSeconds: 1800
        )

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Xcode Command Line Tools installation failed.")
            )
        }

        progressHandler(InstallProgress(stage: .verifying, fractionCompleted: 1.0, message: "Command Line Tools installed"))
    }
}
