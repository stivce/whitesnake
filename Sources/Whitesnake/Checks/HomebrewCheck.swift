import Foundation

struct HomebrewCheck: SystemCheck {
    let id = "homebrew"
    let title = "Homebrew"
    let requiresAdmin = true
    let fixButtonTitle: String? = "Install"
    let fixAllPriority: Int? = 2

    private let commandRunner: any CommandRunning
    private let brewURL: URL

    init(
        commandRunner: any CommandRunning,
        brewURL: URL = CheckSupport.brewURL
    ) {
        self.commandRunner = commandRunner
        self.brewURL = brewURL
    }

    var fixConfirmationTitle: String {
        "Install Homebrew?"
    }

    var fixConfirmationMessage: String {
        "Whitesnake will install Homebrew into /opt/homebrew and add it to your shell profile. macOS will ask for your password once."
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
        try await fix(progressHandler: { _ in })
    }

    func fix(progressHandler: @escaping @Sendable (InstallProgress) -> Void) async throws {
        progressHandler(InstallProgress(stage: .preparing, fractionCompleted: 0.1, message: "Requesting administrator approval"))

        let script = """
        set -e
        USER_NAME=$(stat -f%Su /dev/console)
        USER_HOME=$(/usr/bin/dscl . -read /Users/$USER_NAME NFSHomeDirectory | awk '{print $2}')
        BREW_PREFIX=/opt/homebrew

        mkdir -p "$BREW_PREFIX"
        /usr/bin/curl -fsSL https://github.com/Homebrew/brew/tarball/master | /usr/bin/tar xz --strip 1 -C "$BREW_PREFIX"
        /usr/sbin/chown -R "$USER_NAME":admin "$BREW_PREFIX"
        /bin/chmod -R go-w "$BREW_PREFIX" || true

        /usr/bin/sudo -u "$USER_NAME" "$BREW_PREFIX/bin/brew" --version
        /usr/bin/sudo -u "$USER_NAME" "$BREW_PREFIX/bin/brew" update --force --quiet || true

        ZPROFILE="$USER_HOME/.zprofile"
        if ! /usr/bin/grep -q 'brew shellenv' "$ZPROFILE" 2>/dev/null; then
            /bin/echo "" >> "$ZPROFILE"
            /bin/echo "# Homebrew" >> "$ZPROFILE"
            /bin/echo 'eval "$('"$BREW_PREFIX"'/bin/brew shellenv)"' >> "$ZPROFILE"
            /usr/sbin/chown "$USER_NAME":staff "$ZPROFILE"
        fi
        """

        progressHandler(InstallProgress(stage: .downloading, fractionCompleted: 0.3, message: "Downloading and installing Homebrew"))

        let result = try await commandRunner.runPrivileged(
            scriptBody: script,
            prompt: "Whitesnake needs to install Homebrew",
            timeoutSeconds: 1800
        )

        guard result.exitCode == 0 else {
            throw InstallCheckError.commandFailed(
                CheckSupport.failureMessage(result, fallback: "Homebrew installation failed.")
            )
        }

        progressHandler(InstallProgress(stage: .verifying, fractionCompleted: 1.0, message: "Homebrew installed"))
    }
}
